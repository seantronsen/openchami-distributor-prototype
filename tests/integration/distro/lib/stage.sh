# shellcheck shell=bash
# Stage 1 of a distro test file: CI tests (ci/cases) that produce what the distro tests use,
# run first on the throwaway repos, with their own suite setup and teardown.

[[ -n ${_IT_STAGE_SH:-} ]] && return 0
_IT_STAGE_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../ci/lib/suite.sh"

################################################################################
# Runs CI tests as a stage. Their results and log go to the log.
# Arguments:
#   CI test names (ci/cases/<name>.bats).
# Returns:
#   0, or 1 when a test failed.
################################################################################
stage__ci() {
  local cases name files=()
  cases="$(dirname "${BASH_SOURCE[0]}")/../../ci/cases"
  for name in "$@"; do files+=("$cases/$name.bats"); done
  log__info "stage 1: CI tests $*"
  if ! bats --formatter tap --timing --setup-suite-file "$cases/setup_suite.bash" "${files[@]}" \
    >&"${IT_LOG_FD:-2}" 2>&1; then
    log__error "stage 1 failed: CI tests $*"
    return 1
  fi
}

################################################################################
# Where a CI test exported its files.
# Arguments:
#   CI test name.
# Outputs:
#   The directory on stdout (the same path on the host).
################################################################################
stage__artifacts() {
  echo "$(suite__artifacts_dir)/$1"
}
