# One poll admits at most MAX_RELEASES releases (lowered to 3 here); the rest wait for the next.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../lib/git.sh"
  source "$BATS_TEST_DIRNAME/../lib/github.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

@test "a poll processes at most MAX_RELEASES releases" {
  local distributor repo dir tag
  distributor=$(suite__distributor_repo)
  repo=$(suite__service2_repo)
  # The cap is a constant in discover.sh; the next test's reset restores the seed commit.
  dir=$(mktemp -d)
  git__clone "$distributor" "$dir/repo"
  sed -i 's/^MAX_RELEASES=256$/MAX_RELEASES=3/' "$dir/repo/scripts/discover.sh"
  grep -q '^MAX_RELEASES=3$' "$dir/repo/scripts/discover.sh"
  git__commit "$dir/repo" "it: MAX_RELEASES=3"
  git__push_main "$dir/repo" "$distributor"
  # Empty releases, a couple of seconds apart so discover orders them reliably.
  for tag in v1.0.1 v1.0.2 v1.0.3 v1.0.4; do
    github__release_create "$repo" "$tag"
    sleep 2
  done
  poll__run > /dev/null
  for tag in v1.0.1 v1.0.2 v1.0.3; do
    wait__check "first poll: $tag processed" \
      test "$(state__release_status "$repo" "$tag")" = rejected
  done
  wait__check "first poll: v1.0.4 left for later" \
    test "$(state__release_status "$repo" v1.0.4)" = absent
  poll__run > /dev/null
  wait__check "second poll: v1.0.4 processed" \
    test "$(state__release_status "$repo" v1.0.4)" = rejected
}
