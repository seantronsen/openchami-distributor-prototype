# The CI real build's published repositories, installed by each distro's own package manager:
# from the files themselves, and over HTTP from a temporary S3 gateway the way users will install
# from S3. Stage 1 runs ci/cases/real-build.bats to produce them.

setup_file() {
  source "$BATS_TEST_DIRNAME/../lib/stage.sh"
  source "$BATS_TEST_DIRNAME/../lib/gateway.sh"
  stage__ci real-build
  gateway__start
  gateway__load "$(stage__artifacts real-build)"
}

teardown_file() {
  source "$BATS_TEST_DIRNAME/../lib/gateway.sh"
  gateway__stop
}

setup() {
  source "$BATS_TEST_DIRNAME/../lib/stage.sh"
  source "$BATS_TEST_DIRNAME/../lib/gateway.sh"
  source "$BATS_TEST_DIRNAME/../lib/images.sh"
  source "$BATS_TEST_DIRNAME/../lib/target.sh"
}

@test "fedora: dnf installs from the files" {
  target__dnf "$(images__fedora)" "$(stage__artifacts real-build)" file:///repo testbed
}

@test "debian: apt installs from the files" {
  target__apt "$(images__debian)" "$(stage__artifacts real-build)" file:///repo testbed
}

@test "fedora: dnf installs over HTTP from the S3 gateway" {
  target__dnf "$(images__fedora)" "$(stage__artifacts real-build)" "$(gateway__url)" testbed \
    --network "$(gateway__network)"
}

@test "debian: apt installs over HTTP from the S3 gateway" {
  target__apt "$(images__debian)" "$(stage__artifacts real-build)" "$(gateway__url)" testbed \
    --network "$(gateway__network)"
}
