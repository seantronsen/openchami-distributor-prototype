# SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# shellcheck shell=bash
# The distributor's state.json on main: what it recorded about each release and its packages.

[[ -n "${_IT_STATE_SH:-}" ]] && return 0
_IT_STATE_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"

################################################################################
# The state.
# Outputs:
#   The JSON on stdout.
################################################################################
state__json() {
  gh api -H 'Accept: application/vnd.github.raw' \
    "repos/$(settings__get .repos.distributor.remote)/contents/state/state.json?ref=main"
}

################################################################################
# Whether a jq filter holds for the state.
# Arguments:
#   jq options (e.g. --arg k value), then the filter last.
# Returns:
#   0 when the filter's result is true, 1 otherwise.
################################################################################
state__has() {
  state__json | jq -e "$@" > /dev/null
}

################################################################################
# Whether the state matches schemas/state.schema.json, checked as the distributor's workflows
# check it.
# Returns:
#   0 when it does, 1 when it doesn't (the errors on stdout) or can't be read.
################################################################################
state__is_valid() {
  local file status
  file="$(mktemp --suffix .json)"
  if ! state__json > "${file}"; then
    log__error "can't read state.json"
    rm -f "${file}"
    return 1
  fi
  /src/distributor/scripts/validate.sh /src/distributor/schemas/state.schema.json "${file}"
  status="$?"
  rm -f "${file}"
  ((status == 0)) || log__error "state.json on main doesn't match schemas/state.schema.json"
  return "${status}"
}

################################################################################
# A release's status.
# Arguments:
#   Repo path (owner/name), tag.
# Outputs:
#   published, skipped, rejected, or absent, on stdout.
################################################################################
state__release_status() {
  state__json | jq -r --arg k "$1@$2" '.[$k].status // "absent"'
}

################################################################################
# Whether none of a repo's packages is published any more.
# Arguments:
#   Repo path (owner/name)
# Returns:
#   0 when none is, 1 otherwise.
################################################################################
state__has_none_published() {
  state__json | jq -e --arg r "$1@" '
    all(to_entries[] | select(.key | startswith($r)) | .value.packages[]?; .status != "published")
  ' > /dev/null
}
