# shellcheck shell=bash
# git against the throwaway repos, over SSH (the host's agent is mounted into the container).

[[ -n ${_IT_GIT_SH:-} ]] && return 0
_IT_GIT_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"

################################################################################
# The SSH remote of a repo.
# Arguments:
#   owner/name
# Outputs:
#   The URL on stdout.
################################################################################
git__url() { echo "git@github.com:$1.git"; }

################################################################################
# Clones a repo's main branch (latest commit only).
# Arguments:
#   owner/name, destination directory (must not exist).
# Returns:
#   0, or 1 when the clone failed.
################################################################################
git__clone() {
  if ! git clone --quiet --depth 1 "$(git__url "$1")" "$2"; then
    log__error "can't clone $1"
    return 1
  fi
}

################################################################################
# Commits everything in a working tree as the suite's identity (empty commits allowed).
# Arguments:
#   Directory, commit message.
# Returns:
#   0, or 1 when the commit failed.
################################################################################
git__commit() {
  if ! git -C "$1" add -A ||
    ! git -C "$1" -c user.name=distributor-it -c user.email=it@invalid \
      commit --quiet --allow-empty -m "$2"; then
    log__error "can't commit in $1"
    return 1
  fi
}

################################################################################
# Pushes a working tree's HEAD to a repo's main branch.
# Arguments:
#   Directory, owner/name, then extra git push options (e.g. --force).
# Returns:
#   0, or 1 when the push failed.
################################################################################
git__push_main() {
  if ! git -C "$1" push --quiet "${@:3}" "$(git__url "$2")" HEAD:refs/heads/main; then
    log__error "can't push to $2"
    return 1
  fi
}

################################################################################
# Pushes a tag on a working tree's HEAD.
# Arguments:
#   Directory, owner/name, tag.
# Returns:
#   0, or 1 when tagging or the push failed.
################################################################################
git__push_tag() {
  if ! git -C "$1" tag "$3" || ! git -C "$1" push --quiet "$(git__url "$2")" "refs/tags/$3"; then
    log__error "can't push tag $3 to $2"
    return 1
  fi
}
