# shellcheck shell=bash
# Random names.

[[ -n ${_IT_RANDOM_SH:-} ]] && return 0
_IT_RANDOM_SH=1

################################################################################
# Random lowercase hex characters.
# Arguments:
#   How many.
# Outputs:
#   The characters on stdout.
################################################################################
random__hex() {
  head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c "1-$1"
}
