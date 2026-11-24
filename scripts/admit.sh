#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Admit one release.
#
#   admit.sh <owner/repo> <tag> <outdir>
#
# Downloads the sidecars, checks that a publisher pushed the tag (config `publishers`), verifies
# the trust chain with github-actions' gpg-verify-trust-chain.sh (VERIFY_CHAIN_URL; root key from
# MASTER_PUBLIC_ASC and MASTER_FPR), then checks the packages.
#
# Writes <outdir>/result.json with status published, skipped, or rejected (plus reasons), and the
# admitted packages under <outdir>/files/. Exits non-zero only for infrastructure errors (API,
# downloads), which leave nothing to record so the next poll retries the release.
#
# Environment: GITHUB_TOKEN, GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID,
#   MASTER_PUBLIC_ASC, MASTER_FPR.
source "$(dirname "$0")/lib/base.sh"
source "$(dirname "$0")/lib/config.sh"
source "$(dirname "$0")/lib/github.sh"
source "$(dirname "$0")/lib/package.sh"
source "$(dirname "$0")/lib/state.sh"

SIDECARS=(checksums.txt checksums.txt.asc pubkey-signing.asc pubkey-repo.asc)

################################################################################
# Updates the admission's result.json with a jq filter.
# Arguments:
#   <outdir> <jq filter> [jq args...]
################################################################################
update_result() {
  local result="$1/result.json" filter="$2"
  shift 2
  jq "$@" "${filter}" "${result}" > "${result}.tmp" && mv "${result}.tmp" "${result}"
}

################################################################################
# Ends the admission with a status and its reasons.
# Arguments:
#   <outdir> <published|skipped|rejected> [reason...]
################################################################################
finish_admission() {
  local out="$1" status="$2"
  shift 2
  update_result "${out}" '.status = $st | .reasons += $r' --arg st "${status}" \
    --argjson r "$(jq -nc '$ARGS.positional' --args "$@")"
  log__info "admit $(jq -r .key "${out}/result.json"): ${status}${*:+ ($*)}"
  exit 0
}

################################################################################
# Rejects the release unless everyone who pushed its tag or ran its push runs may publish this
# repo (config `publishers`): the service repo's release workflow signs any `v*` tag.
#
# Every run counts, not just the latest: the API doesn't say which run published the release.
# E.g. a non-publisher's run publishes, then a publisher re-pushes the tag; that run fails the
# draft guard, so the latest run is the publisher's but the release isn't. No run: rejected.
# Arguments:
#   <outdir> <owner/repo> <tag>
################################################################################
reject_if_publisher_not_allowed() {
  local out="$1" repo="$2" tag="$3" pubs actors reasons=()
  pubs="$(config__get .publishers)"
  actors="$(github__tag_push_actor_list "${repo}" "${tag}")"
  [[ "$(jq length <<< "${actors}")" -gt 0 ]] \
    || finish_admission "${out}" rejected \
      "no push run found for tag ${tag}, so its publisher can't be checked"
  # Usernames are labels only; flag a listed ID whose username has since changed.
  base__jq -r --argjson p "${pubs}" \
    'import "publishers" as publishers; publishers::rename_warnings($p)' <<< "${actors}" \
    | while read -r line; do log__info "${line}"; done
  mapfile -t reasons < <(base__jq -r --argjson p "${pubs}" --arg repo "${repo}" \
    'import "publishers" as publishers; publishers::unauthorized_actor_reasons($p; $repo)' \
    <<< "${actors}")
  [[ "${#reasons[@]}" -eq 0 ]] || finish_admission "${out}" rejected "${reasons[@]}"
}

################################################################################
# Downloads the release's sidecars (SIDECARS) into release/; rejects the release when any is
# missing.
# Arguments:
#   <outdir> <owner/repo> <tag>
################################################################################
download_sidecars() {
  local out="$1" repo="$2" tag="$3" f id missing=()
  github__release_asset_list "${repo}" "${tag}" > "${out}/assets.json"
  for f in "${SIDECARS[@]}"; do
    jq -e --arg n "${f}" 'any(.name == $n)' "${out}/assets.json" > /dev/null \
      || missing+=("missing ${f}")
  done
  [[ "${#missing[@]}" -eq 0 ]] || finish_admission "${out}" rejected "${missing[@]}"
  for f in "${SIDECARS[@]}"; do
    id="$(jq -r --arg n "${f}" '.[] | select(.name == $n) | .id' "${out}/assets.json")"
    github__release_asset_download "${repo}" "${id}" "${out}/release/${f}"
  done
}

