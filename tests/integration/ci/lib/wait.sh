# shellcheck shell=bash
# Waiting on GitHub: retry a check until it passes, without fixed sleeps.

[[ -n ${_IT_WAIT_SH:-} ]] && return 0
_IT_WAIT_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"

################################################################################
# Runs a command every poll interval until it succeeds or the timeout passes. The command
# returns 0 when done, 1 for "not yet", and anything else to give up early (e.g. a release
# build failed).
# Arguments:
#   Description, then the command and its arguments.
# Outputs:
#   Progress on the log.
# Returns:
#   0 when done, 1 on timeout or when the command gave up.
################################################################################
wait__until() {
  local desc=$1 deadline rc
  shift
  deadline=$((SECONDS + $(suite__timeout)))
  log__info "waiting: $desc"
  while true; do
    rc=0
    "$@" || rc=$?
    case $rc in
      0)
        log__info "done: $desc"
        return 0
        ;;
      1) ;;
      *)
        log__error "gave up: $desc"
        return 1
        ;;
    esac
    if ((SECONDS >= deadline)); then
      log__error "timed out after $(suite__timeout)s: $desc"
      return 1
    fi
    sleep "$(suite__poll_interval)"
  done
}

################################################################################
# Checks a condition a few times, 10 seconds apart, since GitHub's state and status APIs lag.
# For assertions inside tests.
# Arguments:
#   Description, then the command and its arguments.
# Outputs:
#   "ok: <description>" or the failure on the log.
# Returns:
#   0 when the command succeeded, 1 otherwise.
################################################################################
wait__check() {
  local desc=$1 try
  shift
  for try in {1..3}; do
    if "$@"; then
      log__info "ok: $desc"
      return 0
    fi
    if ((try < 3)); then sleep 10; fi
  done
  log__error "check failed: $desc"
  return 1
}
