# A release signed by a key the repo key never certified fails the trust chain.

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

@test "a release with an uncertified signature is rejected" {
  local repo reason
  repo=$(suite__service2_repo)
  reason="trust chain or checksums.txt signature didn't verify (see the run log)"
  crafted__release "$repo" v1.0.0 --foreign "$(suite__repo_name "$repo") 1.0.0"
  poll__run > /dev/null
  wait__check "rejected" test "$(state__release_status "$repo" v1.0.0)" = rejected
  wait__check "trust chain reason" state__has --arg k "$repo@v1.0.0" \
    --arg r "$reason" '.[$k].reasons == [$r]'
  wait__check "one issue" test "$(issues__count "Rejected release: $repo@v1.0.0")" = 1
}