################################################################################
# Verifies the trust chain and checksums.txt's signature with github-actions'
# gpg-verify-trust-chain.sh, then records the repo key; rejects the release when it fails.
# Globals:
#   VERIFY_CHAIN_URL, MASTER_PUBLIC_ASC, MASTER_FPR
# Arguments:
#   <outdir> <owner/repo>
################################################################################
verify_trust_chain() {
  local out="$1" repo="$2" fpr
  curl -fsSL --retry 3 "${VERIFY_CHAIN_URL}" -o "${out}/verify-chain.sh"
  MASTER_PUBLIC_KEY="${MASTER_PUBLIC_ASC}" MASTER_FINGERPRINT="${MASTER_FPR}" \
    REPO_KEY_FILE="${out}/release/pubkey-repo.asc" \
    SIGNING_KEY_FILE="${out}/release/pubkey-signing.asc" \
    FILES="${out}/release/checksums.txt" REPO="${repo}" OUTPUT_FILE="${out}/verify.out" \
    bash "${out}/verify-chain.sh" >&2 \
    || finish_admission "${out}" rejected \
      "trust chain or checksums.txt signature didn't verify (see the run log)"
  fpr="$(sed -n 's/^fingerprint-repo=//p' "${out}/verify.out")"
  update_result "${out}" '.repo_key = $f' --arg f "${fpr^^}"
}

################################################################################
# Rejects the release when the repo key that signed it is on its repo's deny list (config
# `deny`), with the entry's reason.
# Arguments:
#   <outdir> <owner/repo>
################################################################################
reject_if_repo_key_denied() {
  local out="$1" repo="$2" repo_key entry
  repo_key="$(jq -r .repo_key "${out}/result.json")"
  entry="$(config__get .repos | jq -c --arg repo "${repo}" --arg f "${repo_key}" \
    'first(.[$repo].deny[] | select(.fingerprint == $f))')"
  if [[ -n "${entry}" ]]; then
    finish_admission "${out}" rejected \
      "repo key ${repo_key} is denied: $(jq -r '.reason // "no reason given"' <<< "${entry}")"
  fi
}

################################################################################
# The packages checksums.txt lists ("<sha256>  <name>", or "<sha256> *<name>").
# Arguments:
#   <outdir>
# Outputs:
#   {name: sha256} as JSON on stdout.
################################################################################
read_checksums() {
  local out="$1" hash name
  while read -r hash name; do
    name="${name#\*}"
    if [[ "${name}" == *.rpm || "${name}" == *.deb ]]; then
      printf '%s\t%s\n' "${name}" "${hash}"
    fi
  done < "${out}/release/checksums.txt" \
    | jq -Rnc '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

################################################################################
# Downloads each listed package into files/; rejects the release when one isn't attached or its
# sha256 doesn't match.
# Arguments:
#   <outdir> <owner/repo> <checksums (read_checksums)>
################################################################################
download_packages() {
  local out="$1" repo="$2" checksums="$3" name want id got reasons=()
  while IFS=$'\t' read -r name want; do
    # GitHub renames "~" to "." in asset names.
    id="$(jq -r --arg a "${name}" --arg b "${name//\~/.}" \
      '[.[] | select(.name == $a or .name == $b)][0].id // empty' "${out}/assets.json")"
    if [[ -z "${id}" ]]; then
      reasons+=("${name} is listed in checksums.txt but not attached")
      continue
    fi
    github__release_asset_download "${repo}" "${id}" "${out}/files/${name}"
    got="$(sha256sum "${out}/files/${name}" | cut -d' ' -f1)"
    [[ "${got}" == "${want}" ]] || reasons+=("${name}: sha256 ${got} doesn't match checksums.txt")
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "${checksums}")
  [[ "${#reasons[@]}" -eq 0 ]] || finish_admission "${out}" rejected "${reasons[@]}"
}

################################################################################
# Each downloaded package's metadata, with its sha256, dropping (and deleting) packages of
# architectures the distributor doesn't publish.
# Arguments:
#   <outdir> <checksums (read_checksums)>
# Outputs:
#   The packages as a JSON array on stdout.
################################################################################
read_package_metadata() {
  local out="$1" checksums="$2" name sha info arch infos='[]'
  while IFS=$'\t' read -r name sha; do
    info="$(package__metadata "${out}/files/${name}")" \
      || log__fatal "can't read package metadata: ${name}"
    arch="$(jq -r .arch <<< "${info}")"
    if ! package__is_arch_supported "$(jq -r .format <<< "${info}")" "${arch}"; then
      log__info "admit: ignoring ${name} (architecture ${arch})"
      rm -f "${out}/files/${name}"
      continue
    fi
    infos="$(jq -c --argjson i "${info}" --arg sha "${sha}" '. + [$i + {sha256: $sha}]' \
      <<< "${infos}")"
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "${checksums}")
  echo "${infos}"
}

