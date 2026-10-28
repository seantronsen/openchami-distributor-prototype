# The whole pipeline with a real build: a testbed tag goes through GoReleaser and signing, and
# the distributor admits and publishes it. The published repositories are exported to
# artifacts/real-build (rpm/, deb/, keys/archive.asc) for the distro tests. The only test that
# waits for a real release build.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/testbed.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

@test "a real release is admitted and its repositories published" {
  local repo run dir
  repo=$(suite__testbed_repo)
  testbed__release v1.0.0
  run=$(poll__run)
  wait__check "v1.0.0: 6 packages published" state__has --arg k "$repo@v1.0.0" \
    '.[$k].packages | length == 6 and all(.status == "published")'
  dir="$(suite__artifacts_dir)/real-build"
  rm -rf "$dir"
  poll__download_published "$run" "$dir"
  test -s "$dir/keys/archive.asc"
  test -d "$dir/rpm/repodata"
  test -d "$dir/deb/dists"
  log__info "exported to $dir"
}
