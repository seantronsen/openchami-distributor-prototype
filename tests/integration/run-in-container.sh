#!/usr/bin/env bash
# Runs inside the tools container that ci/run.sh or distro/run.sh starts; never run it by hand.
# Installs the tools, sets up GitHub access, and runs bats on one suite's tests.
#
#   run-in-container.sh <suite> [test name... | bats option...]
#
# stdin: the GitHub token (one line), so it's never in a file, the engine's record of the
# container's environment, or a command line. The settings are in /run/distributor-it.
set -uo pipefail

# shellcheck source=lib/log.sh
source /suite/lib/log.sh
# shellcheck source=lib/settings.sh
source /suite/lib/settings.sh
# shellcheck source=lib/container.sh
source /suite/lib/container.sh

main() {
  local suite=${1:-} cases files=() options=() status bats_pid failed=false
  cases=/suite/$suite/cases
  if [[ -z $suite || ! -d $cases ]]; then
    log__error "no suite '$suite'"
    failed=true
  fi
  shift
  IFS= read -r GH_TOKEN || true
  if [[ -z $GH_TOKEN ]]; then
    log__error "no GitHub token on stdin"
    failed=true
  fi
  $failed && exit 1
  export GH_TOKEN
  container__install_tools || exit 1
  container__setup_github_access || exit 1
  # The engine command for lib/engine.sh, when the run has one (distro: podman-remote).
  if settings__has .run.engine; then
    IT_ENGINE=$(settings__get .run.engine) || exit 1
    export IT_ENGINE
  fi
  while (($#)); do
    case $1 in
      -f | --filter | --filter-tags | --filter-status)
        options+=("$1" "${2:-}")
        shift 2 || log__fatal "$1 needs a value"
        ;;
      -*)
        options+=("$1")
        shift
        ;;
      *)
        files+=("$cases/${1%.bats}.bats")
        shift
        ;;
    esac
  done
  ((${#files[@]})) || files=("$cases")
  if [[ -f $cases/setup_suite.bash ]]; then
    options+=(--setup-suite-file "$cases/setup_suite.bash")
  fi
  # Live log lines from tests: bats captures a test's stderr, so open a descriptor to the real
  # one and name it for log.sh.
  exec 9>&2
  export IT_LOG_FD=9
  # The engine's init forwards Ctrl-C to this shell only. Pass it to the whole process group, as
  # a terminal would, so the running test stops and bats runs the teardowns. bats needs SIGINT's
  # default handling back: a background job of a script starts with it ignored.
  env --default-signal=INT bats --formatter tap --timing "${options[@]}" "${files[@]}" &
  bats_pid=$!
  trap 'trap "" INT TERM; kill -INT 0' INT TERM
  wait "$bats_pid"
  status=$?
  # A signal ends the first wait early; the second collects bats' exit status.
  if kill -0 "$bats_pid" 2> /dev/null; then
    wait "$bats_pid"
    status=$?
  fi
  exit "$status"
}

main "$@"
