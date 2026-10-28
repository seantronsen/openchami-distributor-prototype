# shellcheck shell=bash
# The host side of a run, shared by ci/run.sh and distro/run.sh: checks the host and the
# configuration, snapshots the code under test, and runs one suite in a transient tools
# container, which gets the resolved settings as a file and the GitHub token on stdin.

[[ -n ${_IT_LAUNCH_SH:-} ]] && return 0
_IT_LAUNCH_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/engine.sh"
source "$(dirname "${BASH_SOURCE[0]}")/settings.sh"

################################################################################
# Prints a run script's header comment (from line 2 to its `set` line) as its usage.
# Arguments:
#   The script's path.
# Outputs:
#   The usage on stdout.
################################################################################
launch__usage() {
  sed -n '2,/^set /p' "$1" | sed '$d; s/^# \{0,1\}//'
}

################################################################################
# Checks the host's tools, reporting every missing one.
# Returns:
#   0, or 1 when any is missing.
################################################################################
launch__check_tools() {
  local tool failed=false
  for tool in yq jq gh git ssh-add; do
    if ! command -v "$tool" > /dev/null; then
      log__error "needs $tool"
      failed=true
    fi
  done
  ! $failed
}

################################################################################
# Checks the SSH agent git pushes through.
# Returns:
#   0, or 1 when there's no agent or it holds no key.
################################################################################
launch__check_agent() {
  if [[ ! -S ${SSH_AUTH_SOCK:-} ]]; then
    log__error "git pushes over SSH: start an ssh-agent holding a key GitHub accepts"
    return 1
  fi
  if ! ssh-add -l > /dev/null 2>&1; then
    log__error "the SSH agent holds no key: add one GitHub accepts (ssh-add <key file>)"
    return 1
  fi
}

################################################################################
# Whether podman runs rootless.
# Returns:
#   0 when it does, 1 when it doesn't or isn't installed.
################################################################################
launch__rootless_podman() {
  command -v podman > /dev/null &&
    [[ $(podman info --format '{{.Host.Security.Rootless}}' 2> /dev/null) == true ]]
}

################################################################################
# Picks the container engine: the configured one, else rootless podman, podman, or docker, the
# first installed. A suite that gets the engine's socket needs rootless podman: the socket lets
# a container start containers as whoever runs the engine, and docker's is root's.
# Arguments:
#   "socket" when the suite gets the engine's socket (optional).
# Outputs:
#   podman or docker on stdout.
# Returns:
#   0, or 1 when no usable engine is found.
################################################################################
launch__engine() {
  local engine=""
  if config__has .engine; then
    engine=$(config__get .engine) || return 1
    if ! command -v "$engine" > /dev/null; then
      log__error "engine is $engine, which isn't installed"
      return 1
    fi
  elif launch__rootless_podman; then
    engine=podman
  elif command -v podman > /dev/null; then
    engine=podman
  elif command -v docker > /dev/null; then
    engine=docker
  else
    log__error "needs podman or docker"
    return 1
  fi
  if [[ ${1:-} == socket ]] && ! { [[ $engine == podman ]] && launch__rootless_podman; }; then
    log__error "these tests need rootless podman: they get the engine's socket (engine: $engine)"
    return 1
  fi
  echo "$engine"
}

