# A release without its signature sidecars is rejected once, with one issue, and not reprocessed.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../lib/github.sh"
  source "$BATS_TEST_DIRNAME/../lib/issues.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

@test "a release missing its sidecars is rejected once" {
  local repo at
  repo=$(suite__service2_repo)
  github__release_create "$repo" v1.0.0
  poll__run > /dev/null
  wait__check "rejected" test "$(state__release_status "$repo" v1.0.0)" = rejected
  wait__check "a missing reason per sidecar" state__has --arg k "$repo@v1.0.0" \
    '[.[$k].reasons[] | select(startswith("missing "))] | length == 4'
  wait__check "one open issue" \
    test "$(issues__count "Rejected release: $repo@v1.0.0" OPEN)" = 1
  at=$(state__get | jq -r --arg k "$repo@v1.0.0" '.[$k].at')
  poll__run > /dev/null
  wait__check "not processed again" state__has --arg k "$repo@v1.0.0" --arg at "$at" \
    '.[$k].at == $at'
  wait__check "still one issue" \
    test "$(issues__count "Rejected release: $repo@v1.0.0")" = 1
}
