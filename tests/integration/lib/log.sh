# shellcheck shell=bash
# Logging for every script in the suites, on the host and in containers: timestamped lines on
# stderr, tagged with the running test's name inside bats.

[[ -n ${_IT_LOG_SH:-} ]] && return 0
_IT_LOG_SH=1

################################################################################
# Writes one log line. Inside bats, stderr is captured per test, so run-in-container.sh opens a
# descriptor to the real stderr before starting bats and names it in IT_LOG_FD.
# Globals:
#   IT_LOG_FD (optional), BATS_TEST_DESCRIPTION (set by bats inside a test)
# Arguments:
#   Message words.
# Outputs:
#   "[HH:MM:SS] <test>: <message>" on IT_LOG_FD, or stderr.
################################################################################
log__info() {
  local tag=${BATS_TEST_DESCRIPTION:+$BATS_TEST_DESCRIPTION: }
  TZ=UTC printf '[%(%H:%M:%S)T] %s%s\n' -1 "$tag" "$*" >&"${IT_LOG_FD:-2}"
}

################################################################################
# Logs an error naming the function that reported it. It only logs: the caller returns.
# Arguments:
#   Message words.
################################################################################
log__error() {
  log__info "error: ${FUNCNAME[1]:-main}: $*"
}

################################################################################
# Logs an error and exits. For scripts only; library functions return instead.
# Arguments:
#   Message words.
################################################################################
log__fatal() {
  log__info "fatal: $*"
  exit 1
}
