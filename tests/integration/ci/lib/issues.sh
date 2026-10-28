# shellcheck shell=bash
# The issues the distributor opens: rejected releases, denied repo keys, a failing prune.

[[ -n ${_IT_ISSUES_SH:-} ]] && return 0
_IT_ISSUES_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"

################################################################################
# Counts the distributor's issues with an exact title, optionally in one state.
# Arguments:
#   Title, state (OPEN or CLOSED; optional).
# Outputs:
#   The count on stdout.
################################################################################
issues__count() {
  github__issue_count "$(suite__distributor_repo)" "$@"
}

################################################################################
# Whether the distributor has an open issue for denying a repo key.
# Arguments:
#   owner/name of the service repo, the key's fingerprint.
# Returns:
#   0 when there is one, 1 otherwise.
################################################################################
issues__has_denial() {
  github__issues "$(suite__distributor_repo)" | jq -e --arg p "Denied repo key: $1 $2 (" \
    'any(.[]; .state == "OPEN" and (.title | startswith($p)))' > /dev/null
}