################################################################################
# The GitHub token from gh, checked for the repo scope.
# Outputs:
#   The token on stdout.
# Returns:
#   0, or 1 when gh isn't logged in or the token lacks the scope.
################################################################################
launch__token() {
  local token scopes
  if ! token=$(gh auth token); then
    log__error "gh isn't logged in (gh auth login)"
    return 1
  fi
  # Classic tokens list their scopes; fine-grained ones don't, and are checked by use.
  scopes=$(GH_TOKEN=$token gh api -i user 2> /dev/null | tr -d '\r' |
    sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: //p')
  if [[ -n $scopes && ,${scopes// /}, != *,repo,* ]]; then
    log__error "the gh token needs the repo scope (gh auth refresh -s repo)"
    return 1
  fi
  echo "$token"
}

################################################################################
# The throwaway repos, checking that each exists, reporting every missing one.
# Outputs:
#   {"distributor": ..., "testbed": ..., "service2": ...} on stdout.
# Returns:
#   0, or 1 when a repo isn't named or doesn't exist.
################################################################################
launch__repos() {
  local role repo repos='{}' failed=false
  if ! config__has .repos && [[ ! -f $(config__state_file) ]]; then
    log__error "no repos: run init.sh, or set repos in $(config__file)"
    return 1
  fi
  for role in distributor testbed service2; do
    if ! repo=$(config__repo "$role"); then
      failed=true
    elif ! gh api "repos/$repo" > /dev/null 2>&1; then
      log__error "$repo not found (init.sh creates the repos)"
      failed=true
    else
      repos=$(jq -c --arg role "$role" --arg repo "$repo" '.[$role] = $repo' <<< "$repos")
    fi
  done
  $failed && return 1
  echo "$repos"
}

################################################################################
# Copies a checkout's code into the run directory as a plain repo with the commit under test
# checked out (detached), whatever the source is. A local checkout gives its HEAD commit (a git
# worktree's .git points outside it, so it's cloned) and must have no uncommitted changes to
# tracked files: they wouldn't be tested. A GitHub repo gives its ref, or its latest release.
# Arguments:
#   Role (distributor or testbed: checkouts.<role> in the configuration), destination.
# Returns:
#   0, or 1 when the code can't be found or copied.
################################################################################
launch__snapshot() {
  local checkout
  checkout=$(config__get ".checkouts.$1") || return 1
  if jq -e 'has("path")' <<< "$checkout" > /dev/null; then
    launch__snapshot_path "$1" "$(jq -r .path <<< "$checkout")" "$2"
  else
    launch__snapshot_repo "$1" "$(jq -r .repo <<< "$checkout")" \
      "$(jq -r '.ref // empty' <<< "$checkout")" "$2"
  fi
}

################################################################################
# launch__snapshot from a local checkout. Relative paths start at this repo's root.
# Arguments:
#   Role, path, destination.
# Returns:
#   0, or 1 when the checkout is missing, not a git checkout, dirty, or can't be copied.
################################################################################
launch__snapshot_path() {
  local path=${2/#\~/$HOME} dir sha
  if [[ $path != /* ]]; then
    path="$(dirname "${BASH_SOURCE[0]}")/../../../$path"
  fi
  if ! dir=$(realpath "$path" 2> /dev/null) || [[ ! -d $dir ]]; then
    log__error "checkouts.$1: $2 not found"
    return 1
  fi
  if ! sha=$(git -C "$dir" rev-parse HEAD 2> /dev/null); then
    log__error "checkouts.$1: $dir isn't a git checkout"
    return 1
  fi
  if [[ -n $(git -C "$dir" status --porcelain --untracked-files=no) ]]; then
    log__error "checkouts.$1: $dir has uncommitted changes (the tests use the HEAD commit)"
    return 1
  fi
  if ! { git clone --quiet --no-checkout "$dir" "$3" &&
    git -C "$3" checkout --quiet --detach "$sha"; } 2> /dev/null; then
    log__error "checkouts.$1: can't copy $dir's HEAD ($sha) into the run directory"
    return 1
  fi
  log__info "$1: ${sha:0:7} from $dir"
}

################################################################################
# launch__snapshot from a GitHub repo, fetched anonymously over HTTPS with its history (the
# seed pushes it whole).
# Arguments:
#   Role, owner/name, ref (empty: the latest release), destination.
# Returns:
#   0, or 1 when there's no release or the ref can't be fetched.
################################################################################
launch__snapshot_repo() {
  local ref=$3
  if [[ -z $ref ]] && ! ref=$(gh release view -R "$2" --json tagName -q .tagName 2> /dev/null); then
    log__error "checkouts.$1: $2 has no release; set checkouts.$1.ref"
    return 1
  fi
  if ! { git init --quiet "$4" &&
    GIT_TERMINAL_PROMPT=0 git -C "$4" fetch --quiet "https://github.com/$2.git" "$ref" &&
    git -C "$4" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD; } 2> /dev/null
  then
    log__error "checkouts.$1: can't fetch $2 at $ref"
    return 1
  fi
  log__info "$1: $(git -C "$4" rev-parse --short HEAD) from $2 at $ref"
}

################################################################################
# Writes the run's settings for the container: the configuration with the repos resolved, and
# the run's own values under .run.
# Arguments:
#   The repos (JSON from launch__repos), run id, run directory (shared with the container),
#   the run's output directory, the engine command in the container (empty when it has none),
#   the file.
# Returns:
#   0, or 1 when it can't be written.
################################################################################
launch__settings() {
  local merged
  merged=$(config__merged) || return 1
  if ! jq --argjson repos "$1" --arg id "$2" --arg share "$3" --arg out "$4" --arg engine "$5" \
    '.repos = $repos | .run = {id: $id, share_dir: $share, output_dir: $out,
      artifacts_dir: "\($out)/artifacts", engine: (if $engine == "" then null else $engine end)}' \
    <<< "$merged" > "$6"; then
    log__error "can't write $6"
    return 1
  fi
}

################################################################################
# Starts a private API service of the user's rootless podman on a socket in the run directory,
# for a suite that starts sibling containers.
# Arguments:
#   Run directory.
# Outputs:
#   The container's options for it on stdout, one word per line.
# Returns:
#   0, or 1 when the service didn't start.
################################################################################
launch__engine_socket() {
  local sock=$1/engine.sock
  # Its output goes elsewhere: this function's stdout is read to its end.
  podman system service --time=0 "unix://$sock" > /dev/null 2>&1 &
  echo $! > "$1/engine.pid"
  for _ in {1..50}; do
    [[ -S $sock ]] && break
    sleep 0.1
  done
  if [[ ! -S $sock ]]; then
    log__error "podman's API service didn't start"
    return 1
  fi
  printf '%s\n' -v "$sock:/run/engine.sock" -e CONTAINER_HOST=unix:///run/engine.sock
}

################################################################################
# Stops the podman service and deletes the run directory (keys, checkout copies, the gateway's
# files).
# Arguments:
#   Run directory, then the engine and tools image once known (to delete root-owned leftovers
#   docker can leave).
################################################################################
launch__cleanup() {
  if [[ -f $1/engine.pid ]]; then kill "$(< "$1/engine.pid")" 2> /dev/null; fi
  [[ -d $1 ]] || return 0
  rm -rf "$1" 2> /dev/null && return 0
  [[ -n $2 && -n $3 ]] || return 0
  IT_ENGINE=$2 engine__run -v "$1:/run-dir" "$3" find /run-dir -mindepth 1 -delete
  rmdir "$1" 2> /dev/null || log__info "warning: couldn't remove $1"
}

################################################################################
# Runs one suite: the bats files under <suite>/cases in a transient tools container. Everything
# the run needs is checked first, and every problem reported at once (only a missing tool stops
# the checks early). The results (TAP)
# go to stdout and <output_dir>/<run id>/report.tap; the settings the container got to
# settings.json there; files tests export to artifacts/ there.
# Arguments:
#   Suite (ci or distro), --engine-socket to give the container the user's rootless podman
#   (optional), then test names and bats options.
# Returns:
#   bats' exit status, or 1 when the run couldn't start.
################################################################################
launch__run() {
  local suite=$1 socket="" root id run_dir engine="" token repos image out role sock status
  local failed=false
  local -a options
  shift
  if [[ ${1:-} == --engine-socket ]]; then
    socket=socket
    shift
  fi
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  launch__check_tools || return 1

  id=$(date -u +%Y%m%dT%H%M%SZ)
  # /dev/shm: RAM-backed, and a short path for the engine socket.
  run_dir=/dev/shm/distributor-it-$id
  if ! mkdir -m 700 "$run_dir"; then
    log__error "can't create $run_dir"
    return 1
  fi
  # shellcheck disable=SC2064 # the values are fixed now
  trap "launch__cleanup '$run_dir'" EXIT

  launch__check_agent || failed=true
  token=$(launch__token) || failed=true
  engine=$(launch__engine $socket) || failed=true
  repos=$(launch__repos) || failed=true
  image=$(config__get .images.tools) || failed=true
  out=$(config__get .output_dir) || failed=true
  out=${out/#\~/$HOME}/$id
  for role in distributor testbed; do
    launch__snapshot "$role" "$run_dir/src/$role" || failed=true
  done
  if $failed; then
    log__error "nothing was run: fix the above first"
    return 1
  fi
  # shellcheck disable=SC2064 # the values are fixed now
  trap "launch__cleanup '$run_dir' '$engine' '$image'" EXIT

  if ! mkdir -p "$out/artifacts"; then
    log__error "can't create $out"
    return 1
  fi
  options=()
  if [[ -n $socket ]]; then
    sock=$(launch__engine_socket "$run_dir") || return 1
    mapfile -t options <<< "$sock"
  fi
  launch__settings "$repos" "$id" "$run_dir" "$out" "${socket:+podman-remote}" \
    "$out/settings.json" || return 1
  log__info "run $id ($suite, $engine); report: $out/report.tap"

  # Ctrl-C reaches the container through the engine, which stops the running test and runs the
  # teardowns; this script and tee wait for that instead of quitting under it.
  trap 'log__info "interrupted: waiting for the tests to tear down"' INT TERM
  printf '%s\n' "$token" | IT_ENGINE=$engine engine__run -i \
    --tmpfs /tmp:exec \
    -v "$root:/suite:ro" \
    -v "$out/settings.json:$(settings__file):ro" \
    -v "$run_dir:$run_dir" -v "$out:$out" \
    -v "$run_dir/src/distributor:/src/distributor:ro" -v "$run_dir/src/testbed:/src/testbed:ro" \
    -v "$SSH_AUTH_SOCK:/run/ssh-agent.sock" -e SSH_AUTH_SOCK=/run/ssh-agent.sock \
    "${options[@]}" "$image" bash /suite/run-in-container.sh "$suite" "$@" |
    tee -i "$out/report.tap"
  status=${PIPESTATUS[1]}
  log__info "report: $out/report.tap"
  return "$status"
}
