# shellcheck shell=bash
# Crafted releases: tiny but real rpm and deb packages, signed through the run's key chain the
# way gpg-sign-artifacts signs a real release, published as a GitHub release in seconds.

[[ -n ${_IT_CRAFTED_SH:-} ]] && return 0
_IT_CRAFTED_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"
source "$(dirname "${BASH_SOURCE[0]}")/keys.sh"

################################################################################
# Builds a minimal arch-independent deb.
# Arguments:
#   Output directory, package name, version, revision (default 1).
# Returns:
#   0, or 1 when the build failed.
################################################################################
crafted__deb() {
  local out=$1 name=$2 version=$3 rev=${4:-1} root
  root=$(mktemp -d)
  mkdir -p "$root/DEBIAN" "$root/usr/share/doc/$name"
  cat > "$root/DEBIAN/control" << EOF
Package: $name
Version: $version-$rev
Architecture: all
Maintainer: distributor-it <it@invalid>
Description: distributor integration test package
EOF
  echo distributor-it > "$root/usr/share/doc/$name/README"
  if ! dpkg-deb --root-owner-group -Zgzip --build "$root" "$out/${name}_${version}-${rev}_all.deb" \
    > /dev/null; then
    log__error "can't build the deb $name $version-$rev"
    return 1
  fi
}

################################################################################
# Builds a minimal noarch rpm. rpm has no "~" restriction, so prerelease versions work as is.
# Arguments:
#   Output directory, package name, version, release (default 1).
# Returns:
#   0, or 1 when the build failed.
################################################################################
crafted__rpm() {
  local out=$1 name=$2 version=$3 rel=${4:-1} top
  top=$(mktemp -d)
  mkdir -p "$top/SPECS"
  cat > "$top/SPECS/$name.spec" << EOF
Name: $name
Version: $version
Release: $rel
Summary: distributor integration test package
License: MIT
BuildArch: noarch

%description
distributor integration test package

%files
EOF
  if ! rpmbuild --quiet --define "_topdir $top" -bb "$top/SPECS/$name.spec" > /dev/null 2>&1 ||
    ! mv "$top"/RPMS/noarch/*.rpm "$out/"; then
    log__error "can't build the rpm $name $version-$rel"
    return 1
  fi
}

################################################################################
# Writes checksums.txt for a directory's packages and signs it the way gpg-sign-artifacts
# does: a 1-day signing key, certified by the repo's key, plus the three public keys.
# Arguments:
#   Directory, owner/name, "foreign" to leave the signing key uncertified (optional).
# Returns:
#   0, or 1 when signing failed.
################################################################################
crafted__sign() {
  local dir=$1 repo=$2 role signing
  if [[ $repo == "$(suite__testbed_repo)" ]]; then role=testbed; else role=service2; fi
  if ! (cd "$dir" && sha256sum -- *.rpm *.deb > checksums.txt); then
    log__error "can't checksum $dir"
    return 1
  fi
  signing=$(keys__new "$repo Release (distributor-it) <it@invalid>" ed25519 sign 1d) || return 1
  if [[ ${3:-} != foreign ]]; then
    keys__certify "$(keys__fpr "$role")" "$signing" || return 1
  fi
  if ! keys__gpg --batch --yes --armor --local-user "$signing" --detach-sign \
    -o "$dir/checksums.txt.asc" "$dir/checksums.txt"; then
    log__error "can't sign $dir"
    return 1
  fi
  keys__gpg --armor --export "$signing" > "$dir/pubkey-signing.asc"
  keys__gpg --armor --export "$(keys__fpr "$role")" > "$dir/pubkey-repo.asc"
  keys__gpg --armor --export "$(keys__fpr root)" > "$dir/pubkey-org.asc"
}

################################################################################
# Publishes a release of crafted packages: for each spec, a deb and an rpm.
# Arguments:
#   owner/name, tag, then options, then package specs ("name version [revision]").
#   Options: --prerelease (a GitHub prerelease), --foreign (signed by an uncertified key).
# Returns:
#   0, or 1 when building, signing, or the release failed.
################################################################################
crafted__release() {
  local repo=$1 tag=$2 dir spec sign_as='' gh_opts=()
  shift 2
  while [[ ${1:-} == --* ]]; do
    case $1 in
      --prerelease) gh_opts+=(--prerelease) ;;
      --foreign) sign_as=foreign ;;
      *)
        log__error "unknown option $1"
        return 1
        ;;
    esac
    shift
  done
  dir=$(mktemp -d)
  for spec in "$@"; do
    # shellcheck disable=SC2086 # a spec is "name version [revision]"
    crafted__deb "$dir" $spec || return 1
    # shellcheck disable=SC2086
    crafted__rpm "$dir" $spec || return 1
  done
  crafted__sign "$dir" "$repo" ${sign_as:+"$sign_as"} || return 1
  github__release_create "$repo" "$tag" "${gh_opts[@]}" "$dir"/* || return 1
  log__info "released $repo $tag ($*)"
}

################################################################################
# Copies a release's assets to a new release on the same repo (a retag).
# Arguments:
#   owner/name, existing tag, new tag.
# Returns:
#   0, or 1 when the download or the release failed.
################################################################################
crafted__copy_release() {
  local dir
  dir=$(mktemp -d)
  if ! gh release download "$2" -R "$1" -D "$dir"; then
    log__error "can't download $1 $2"
    return 1
  fi
  github__release_create "$1" "$3" "$dir"/* || return 1
  log__info "copied $1 $2 to $3"
}
