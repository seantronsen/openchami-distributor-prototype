# shellcheck shell=bash
# The container engine: podman or docker on the host, or podman-remote inside the distro tools
# container (sibling containers through the host's rootless podman socket).

[[ -n ${_IT_ENGINE_SH:-} ]] && return 0
_IT_ENGINE_SH=1

################################################################################
# Runs a transient container: removed on exit, a minimal init as PID 1 (so signals like Ctrl-C
# reach the command), SELinux relabeling off (mounts are shared with the host).
# Globals:
#   IT_ENGINE: the engine command (podman, docker, or podman-remote)
# Arguments:
#   The rest of the run command line: options, image, command.
# Returns:
#   The container's exit status.
################################################################################
engine__run() {
  "$IT_ENGINE" run --rm --init --security-opt label=disable "$@"
}
