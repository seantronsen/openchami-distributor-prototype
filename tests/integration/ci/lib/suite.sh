# shellcheck shell=bash
# The CI tests' settings, from the run's settings file. Every other lib file gets the repo
# names, directories, and timings from these functions.

[[ -n ${_IT_SUITE_SH:-} ]] && return 0
_IT_SUITE_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/settings.sh"

################################################################################
# The throwaway repos, as owner/name.
# Outputs:
#   owner/name on stdout.
################################################################################
suite__distributor_repo() { settings__get .repos.distributor; }
suite__testbed_repo() { settings__get .repos.testbed; }
suite__service2_repo() { settings__get .repos.service2; }

################################################################################
# A repo's name without its owner, lowercased, as admit compares package names.
# Arguments:
#   owner/name
# Outputs:
#   The name on stdout.
################################################################################
suite__repo_name() {
  local name=${1#*/}
  echo "${name,,}"
}

################################################################################
# The run's shared directory, deleted when the run ends: the GnuPG home, fingerprints, the
# distributor's seed commit. The same path on the host, so sibling containers can mount from it.
# Outputs:
#   The path on stdout.
################################################################################
suite__share_dir() { settings__get .run.share_dir; }

################################################################################
# Where tests export files for later stages (artifacts/<test name>/), kept after the run. The
# same path on the host.
# Outputs:
#   The path on stdout.
################################################################################
suite__artifacts_dir() { settings__get .run.artifacts_dir; }

################################################################################
# The file every repo the suite pushes carries, so the guard knows it's the suite's.
# Outputs:
#   The file name on stdout.
################################################################################
suite__marker() { echo .distributor-it; }

################################################################################
# Waiting: the longest any single wait may take, and the pause between checks, in seconds.
# Outputs:
#   Seconds on stdout.
################################################################################
suite__timeout() { settings__get .timeout; }
suite__poll_interval() { settings__get .poll_interval; }

################################################################################
# Whether to leave the repos as the run left them (no end-of-run cleanup).
# Returns:
#   0 when keeping them, 1 otherwise.
################################################################################
suite__keep() { [[ $(settings__get .keep) == true ]]; }
