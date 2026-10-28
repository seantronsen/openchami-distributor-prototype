# shellcheck shell=bash
# The distributor's poll runs: finding them, dispatching them, and downloading the repositories
# a run published.

[[ -n ${_IT_POLL_SH:-} ]] && return 0
_IT_POLL_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/wait.sh"
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"

################################################################################
# The poll run a push of a commit triggered.
# Arguments:
#   Commit SHA.
# Outputs:
#   The run id on stdout, or nothing yet.
################################################################################
poll__push_run() {
  gh api "repos/$(suite__distributor_repo)/actions/workflows/poll.yml/runs?event=push&head_sha=$1" \
    -q '.workflow_runs[0].id // empty'
}

################################################################################
# Whether a push of a commit has triggered a poll yet.
# Arguments:
#   Commit SHA.
# Returns:
#   0 when it has, 1 otherwise.
################################################################################
poll__has_push_run() {
  [[ -n $(poll__push_run "$1") ]]
}

################################################################################
# The newest poll run's id, of any trigger.
# Outputs:
#   The id on stdout (0 when there is none).
################################################################################
poll__latest() {
  gh api "repos/$(suite__distributor_repo)/actions/workflows/poll.yml/runs?per_page=1" \
    -q '.workflow_runs[0].id // 0'
}

################################################################################
# Dispatched poll runs newer than a given run.
# Arguments:
#   Run id.
# Outputs:
#   Their ids on stdout, oldest first, one per line.
################################################################################
poll__dispatches_after() {
  gh api "repos/$(suite__distributor_repo)/actions/workflows/poll.yml/runs" \
    -X GET -f event=workflow_dispatch -f per_page=20 \
    -q "[.workflow_runs[] | select(.id > $1) | .id] | sort | .[]"
}

################################################################################
# Whether at least <count> polls were dispatched after a given run.
# Arguments:
#   Run id, count.
# Returns:
#   0 when they were, 1 otherwise.
################################################################################
poll__has_dispatches_after() {
  (($(poll__dispatches_after "$1" | wc -l) >= $2))
}

################################################################################
# Dispatches polls without waiting for them to finish.
# Arguments:
#   How many.
# Outputs:
#   The new runs' ids on stdout, oldest first, one per line.
# Returns:
#   0, or 1 when they didn't start.
################################################################################
poll__dispatch() {
  local repo count=$1 before i id
  repo=$(suite__distributor_repo)
  before=$(poll__latest)
  for ((i = 0; i < count; i++)); do
    if ! gh workflow run poll.yml -R "$repo" --ref main > /dev/null; then
      log__error "can't dispatch poll"
      return 1
    fi
  done
  wait__until "$count dispatched poll(s) start" poll__has_dispatches_after "$before" "$count" ||
    return 1
  for id in $(poll__dispatches_after "$before" | head -n "$count"); do
    log__info "poll run: https://github.com/$repo/actions/runs/$id"
    echo "$id"
  done
}

################################################################################
# Dispatches one poll and waits for it to finish.
# Outputs:
#   The run id on stdout.
# Returns:
#   0, or 1 when it didn't start or finish.
################################################################################
poll__run() {
  local id
  id=$(poll__dispatch 1) || return 1
  github__run_wait "$(suite__distributor_repo)" "$id" > /dev/null || return 1
  echo "$id"
}

################################################################################
# Downloads the repositories a poll run published (its target-publish-rpm and -deb artifacts)
# into one directory, laid out as the distributor publishes: rpm/, deb/, keys/archive.asc.
# Arguments:
#   Run id, destination directory.
# Returns:
#   0, or 1 when a download failed.
################################################################################
poll__download_published() {
  local repo tmp format
  repo=$(suite__distributor_repo)
  tmp=$(mktemp -d)
  for format in rpm deb; do
    if ! gh run download "$1" -R "$repo" -n "target-publish-$format" -D "$tmp/$format"; then
      log__error "can't download run $1's published $format repository"
      return 1
    fi
  done
  # Both carry keys/archive.asc, the same file.
  if ! mkdir -p "$2" || ! cp -a "$tmp/rpm/." "$tmp/deb/." "$2/"; then
    log__error "can't copy the published repositories to $2"
    return 1
  fi
}
