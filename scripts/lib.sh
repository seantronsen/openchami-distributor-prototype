# shellcheck shell=bash
# Shared helpers for the distributor scripts. Source it; don't run it.
#
# Environment (all optional unless a script says otherwise):
#   CONFIG                 config file (default config/repos.yaml)
#   STATE                  state file (default state/state.json)
#   GITHUB_TOKEN           token for the GitHub API (releases, assets, issues)
#   PUBLISH_DIR            local publish target (required)
#   PUBLISH_S3_URI, PUBLISH_DOMAIN   remote publish targets (not implemented in v1)
#   ARCHIVE_GPG_KEY        archive secret key, armored or base64 (default: throwaway key)
#   ARCHIVE_GPG_PASSPHRASE its passphrase, if any
#   MASTER_PUBLIC_ASC, MASTER_FPR   root public key and fingerprint (admit)

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${CONFIG:-$ROOT/config/repos.yaml}
STATE=${STATE:-$ROOT/state/state.json}
GITHUB_API=${GITHUB_API_URL:-https://api.github.com}
# shellcheck disable=SC2034 # used by the scripts that source this
{
  SUITE=stable
  DEB_ARCHES=(amd64 arm64)
  # github-actions' trust-chain check, pinned by commit; Renovate updates the tag and commit.
  # renovate: datasource=github-tags depName=OpenCHAMI/github-actions currentValue=v4.0.0
  VERIFY_CHAIN_URL=https://raw.githubusercontent.com/OpenCHAMI/github-actions/4dc5bc0542a70beffd00cb218a46cb14650fc638/scripts/gpg-verify-trust-chain.sh
}

log() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

run_url() { echo "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"; }

# jq with scripts/lib.jq available through `include "lib";`.
jql() { jq -L "$ROOT/scripts" "$@"; }

# The repos list from the config, as JSON.
config_json() { yq -o=json -I=0 '.repos // []' "$CONFIG"; }

state_json() {
  if [[ -s $STATE ]]; then cat "$STATE"; else echo '{}'; fi
}

# --- GitHub API -------------------------------------------------------------------------------

gh_api() { # <path> [curl args...]; GH_ACCEPT overrides the Accept header
  local path=$1; shift
  local auth=()
  [[ -n ${GITHUB_TOKEN:-} ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL --retry 3 -H "Accept: ${GH_ACCEPT:-application/vnd.github+json}" \
    -H 'X-GitHub-Api-Version: 2022-11-28' "${auth[@]}" "$@" "$GITHUB_API/$path"
}

uri() { jq -rn --arg s "$1" '$s | @uri'; }

# Releases of a repo as a JSON array of {tag_name, draft, prerelease, published_at}.
# Each page is trimmed on stdin: a full page outgrows the command-line argument limit.
releases_list() { # <owner/repo>
  local repo=$1 page=1 all='[]' batch
  while :; do
    batch=$(gh_api "repos/$repo/releases?per_page=100&page=$page" \
      | jq -c 'map({tag_name, draft, prerelease, published_at})')
    all=$(jq -c -s 'add' <<< "$all $batch")
    [[ $(jq length <<< "$batch") -lt 100 ]] && break
    page=$((page + 1))
  done
  echo "$all"
}

# A release's assets as a JSON array of {name, id}.
release_assets() { # <owner/repo> <tag>
  gh_api "repos/$1/releases/tags/$(uri "$2")" | jq -c '[.assets[] | {name, id}]'
}

asset_fetch() { # <owner/repo> <asset-id> <dest>
  GH_ACCEPT=application/octet-stream gh_api "repos/$1/releases/assets/$2" -o "$3"
}

# Open an issue with this title and label, unless an open one already exists.
issue_ensure() { # <title> <label> <body>
  local title=$1 label=$2 body=$3 number
  number=$(gh_api "repos/$GITHUB_REPOSITORY/issues?state=open&labels=$(uri "$label")&per_page=100" \
    | jq -r --arg t "$title" '[.[] | select(.title == $t)][0].number // empty')
  if [[ -n $number ]]; then
    log "issue #$number already open: $title"
    return
  fi
  issue_create "$title" "$label" "$body"
}

issue_create() { # <title> <label> <body>
  gh_api "repos/$GITHUB_REPOSITORY/issues" -X POST \
    --data "$(jq -n --arg t "$1" --arg l "$2" --arg b "$3" '{title: $t, body: $b, labels: [$l]}')" > /dev/null
}

# --- Publish target ---------------------------------------------------------------------------

target_init() {
  if [[ -n ${PUBLISH_S3_URI:-} || -n ${PUBLISH_DOMAIN:-} ]]; then
    die "S3 and domain publish targets aren't implemented yet; unset PUBLISH_S3_URI/PUBLISH_DOMAIN"
  fi
  mkdir -p "${PUBLISH_DIR:?PUBLISH_DIR is required}"
}

target_get() { # <path> <dest>; 1 when absent
  [[ -f $PUBLISH_DIR/$1 ]] || return 1
  mkdir -p "$(dirname "$2")"
  cp "$PUBLISH_DIR/$1" "$2"
}

target_put() { # <src> <path>; atomic per file
  local dest=$PUBLISH_DIR/$2
  mkdir -p "$(dirname "$dest")"
  cp "$1" "$dest.tmp.$$"
  mv -f "$dest.tmp.$$" "$dest"
}

target_rm() { rm -f "$PUBLISH_DIR/$1"; }

target_ls() { # <dir>: file names directly in it
  [[ -d $PUBLISH_DIR/$1 ]] || return 0
  find "$PUBLISH_DIR/$1" -maxdepth 1 -type f ! -name '*.tmp.*' -printf '%f\n'
}

# --- Archive key ------------------------------------------------------------------------------

# Sets up a private GNUPGHOME holding the archive secret key. Sets ARCHIVE_FPR and ARCHIVE_PUB (the
# exported public key). Without ARCHIVE_GPG_KEY it generates a throwaway key.
archive_key_init() {
  GNUPGHOME=$(mktemp -d)
  export GNUPGHOME
  chmod 700 "$GNUPGHOME"
  printf 'pinentry-mode loopback\ntrust-model always\n' > "$GNUPGHOME/gpg.conf"
  if [[ -n ${ARCHIVE_GPG_PASSPHRASE:-} ]]; then
    printf '%s' "$ARCHIVE_GPG_PASSPHRASE" > "$GNUPGHOME/passphrase"
    echo "passphrase-file $GNUPGHOME/passphrase" >> "$GNUPGHOME/gpg.conf"
  fi

  if [[ -n ${ARCHIVE_GPG_KEY:-} ]]; then
    if grep -q 'BEGIN PGP' <<< "$ARCHIVE_GPG_KEY"; then
      printf '%s\n' "$ARCHIVE_GPG_KEY"
    else
      base64 -d <<< "$ARCHIVE_GPG_KEY"
    fi | gpg --batch --quiet --import 2> /dev/null || die "ARCHIVE_GPG_KEY doesn't import"
  else
    gpg --batch --quiet --passphrase '' --quick-generate-key \
      'OpenCHAMI throwaway archive key' rsa3072 sign 1y 2> /dev/null
    log "ARCHIVE_GPG_KEY not set: signing with a throwaway archive key"
  fi

  local fprs
  fprs=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1=="sec" {s=1} s && $1=="fpr" {print $10; s=0}')
  [[ $(wc -l <<< "$fprs") -eq 1 && -n $fprs ]] || die "the archive key must be exactly one secret key"
  ARCHIVE_FPR=$fprs
  ARCHIVE_PUB=$GNUPGHOME/archive-public.asc
  gpg --batch --armor --export "$ARCHIVE_FPR" > "$ARCHIVE_PUB"
  export ARCHIVE_FPR ARCHIVE_PUB
}

rpm_sign() { # <rpm>...
  # Ubuntu's rpm macros point __gpg at a path that may not exist; use the gpg on PATH.
  rpmsign --addsign --define "__gpg $(command -v gpg)" --define "_gpg_name $ARCHIVE_FPR" \
    --define "_gpg_path $GNUPGHOME" "$@" > /dev/null
}

# --- Packages ---------------------------------------------------------------------------------

# Metadata of a .rpm or .deb as JSON {format, name, version, arch, filename}; version is the
# upstream version (rpm VERSION; deb Version without epoch or revision).
package_info() { # <file>
  local f=$1 name version arch format
  case $f in
    *.rpm)
      format=rpm
      IFS=$'\t' read -r name version arch < <(rpm -qp --nosignature --nodigest \
        --qf '%{NAME}\t%{VERSION}\t%{ARCH}\n' "$f" 2> /dev/null)
      ;;
    *.deb)
      format=deb
      name=$(dpkg-deb -f "$f" Package)
      version=$(dpkg-deb -f "$f" Version)
      arch=$(dpkg-deb -f "$f" Architecture)
      version=${version#*:}
      [[ $version == *-* ]] && version=${version%-*}
      ;;
    *) die "not a package: $f" ;;
  esac
  jq -nc --arg format "$format" --arg name "$name" --arg version "$version" --arg arch "$arch" \
    --arg filename "$(basename "$f")" '{format: $format, name: $name, version: $version, arch: $arch, filename: $filename}'
}

supported_arch() { # <format> <arch>
  case $1:$2 in
    rpm:x86_64 | rpm:aarch64 | rpm:noarch | deb:amd64 | deb:arm64 | deb:all) return 0 ;;
    *) return 1 ;;
  esac
}

# Path of a package in the publish target.
package_path() { # <format> <name> <filename>
  case $1 in
    rpm) echo "rpm/packages/$3" ;;
    deb) echo "deb/pool/main/${2:0:1}/$2/$3" ;;
  esac
}
