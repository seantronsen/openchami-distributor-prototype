# shellcheck shell=bash
# The suites' configuration on the host: config.defaults.yaml (every setting's default, in the
# source tree) overridden by the user's config file (never written), and the state file (the
# repos init.sh created). YAML is read with yq, converted to JSON for either yq implementation,
# and queried with jq.

[[ -n ${_IT_CONFIG_SH:-} ]] && return 0
_IT_CONFIG_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

################################################################################
# The defaults file.
# Outputs:
#   The path on stdout.
################################################################################
config__defaults_file() {
  echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.defaults.yaml"
}

################################################################################
# The user's config file. It may not exist: then the defaults apply.
# Globals:
#   IT_CONFIG (optional override), XDG_CONFIG_HOME
# Outputs:
#   The path on stdout.
################################################################################
config__file() {
  echo "${IT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/distributor-it/config.yaml}"
}

################################################################################
# The state file: the repos init.sh created, kept outside the source tree.
# Globals:
#   IT_STATE (optional override), XDG_STATE_HOME
# Outputs:
#   The path on stdout.
################################################################################
config__state_file() {
  echo "${IT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/distributor-it/repos.yaml}"
}

################################################################################
# A YAML file as JSON. mikefarah's yq needs to be told; the jq-based one prints JSON anyway.
# Arguments:
#   File.
# Outputs:
#   The JSON on stdout, on one line (null for an empty file).
# Returns:
#   0, or 1 when the file can't be read.
################################################################################
config__json() {
  local json
  if yq --version 2>&1 | grep -q mikefarah; then
    json=$(yq -o=json . "$1")
  else
    json=$(yq . "$1")
  fi || {
    log__error "can't read $1"
    return 1
  }
  jq -c . <<< "${json:-null}"
}

################################################################################
# The configuration: the user's settings over the defaults. A checkout the user sets replaces
# the default one whole (path, or repo and ref, never a mix).
# Outputs:
#   The JSON on stdout.
# Returns:
#   0, or 1 when a file can't be read.
################################################################################
config__merged() {
  local defaults user=null
  defaults=$(config__json "$(config__defaults_file)") || return 1
  if [[ -f $(config__file) ]]; then
    user=$(config__json "$(config__file)") || return 1
  fi
  jq -n --argjson d "$defaults" --argjson u "$user" '($u // {}) as $u
    | ($d * $u) | .checkouts = ($d.checkouts + ($u.checkouts // {}))'
}

################################################################################
# Whether a setting is set (the defaults leave some unset).
# Arguments:
#   jq path (e.g. .engine).
# Returns:
#   0 when set, 1 when not or the configuration can't be read.
################################################################################
config__has() {
  local merged
  merged=$(config__merged) || return 1
  jq -e "$1 != null" <<< "$merged" > /dev/null
}

################################################################################
# One setting.
# Arguments:
#   jq path (e.g. .images.tools).
# Outputs:
#   The value on stdout (objects as JSON).
# Returns:
#   0, or 1 when it isn't set or the configuration can't be read.
################################################################################
config__get() {
  local merged
  merged=$(config__merged) || return 1
  if ! jq -r "$1"' | if . == null then error("unset") else . end' <<< "$merged" 2> /dev/null; then
    log__error "$1 isn't set"
    return 1
  fi
}

################################################################################
# One value from the state file.
# Arguments:
#   jq path (e.g. .testbed).
# Outputs:
#   The value on stdout, empty when missing.
# Returns:
#   0, or 1 when the file can't be read.
################################################################################
config__state() {
  local json
  json=$(config__json "$(config__state_file)") || return 1
  jq -r "$1 // empty" <<< "$json"
}

################################################################################
# A throwaway repo: from the configuration when it sets repos (the source of truth), else from
# the state file init.sh wrote.
# Arguments:
#   Role: distributor, testbed, or service2.
# Outputs:
#   owner/name on stdout.
# Returns:
#   0, or 1 when neither names it.
################################################################################
config__repo() {
  local repo=""
  if config__has .repos; then
    repo=$(config__get ".repos.$1") || return 1
  elif [[ -f $(config__state_file) ]]; then
    repo=$(config__state ".$1") || return 1
  fi
  if [[ -z $repo ]]; then
    log__error "no $1 repo: run init.sh, or set repos in $(config__file)"
    return 1
  fi
  echo "$repo"
}
