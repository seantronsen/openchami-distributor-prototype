# shellcheck shell=bash
# Setting up the tools container before its tests run.

[[ -n ${_IT_CONTAINER_SH:-} ]] && return 0
_IT_CONTAINER_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/settings.sh"

################################################################################
# Installs the suites' tools with apt, plus the engine client when the run has one (the
# container has the host engine's socket). jq comes first: reading the settings needs it.
# Returns:
#   0, or 1 when apt failed.
################################################################################
container__install_tools() {
  local packages=(bats ca-certificates gh git gnupg openssh-client rpm)
  if ! { apt-get update -qq && apt-get install -y -qq --no-install-recommends jq; } \
    > /dev/null 2>&1; then
    log__error "apt couldn't install jq"
    return 1
  fi
  if settings__has .run.engine; then packages+=(podman-remote); fi
  if ! apt-get install -y -qq --no-install-recommends "${packages[@]}" > /dev/null 2>&1; then
    log__error "apt couldn't install the tools"
    return 1
  fi
}

################################################################################
# GitHub access for git (gh already has GH_TOKEN): over SSH through the host's agent, with
# github.com's host keys taken from GitHub's API (over TLS) instead of trusted on first use.
# Returns:
#   0, or 1 when the host keys can't be fetched.
################################################################################
container__setup_github_access() {
  install -d -m 700 ~/.ssh
  if ! gh api meta -q '.ssh_keys[] | "github.com " + .' > ~/.ssh/known_hosts; then
    log__error "can't fetch github.com's SSH host keys"
    return 1
  fi
  # No .gitconfig: the checkout copies may belong to another user, and detached HEADs are fine.
  export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=yes -o BatchMode=yes"
  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
  export GIT_CONFIG_KEY_1=advice.detachedHead GIT_CONFIG_VALUE_1=false
}
