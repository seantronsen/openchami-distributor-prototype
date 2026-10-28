# Packages already admitted can't come back under another tag; ship a new version instead.

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

@test "a retagged copy of an admitted release is rejected" {
  local repo
  repo=$(suite__service2_repo)
  crafted__release "$repo" v1.0.0 "$(suite__repo_name "$repo") 1.0.0"
  poll__run > /dev/null
  crafted__copy_release "$repo" v1.0.0 v1.0.0-retag
  poll__run > /dev/null
  wait__check "rejected" test "$(state__release_status "$repo" v1.0.0-retag)" = rejected
  wait__check "every package already admitted" state__has \
    --arg k "$repo@v1.0.0-retag" '.[$k].reasons | length == 2
      and all(endswith("was already admitted; ship a new patch version"))'
  wait__check "one issue" \
    test "$(issues__count "Rejected release: $repo@v1.0.0-retag")" = 1
}
