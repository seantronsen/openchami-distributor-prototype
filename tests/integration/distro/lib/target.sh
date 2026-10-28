# shellcheck shell=bash
# The distros' own package managers installing from published repositories, each in a clean
# sibling container, the repository and package signatures checked against the archive key.
# Repositories are in the distributor's publish layout (rpm/, deb/, keys/archive.asc) under a
# base URL: file:///repo for the files themselves, or the gateway's URL. The key always comes
# from the files, mounted at /repo, until the keyring package exists.

[[ -n ${_IT_TARGET_SH:-} ]] && return 0
_IT_TARGET_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/engine.sh"

################################################################################
# Installs a package with dnf, only the published repository enabled.
# Arguments:
#   Image, the published files (a path on the host), base URL, package, then extra engine
#   options (e.g. --network).
# Returns:
#   0 when installed, 1 otherwise.
################################################################################
target__dnf() {
  local image=$1 dir=$2 base=$3 package=$4
  shift 4
  if ! engine__run -i -v "$dir:/repo:ro" -e "BASE=$base" -e "PACKAGE=$package" "$@" "$image" \
    bash -s << 'EOF'; then
set -euo pipefail
cat > /etc/yum.repos.d/it.repo << REPO
[it]
name=it
baseurl=$BASE/rpm
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///repo/keys/archive.asc
REPO
dnf -y -q --disablerepo='*' --enablerepo=it install "$PACKAGE"
rpm -q "$PACKAGE"
EOF
    log__error "dnf on $image couldn't install $package from $base"
    return 1
  fi
}

################################################################################
# Installs a package with apt, only the published repository configured, signed-by the archive
# key.
# Arguments:
#   Image, the published files (a path on the host), base URL, package, then extra engine
#   options (e.g. --network).
# Returns:
#   0 when installed, 1 otherwise.
################################################################################
target__apt() {
  local image=$1 dir=$2 base=$3 package=$4
  shift 4
  if ! engine__run -i -v "$dir:/repo:ro" -e "BASE=$base" -e "PACKAGE=$package" "$@" "$image" \
    bash -s << 'EOF'; then
set -euo pipefail
install -Dm644 /repo/keys/archive.asc /etc/apt/keyrings/it.asc
echo "deb [signed-by=/etc/apt/keyrings/it.asc] $BASE/deb stable main" > /etc/apt/it.list
apt=(apt-get -o Dir::Etc::sourcelist=/etc/apt/it.list -o Dir::Etc::sourceparts=-)
"${apt[@]}" update -qq
"${apt[@]}" install -y -qq "$PACKAGE"
dpkg -s "$PACKAGE" | grep ^Version
EOF
    log__error "apt on $image couldn't install $package from $base"
    return 1
  fi
}
