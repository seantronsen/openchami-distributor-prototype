#!/usr/bin/env bash
# Admit one release.
#
#   admit.sh <owner/repo> <tag> <outdir>
#
# Downloads the sidecars, verifies the trust chain with github-actions' gpg-verify-trust-chain.sh
# (VERIFY_CHAIN_URL; root key from MASTER_PUBLIC_ASC and MASTER_FPR), then checks the packages.
#
# Writes <outdir>/result.json with status published, skipped, or rejected (plus reasons), and the
# admitted packages under <outdir>/files/. Exits non-zero only for infrastructure errors (API,
# downloads), which leave nothing to record so the next poll retries the release.
source "$(dirname "$0")/lib.sh"

[[ $# -eq 3 ]] || die "usage: admit.sh <owner/repo> <tag> <outdir>"
repo=$1 tag=$2 out=$3
mkdir -p "$out/release" "$out/files"
out=$(cd "$out" && pwd)
result=$out/result.json
SIDECARS=(checksums.txt checksums.txt.asc pubkey-signing.asc pubkey-repo.asc)

jq -n --arg key "$repo@$tag" --arg repo "$repo" --arg tag "$tag" --arg at "$(now)" --arg run "$(run_url)" \
  '{key: $key, repo: $repo, tag: $tag, status: "pending", at: $at, run: $run, reasons: [], packages: []}' > "$result"

set_result() { # <jq filter> [jq args...]
  local filter=$1; shift
  jq "$@" "$filter" "$result" > "$result.tmp" && mv "$result.tmp" "$result"
}

# Ends the admission with a status (and reasons, one per argument).
finish() { # <status> [reason...]
  local st=$1; shift
  set_result '.status = $st | .reasons += $r' --arg st "$st" --argjson r "$(jq -nc '$ARGS.positional' --args "$@")"
  log "admit $repo@$tag: $st${*:+ ($*)}"
  exit 0
}

cfg=$(config_json)

fetch_sidecars() {
  release_assets "$repo" "$tag" > "$out/assets.json"
  local missing=()
  for f in "${SIDECARS[@]}"; do
    jq -e --arg n "$f" 'any(.name == $n)' "$out/assets.json" > /dev/null || missing+=("missing $f")
  done
  [[ ${#missing[@]} -eq 0 ]] || finish rejected "${missing[@]}"
  for f in "${SIDECARS[@]}"; do
    asset_fetch "$repo" "$(jq -r --arg n "$f" '.[] | select(.name == $n) | .id' "$out/assets.json")" \
      "$out/release/$f"
  done
}

verify_chain() {
  local fpr
  curl -fsSL --retry 3 "$VERIFY_CHAIN_URL" -o "$out/verify-chain.sh"
  MASTER_PUBLIC_KEY=${MASTER_PUBLIC_ASC:?MASTER_PUBLIC_ASC is required} \
    MASTER_FINGERPRINT=${MASTER_FPR:?MASTER_FPR is required} \
    REPO_KEY_FILE=$out/release/pubkey-repo.asc SIGNING_KEY_FILE=$out/release/pubkey-signing.asc \
    FILES=$out/release/checksums.txt REPO=$repo OUTPUT_FILE=$out/verify.out \
    bash "$out/verify-chain.sh" >&2 \
    || finish rejected "trust chain or checksums.txt signature didn't verify (see the run log)"
  fpr=$(sed -n 's/^fingerprint-repo=//p' "$out/verify.out")
  set_result '.repo_key = $f' --arg f "${fpr^^}"
}

check_packages() {
  local repo_key reasons=() denied
  repo_key=$(jq -r .repo_key "$result")
  denied=$(jq -r --arg repo "$repo" --arg f "$repo_key" \
    '.[] | select(.name == $repo) | (.deny // [])[] | select((.fingerprint | ascii_upcase) == $f) | .reason // "no reason given"' \
    <<< "$cfg" | head -1)
  [[ -z $denied ]] || finish rejected "repo key $repo_key is denied: $denied"

  # Packages listed in checksums.txt ("<sha256>  <name>", or "<sha256> *<name>").
  local -A want=()
  local hash name
  while read -r hash name; do
    name=${name#\*}
    [[ $name == *.rpm || $name == *.deb ]] && want[$name]=$hash
  done < "$out/release/checksums.txt"

  local id got
  for name in "${!want[@]}"; do
    # GitHub renames "~" to "." in asset names.
    id=$(jq -r --arg a "$name" --arg b "${name//\~/.}" \
      '[.[] | select(.name == $a or .name == $b)][0].id // empty' "$out/assets.json")
    if [[ -z $id ]]; then
      reasons+=("$name is listed in checksums.txt but not attached")
      continue
    fi
    asset_fetch "$repo" "$id" "$out/files/$name"
    got=$(sha256sum "$out/files/$name" | cut -d' ' -f1)
    [[ $got == "${want[$name]}" ]] || reasons+=("$name: sha256 $got doesn't match checksums.txt")
  done
  [[ ${#reasons[@]} -eq 0 ]] || finish rejected "${reasons[@]}"

  local info infos='[]'
  for name in "${!want[@]}"; do
    info=$(package_info "$out/files/$name") || die "can't read package metadata: $name"
    if ! supported_arch "$(jq -r .format <<< "$info")" "$(jq -r .arch <<< "$info")"; then
      log "admit: ignoring $name (architecture $(jq -r .arch <<< "$info"))"
      rm -f "$out/files/$name"
      continue
    fi
    infos=$(jq -c --argjson i "$info" --arg sha "${want[$name]}" '. + [$i + {sha256: $sha}]' <<< "$infos")
  done

  # Prerelease versions: skip the release quietly. Other non major.minor.patch versions: reject.
  if jq -e 'any(.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+[~-]"))' <<< "$infos" > /dev/null; then
    rm -rf "$out/files"
    finish skipped "prerelease version"
  fi
  mapfile -t reasons < <(jq -r '.[] | select(.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not)
    | "\(.filename): version \(.version) isn'"'"'t major.minor.patch"' <<< "$infos")

  # Name, duplicate, and already-admitted rules.
  # State goes to jq on stdin: it outgrows the command-line argument limit.
  local checked
  checked=$(state_json | jql -c --arg repo "$repo" --argjson cfg "$cfg" --argjson infos "$infos" '
    include "lib";
    def short($r): $r | split("/") | last | ascii_downcase;
    def claims($n; $s): $n == $s or ($n | startswith($s + "-"));
    . as $state
    | $infos
    | ($repo | short(.)) as $me
    | ($cfg | map(select(.name == $repo))[0].allow // []) as $allow
    | [$cfg[] | select(.name != $repo)] as $others
    # Historical owners: the repo that first published each name, from state.
    | ([$state | to_entries[] | .key as $k | (.value.packages // [])[] | {name, repo: ($k | repo_of)}]
       | group_by(.name) | map({key: .[0].name, value: (map(.repo) | unique)}) | from_entries) as $owners
    | ($state | [to_entries[] | (.value.packages // [])[]]) as $known
    | group_by([.format, .name, .version, .arch]) as $groups
    | map(. as $p
        | ($owners[$p.name] // []) as $o
        | [ (if ($o | length) > 0 then
               (if ($o | index($repo)) == null then "\($p.filename): \($p.name) is already published by \($o | join(", "))" else empty end)
             elif ($allow | index($p.name)) == null and (claims($p.name; $me) | not) then
               "\($p.filename): \($p.name) is not \($me) or \($me)-* and not in allow"
             elif any($others[]; ((.allow // []) | index($p.name)) != null) then
               "\($p.filename): \($p.name) is in another repo'"'"'s allow"
             elif any($others[]; (short(.name) | length) > ($me | length) and claims($p.name; short(.name))) then
               "\($p.filename): \($p.name) belongs to a repo with a longer matching name"
             else empty end),
            (if any($groups[]; length > 1 and .[0].format == $p.format and .[0].name == $p.name
                 and .[0].version == $p.version and .[0].arch == $p.arch)
             then "\($p.filename): duplicate \($p.format) package \($p.name) \($p.version) \($p.arch) in the release"
             else empty end),
            # A version is admitted once; a fix ships as a new patch version.
            (if any($known[]; .format == $p.format and .name == $p.name and .version == $p.version
                 and .arch == $p.arch)
             then "\($p.filename): \($p.name) \($p.version) \($p.arch) was already admitted; ship a new patch version"
             else empty end)
          ] as $why
        | $p + {reasons: ($why | unique)})
  ')
  mapfile -t -O "${#reasons[@]}" reasons < <(jq -r '.[].reasons[]' <<< "$checked")
  [[ ${#reasons[@]} -eq 0 ]] || finish rejected "${reasons[@]}"

  set_result '.packages = [$c[] | del(.reasons) + {path: "files/\(.filename)", status: "published"}]' \
    --argjson c "$checked"
  finish published
}

fetch_sidecars
verify_chain
check_packages
