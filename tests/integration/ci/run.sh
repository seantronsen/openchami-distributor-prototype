#!/usr/bin/env bash
# Runs the distributor's CI integration tests (ci/cases/*.bats) against the throwaway repos.
#
#   ci/run.sh                        every test
#   ci/run.sh retention noop         these tests (file names, .bats optional)
#   ci/run.sh --filter 'deny'        bats options pass through
#
# Everything runs in one transient tools container with no access to the container engine. The
# GitHub token reaches it on stdin only; git pushes over SSH through your agent. Logs go to
# stderr; the results (TAP) go to stdout and to <output_dir>/<run id>/report.tap. Files tests
# export (real-build's published repositories) go to <output_dir>/<run id>/artifacts.
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
  launch__run ci "$@"
}

main "$@"
