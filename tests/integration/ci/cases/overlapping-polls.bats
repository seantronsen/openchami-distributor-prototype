# Two polls dispatched together run one after the other: the first admits, the second finds
# nothing new and commits nothing.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../lib/crafted.sh"
  source "$BATS_TEST_DIRNAME/../lib/github.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

################################################################################
# Whether one of the distributor's recent commits was made by a run (its message ends with the
# run's URL).
# Arguments:
#   Run id.
# Returns:
#   0 when it was, 1 otherwise.
################################################################################
committed_by() {
  gh api "repos/$(suite__distributor_repo)/commits?per_page=20" -q '.[].commit.message' |
    grep -q "/runs/$1\$"
}

################################################################################
# The opposite of committed_by.
# Arguments:
#   Run id.
################################################################################
not_committed_by() {
  ! committed_by "$1"
}

@test "overlapping polls admit a release once" {
  local repo distributor first second
  repo=$(suite__service2_repo)
  distributor=$(suite__distributor_repo)
  crafted__release "$repo" v1.0.0 "$(suite__repo_name "$repo") 1.0.0"
  { read -r first && read -r second; } < <(poll__dispatch 2)
  github__run_wait "$distributor" "$first" > /dev/null
  github__run_wait "$distributor" "$second" > /dev/null
  wait__check "first poll admitted v1.0.0" \
    github__jobs_concluded "$distributor" "$first" "admit / admit" success
  wait__check "second poll found nothing new" \
    github__jobs_concluded "$distributor" "$second" admit skipped
  wait__check "v1.0.0: published" test "$(state__release_status "$repo" v1.0.0)" = published
  wait__check "state committed by the first poll" committed_by "$first"
  wait__check "no state commit by the second" not_committed_by "$second"
}
