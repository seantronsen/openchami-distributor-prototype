# GitHub prereleases are ignored: no state entry, no issue.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../lib/crafted.sh"
  source "$BATS_TEST_DIRNAME/../lib/issues.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

@test "a prerelease is ignored" {
  local repo
  repo=$(suite__service2_repo)
  crafted__release "$repo" v9.0.0-rc1 --prerelease "$(suite__repo_name "$repo") 9.0.0"
  poll__run > /dev/null
  wait__check "no state entry" test "$(state__release_status "$repo" v9.0.0-rc1)" = absent
  wait__check "no issue" \
    test "$(issues__count "Rejected release: $repo@v9.0.0-rc1")" = 0
}