################################################################################
# Skips the release quietly when any package has a prerelease version.
# Arguments:
#   <outdir> <packages (read_package_metadata)>
################################################################################
skip_if_prerelease() {
  local out="$1" infos="$2"
  if base__jq -e 'import "version" as version; any(.version | version::is_prerelease)' \
    <<< "${infos}" > /dev/null; then
    rm -rf "${out}/files"
    finish_admission "${out}" skipped "prerelease version"
  fi
}

################################################################################
# The packages whose version isn't major.minor.patch.
# Arguments:
#   <packages (read_package_metadata)>
# Outputs:
#   A reason per package on stdout.
################################################################################
version_rejection_reasons() {
  base__jq -r 'import "version" as version; .[] | select(.version | version::is_semver | not)
    | "\(.filename): version \(.version) isn'"'"'t major.minor.patch"' <<< "$1"
}

################################################################################
# Each package's rejection reasons under the name, duplicate, and already-admitted rules. State
# goes to jq on stdin: it outgrows the command-line argument limit.
# Arguments:
#   <owner/repo> <packages (read_package_metadata)>
# Outputs:
#   The packages as JSON on stdout, each with its reasons ([] when it passes).
################################################################################
package_rejection_reasons() {
  state__json | base__jq -c --arg repo "$1" --argjson cfg "$(config__get .repos)" \
    --argjson infos "$2" \
    'import "admit" as admit;
      . as $state | $infos | admit::add_package_rejection_reasons($state; $cfg; $repo)'
}

################################################################################
# Rejects the release on any version or package rule; else admits its packages.
# Arguments:
#   <outdir> <owner/repo> <packages (read_package_metadata)>
################################################################################
admit_or_reject_packages() {
  local out="$1" repo="$2" infos="$3" reasons checked
  mapfile -t reasons < <(version_rejection_reasons "${infos}")
  checked="$(package_rejection_reasons "${repo}" "${infos}")"
  mapfile -t -O "${#reasons[@]}" reasons < <(jq -r '.[].reasons[]' <<< "${checked}")
  [[ "${#reasons[@]}" -eq 0 ]] || finish_admission "${out}" rejected "${reasons[@]}"
  update_result "${out}" '.packages = [$c[] | del(.reasons)
    + {path: "files/\(.filename)", status: "published"}]' --argjson c "${checked}"
  finish_admission "${out}" published
}

################################################################################
# Admits one release: writes a pending result.json, then runs the checks in order. The first
# that fails ends the admission (finish_admission exits).
# Arguments:
#   <owner/repo> <tag> <outdir>
################################################################################
main() {
  local repo="$1" tag="$2" out checksums infos
  base__env_require GITHUB_TOKEN GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_RUN_ID \
    MASTER_PUBLIC_ASC MASTER_FPR
  mkdir -p "$3/release" "$3/files"
  out="$(cd "$3" && pwd)"
  jq -n --arg key "${repo}@${tag}" --arg repo "${repo}" --arg tag "${tag}" \
    --arg at "$(base__timestamp_utc)" --arg run "$(github__current_run_url)" \
    '{key: $key, repo: $repo, tag: $tag, status: "pending", at: $at, run: $run, reasons: [],
      packages: []}' \
    > "${out}/result.json"
  download_sidecars "${out}" "${repo}" "${tag}"
  reject_if_publisher_not_allowed "${out}" "${repo}" "${tag}"
  verify_trust_chain "${out}" "${repo}"
  reject_if_repo_key_denied "${out}" "${repo}"
  checksums="$(read_checksums "${out}")"
  download_packages "${out}" "${repo}" "${checksums}"
  infos="$(read_package_metadata "${out}" "${checksums}")"
  skip_if_prerelease "${out}" "${infos}"
  admit_or_reject_packages "${out}" "${repo}" "${infos}"
}

[[ "$#" -eq 3 ]] || log__fatal "usage: admit.sh <owner/repo> <tag> <outdir>"
main "$@"
