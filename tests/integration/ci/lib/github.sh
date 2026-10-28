# shellcheck shell=bash
# Generic GitHub API helpers through gh: commits, workflow runs, releases, issues, and wiping a
# repo back to an empty state.

[[ -n ${_IT_GITHUB_SH:-} ]] && return 0
_IT_GITHUB_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/wait.sh"

################################################################################
# The SHA of a repo's main branch.
# Arguments:
#   owner/name
# Outputs:
#   The SHA on stdout.
################################################################################
github__head_sha() {
  gh api "repos/$1/commits/main" -q .sha
}

################################################################################
# Whether a repo has any workflow run that isn't completed (queued, in progress, waiting...).
# Arguments:
#   owner/name
# Returns:
#   0 when idle, 1 otherwise.
################################################################################
github__runs_idle() {
  [[ $(gh api "repos/$1/actions/runs?per_page=100" \
    -q '[.workflow_runs[] | select(.status != "completed")] | length') == 0 ]]
}

################################################################################
# Waits until a repo has no active workflow runs.
# Arguments:
#   owner/name
# Returns:
#   0 when idle, 1 on timeout.
################################################################################
github__wait_idle() {
  wait__until "$1: no active runs" github__runs_idle "$1"
}

################################################################################
# Waits for a workflow run to complete.
# Arguments:
#   owner/name, run id.
# Outputs:
#   The run's conclusion (success, failure, cancelled...) on stdout.
# Returns:
#   0, or 1 on timeout.
################################################################################
github__run_wait() {
  wait__until "run $2 completes" github__run_completed "$1" "$2" || return 1
  gh api "repos/$1/actions/runs/$2" -q .conclusion
}

################################################################################
# Whether a workflow run has completed.
# Arguments:
#   owner/name, run id.
# Returns:
#   0 when completed, 1 otherwise.
################################################################################
github__run_completed() {
  [[ $(gh api "repos/$1/actions/runs/$2" -q .status) == completed ]]
}

################################################################################
# Whether a run has a job by this name, every instance of it (one per matrix entry, e.g.
# "prune / prune (rpm)") ending with one conclusion. A reusable workflow's job is named
# "<caller job> / <job>" when it ran, and just "<caller job>" when the caller was skipped.
# Arguments:
#   owner/name, run id, job name (e.g. "admit / admit", or "admit" when skipped), conclusion.
# Returns:
#   0 when there are such jobs and all match, 1 otherwise.
################################################################################
github__jobs_concluded() {
  local conclusions
  conclusions=$(gh api --paginate "repos/$1/actions/runs/$2/jobs?per_page=100" \
    -q ".jobs[] | select(.name == \"$3\" or (.name | startswith(\"$3 (\"))) | .conclusion")
  [[ -n $conclusions ]] && ! grep -qvx "$4" <<< "$conclusions"
}

################################################################################
# Creates a release, and with it its tag on main.
# Arguments:
#   owner/name, tag, then options for gh release create (e.g. --prerelease) and files.
# Returns:
#   0, or 1 when the release wasn't created.
################################################################################
github__release_create() {
  if ! gh release create "$2" -R "$1" --target main --title "$2" --notes distributor-it \
    --latest=false "${@:3}" > /dev/null; then
    log__error "can't create release $1 $2"
    return 1
  fi
}

################################################################################
# Issues on a repo, open and closed.
# Arguments:
#   owner/name
# Outputs:
#   A JSON array of {number, title, state} on stdout.
################################################################################
github__issues() {
  gh issue list -R "$1" --state all -L 1000 --json number,title,state
}

################################################################################
# Counts issues with an exact title, optionally in one state.
# Arguments:
#   owner/name, title, state (OPEN or CLOSED; optional).
# Outputs:
#   The count on stdout.
################################################################################
github__issue_count() {
  github__issues "$1" | jq --arg t "$2" --arg s "${3:-}" \
    '[.[] | select(.title == $t and ($s == "" or .state == $s))] | length'
}

################################################################################
# Deletes everything a test leaves on a repo: releases and tags, issues, and the distributor's
# labels. With "runs", also cancels active workflow runs, waits for them, and deletes every run.
# Arguments:
#   owner/name, then "runs" (optional).
# Returns:
#   0, or 1 when something couldn't be deleted.
################################################################################
github__wipe() {
  local repo=$1 x failed=false
  for x in $(gh api --paginate "repos/$repo/releases?per_page=100" -q '.[].tag_name'); do
    gh release delete "$x" -R "$repo" --cleanup-tag --yes || failed=true
  done
  # An empty repo has no refs to list (HTTP 409).
  if gh api "repos/$repo/commits?per_page=1" > /dev/null 2>&1; then
    for x in $(gh api --paginate "repos/$repo/git/matching-refs/tags" -q '.[].ref'); do
      gh api -X DELETE "repos/$repo/git/$x" || failed=true
    done
  fi
  for x in $(gh issue list -R "$repo" --state all -L 1000 --json number -q '.[].number'); do
    gh issue delete "$x" -R "$repo" --yes || failed=true
  done
  for x in rejected-release denied-repo-key prune-failing; do
    gh label delete "$x" -R "$repo" --yes > /dev/null 2>&1 || true
  done
  if [[ ${2:-} == runs ]]; then
    for x in $(gh api --paginate "repos/$repo/actions/runs?per_page=100" \
      -q '.workflow_runs[] | select(.status != "completed") | .id'); do
      gh api -X POST "repos/$repo/actions/runs/$x/cancel" > /dev/null 2>&1 || true
    done
    github__wait_idle "$repo" || failed=true
    for x in $(gh api --paginate "repos/$repo/actions/runs?per_page=100" \
      -q '.workflow_runs[].id'); do
      gh api -X DELETE "repos/$repo/actions/runs/$x" || failed=true
    done
  fi
  if $failed; then
    log__error "couldn't delete everything on $repo"
    return 1
  fi
}
