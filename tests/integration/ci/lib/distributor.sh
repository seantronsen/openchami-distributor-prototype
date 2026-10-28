# shellcheck shell=bash
# The throwaway distributor repo's contents: seeding it from the local checkout, resetting it to
# the seed commit, and pushing its config.

[[ -n ${_IT_DISTRIBUTOR_SH:-} ]] && return 0
_IT_DISTRIBUTOR_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/wait.sh"
source "$(dirname "${BASH_SOURCE[0]}")/git.sh"
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"
source "$(dirname "${BASH_SOURCE[0]}")/poll.sh"

################################################################################
# The default config: the testbed allowed its two packages, the second repo nothing extra.
# Outputs:
#   config/repos.yaml content on stdout.
################################################################################
distributor__default_config() {
  cat << EOF
repos:
  - name: $(suite__testbed_repo)
    allow: [testbed, testbed-quadlet]
  - name: $(suite__service2_repo)
EOF
}

################################################################################
# Pushes the local distributor checkout (a copy at /src/distributor) to the throwaway repo, with
# the default config, empty state, no cron schedule (tests dispatch every poll), and the marker.
# The seed commit stays in the shared directory for distributor__reset.
# Returns:
#   0, or 1 when the seed couldn't be pushed or its poll didn't finish.
################################################################################
distributor__seed() {
  local dir poll
  dir="$(suite__share_dir)/seed-distributor"
  poll=$dir/.github/workflows/poll.yml
  rm -rf "$dir"
  if ! git clone --quiet /src/distributor "$dir"; then
    log__error "can't clone /src/distributor"
    return 1
  fi
  distributor__default_config > "$dir/config/repos.yaml"
  echo '{}' > "$dir/state/state.json"
  sed -i '/^  schedule:$/,/^    - cron:/d' "$poll"
  if grep -q 'cron:' "$poll"; then
    log__error "can't drop poll's schedule"
    return 1
  fi
  echo distributor-it > "$dir/$(suite__marker)"
  git__commit "$dir" "it: seed" || return 1
  git__push_main "$dir" "$(suite__distributor_repo)" --force || return 1
  # The config change triggers a poll; tests start idle.
  github__wait_idle "$(suite__distributor_repo)"
}

################################################################################
# Puts the distributor back on the seed commit (default config, empty state, unmodified code)
# when a test moved it, and waits until no poll runs.
# Returns:
#   0, or 1 when the push failed or a poll didn't finish.
################################################################################
distributor__reset() {
  local dir repo
  dir="$(suite__share_dir)/seed-distributor"
  repo=$(suite__distributor_repo)
  github__wait_idle "$repo" || return 1
  if [[ $(github__head_sha "$repo") != "$(git -C "$dir" rev-parse HEAD)" ]]; then
    log__info "reset: $repo back to the seed commit"
    git__push_main "$dir" "$repo" --force || return 1
    # A config difference triggers a poll.
    github__wait_idle "$repo" || return 1
  fi
}

################################################################################
# Replaces the config and waits for the poll the push triggers.
# Inputs:
#   config/repos.yaml content on stdin.
# Outputs:
#   The triggered poll's run id on stdout (nothing when the config didn't change).
# Returns:
#   0, or 1 when the push failed or its poll didn't run.
################################################################################
distributor__push_config() {
  local repo dir sha id
  repo=$(suite__distributor_repo)
  dir=$(mktemp -d)
  git__clone "$repo" "$dir/repo" || return 1
  cat > "$dir/repo/config/repos.yaml"
  if git -C "$dir/repo" diff --quiet; then
    log__info "config unchanged"
    return 0
  fi
  git__commit "$dir/repo" "it: config" || return 1
  git__push_main "$dir/repo" "$repo" || return 1
  sha=$(git -C "$dir/repo" rev-parse HEAD)
  wait__until "poll triggered by config ${sha:0:7}" poll__has_push_run "$sha" || return 1
  id=$(poll__push_run "$sha")
  log__info "poll run: https://github.com/$repo/actions/runs/$id"
  github__run_wait "$repo" "$id" > /dev/null || return 1
  echo "$id"
}
