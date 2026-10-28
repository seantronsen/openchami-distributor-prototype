# shellcheck shell=bash
# The distro tests' container images, from the run's settings file.

[[ -n ${_IT_IMAGES_SH:-} ]] && return 0
_IT_IMAGES_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/settings.sh"

################################################################################
# An image.
# Outputs:
#   The image on stdout.
################################################################################
images__fedora() { settings__get .images.fedora; }
images__debian() { settings__get .images.debian; }
images__versitygw() { settings__get .images.versitygw; }
