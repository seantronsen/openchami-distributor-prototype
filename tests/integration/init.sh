#!/usr/bin/env bash
# Creates the throwaway repos under your GitHub account and records them in the state file
# (~/.local/state/distributor-it/repos.yaml; IT_STATE overrides), which the run scripts and
# destroy.sh read:
#
#   it-<random>-distributor     the distributor
#   it-<random>-testbed         the testbed
#   it-<random>-testbed-tools   the second service repo (its name starts with the testbed's)
#
# They're public and empty; the runs fill them. Delete them with destroy.sh. Refused when your
# config sets repos (the tests use those) or the state file already exists.
set -uo pipefail

# shellcheck source=lib/log.sh
source "$(dirname "$0")/lib/log.sh"
# shellcheck source=lib/config.sh
source "$(dirname "$0")/lib/config.sh"
# shellcheck source=lib/random.sh
source "$(dirname "$0")/lib/random.sh"

main() {
  local file owner base try name taken failed=false
  file=$(config__state_file)
  if config__has .repos; then
    log__error "$(config__file) sets repos, so the tests use those; remove them to create new ones"
    failed=true
  fi
  if [[ -e $file ]]; then
    log__error "already initialized: $file lists repos. destroy.sh deletes them, whether they" \
      "still exist or not; to keep them and create new ones, move $file aside first"
    failed=true
  fi
  if ! owner=$(gh api user -q .login); then
    log__error "gh isn't logged in (gh auth login)"
    failed=true
  fi
  $failed && exit 1

  # A taken name is practically impossible; pick a new one a few times anyway.
  for try in {1..3}; do
    base=it-$(random__hex 8)
    taken=false
    for name in "$base-distributor" "$base-testbed" "$base-testbed-tools"; do
      if gh api "repos/$owner/$name" > /dev/null 2>&1; then taken=true; fi
    done
    $taken || break
    log__info "$base is taken (try $try)"
  done
  $taken && log__fatal "couldn't find a free name"

  # Recorded first, so a failure part way still leaves destroy.sh the list.
  mkdir -p "$(dirname "$file")" || log__fatal "can't create $(dirname "$file")"
  cat > "$file" << EOF
# Written by init.sh; read by the run scripts and destroy.sh.
distributor: $owner/$base-distributor
testbed: $owner/$base-testbed
service2: $owner/$base-testbed-tools
EOF
  for name in "$base-distributor" "$base-testbed" "$base-testbed-tools"; do
    gh repo create "$owner/$name" --public \
      --description "distributor integration test repo (throwaway)" > /dev/null ||
      log__fatal "can't create $owner/$name"
    log__info "created $owner/$name"
  done
  log__info "recorded in $file"
}

main
