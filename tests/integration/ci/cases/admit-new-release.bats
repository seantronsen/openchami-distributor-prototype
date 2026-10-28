# A new release that passes every check is admitted, and its packages are published.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../lib/crafted.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

@test "a new release is admitted and its packages published" {
  local repo name
  repo=$(suite__service2_repo)
  name=$(suite__repo_name "$repo")
  crafted__release "$repo" v1.0.0 "$name 1.0.0"
  poll__run > /dev/null
  wait__check "v1.0.0: published, deb and rpm" state__has --arg k "$repo@v1.0.0" '
    .[$k].status == "published"
    and (.[$k].packages | length == 2 and all(.status == "published"))'
}
