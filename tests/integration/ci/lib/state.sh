# shellcheck shell=bash
# The distributor's state.json on main: what it recorded about each release and its packages.

[[ -n ${_IT_STATE_SH:-} ]] && return 0
_IT_STATE_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"

################################################################################
# The state.
# Outputs:
#   The JSON on stdout.
################################################################################
state__get() {
  gh api -H 'Accept: application/vnd.github.raw' \
    "repos/$(suite__distributor_repo)/contents/state/state.json?ref=main"
}

################################################################################
# Whether a jq filter holds for the state.
# Arguments:
#   jq options (e.g. --arg k value), then the filter last.
# Returns:
#   0 when the filter's result is true, 1 otherwise.
################################################################################
state__has() {
  state__get | jq -e "$@" > /dev/null
}

################################################################################
# A release's status.
# Arguments:
#   owner/name, tag.
# Outputs:
#   published, skipped, rejected, or absent, on stdout.
################################################################################
state__release_status() {
  state__get | jq -r --arg k "$1@$2" '.[$k].status // "absent"'
}

################################################################################
# Whether none of a repo's packages is published any more.
# Arguments:
#   owner/name
# Returns:
#   0 when none is, 1 otherwise.
################################################################################
state__none_published() {
  state__get | jq -e --arg r "$1@" '
    all(to_entries[] | select(.key | startswith($r)) | .value.packages[]?; .status != "published")
  ' > /dev/null
}
