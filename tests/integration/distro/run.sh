#!/usr/bin/env bash
# Runs the distro tests (distro/cases/*.bats): each distro's own package manager installs from
# the distributor's published repositories.
#
#   distro/run.sh                    every test
#   distro/run.sh ci-artifacts       these tests (file names, .bats optional)
#   distro/run.sh --filter 'fedora'  bats options pass through
#
# WARNING: review distro/ before running it. Unlike the CI tests, the tools container gets your
# rootless podman's API socket, so the code in it can start containers as you, with your
# privileges, and anything those containers can reach. Rootless podman is required (docker's
# socket is root's). See docs/integration-tests.md.
#
# Each test file runs its CI stage first (e.g. ci/cases/real-build.bats, on the throwaway repos),
# then one sibling container per distro. Logs go to stderr; the results (TAP) go to stdout and to
# <output_dir>/<run id>/report.tap.
#
# Settings: config.defaults.yaml, overridden by ~/.config/distributor-it/config.yaml.
set -uo pipefail

# shellcheck source=../lib/launch.sh
source "$(dirname "$0")/../lib/launch.sh"

main() {
  case ${1:-} in
    -h | --help)
      launch__usage "$0"
      return 0
      ;;
  esac
  launch__run distro --engine-socket "$@"
}

main "$@"
