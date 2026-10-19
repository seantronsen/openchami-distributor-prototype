# shellcheck shell=bash
# Repository metadata updates for publish, without downloading old packages.
# Needs lib.sh, target_init, and archive_key_init.

RPM_COMPRESS=(--general-compress-type=gz --no-database --quiet)

# Rebuilds the rpm metadata: starts from the target's repodata, drops the entries for the files
# listed in <excludes> (one filename per line), merges in <new>/packages/*.rpm (already signed),
# and signs repomd.xml. Prints the directory holding the new repodata/.
rpm_metadata() { # <work> <new> <excludes>
  local work=$1 new=$2 excludes=$3 old=$1/rpm-old have_old=false have_new=false href f
  mkdir -p "$old/repodata" "$new/packages"
  if target_get rpm/repodata/repomd.xml "$old/repodata/repomd.xml"; then
    have_old=true
    while IFS= read -r href; do
      target_get "rpm/$href" "$old/$href" || die "rpm/$href is referenced by repomd.xml but missing"
    done < <(grep -o 'href="repodata/[^"]*"' "$old/repodata/repomd.xml" | cut -d'"' -f2)
    if [[ -s $excludes ]]; then
      local args=()
      while IFS= read -r f; do args+=(--excludes "packages/$f"); done < "$excludes"
      createrepo_c "${RPM_COMPRESS[@]}" --update --skip-stat --recycle-pkglist "${args[@]}" "$old"
    fi
  fi
  compgen -G "$new/packages/*.rpm" > /dev/null && have_new=true
  [[ $have_new == true ]] && createrepo_c "${RPM_COMPRESS[@]}" "$new"

  local result
  if [[ $have_old == true && $have_new == true ]]; then
    mergerepo_c --all --omit-baseurl --no-database --compress-type=gz \
      --repo "$old" --repo "$new" -o "$work/rpm-merged" > /dev/null
    result=$work/rpm-merged
  elif [[ $have_old == true ]]; then
    result=$old
  elif [[ $have_new == true ]]; then
    result=$new
  else
    createrepo_c "${RPM_COMPRESS[@]}" "$new"
    result=$new
  fi
  rm -f "$result/repodata/repomd.xml.asc"
  gpg --batch --armor --detach-sign -o "$result/repodata/repomd.xml.asc" "$result/repodata/repomd.xml"
  echo "$result"
}

# Writes the rpm repodata to the target: data files first, then repomd.xml and its signature,
# then removes repodata files the new repomd.xml no longer references.
rpm_metadata_write() { # <dir holding repodata/>
  local dir=$1 f
  for f in "$dir"/repodata/*; do
    case ${f##*/} in repomd.xml | repomd.xml.asc) ;; *) target_put "$f" "rpm/repodata/${f##*/}" ;; esac
  done
  target_put "$dir/repodata/repomd.xml" rpm/repodata/repomd.xml
  target_put "$dir/repodata/repomd.xml.asc" rpm/repodata/repomd.xml.asc
  for f in $(target_ls rpm/repodata); do
    [[ -e $dir/repodata/$f ]] || target_rm "rpm/repodata/$f"
  done
}

# Keeps the stanzas of a Packages file whose Filename isn't in <excludes> (pool paths) and,
# when <arch> is set, whose Architecture is <arch> or all.
apt_filter() { # <excludes> <arch> < Packages
  awk -v ex="$1" -v arch="$2" '
    BEGIN { while ((getline l < ex) > 0) skip[l] = 1; RS = ""; ORS = "\n\n" }
    {
      n = split($0, L, "\n"); f = ""; a = ""
      for (i = 1; i <= n; i++) {
        if (L[i] ~ /^Filename: /) f = substr(L[i], 11)
        if (L[i] ~ /^Architecture: /) a = substr(L[i], 15)
      }
      if (!(f in skip) && (arch == "" || a == arch || a == "all")) print
    }'
}

# Rebuilds the apt metadata: per architecture, the target's Packages minus <excludes> (pool
# paths, one per line) plus the stanzas for <new>/pool/**.deb; then Release, InRelease, and
# Release.gpg. Prints the directory holding the new dists/.
apt_metadata() { # <work> <new> <excludes>
  local work=$1 new=$2 excludes=$3 out=$1/apt-out arch
  local dist=$out/dists/$SUITE
  mkdir -p "$new/pool"
  (cd "$new" && apt-ftparchive packages pool 2> /dev/null) > "$work/new.Packages"
  for arch in "${DEB_ARCHES[@]}"; do
    local bin=$dist/main/binary-$arch
    mkdir -p "$bin"
    target_get "deb/dists/$SUITE/main/binary-$arch/Packages" "$work/old.Packages.$arch" \
      || : > "$work/old.Packages.$arch"
    {
      apt_filter "$excludes" "" < "$work/old.Packages.$arch"
      apt_filter /dev/null "$arch" < "$work/new.Packages"
    } > "$bin/Packages"
    gzip -9nc "$bin/Packages" > "$bin/Packages.gz"
  done
  (cd "$out" && apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=OpenCHAMI \
    -o APT::FTPArchive::Release::Label=OpenCHAMI \
    -o APT::FTPArchive::Release::Suite="$SUITE" \
    -o APT::FTPArchive::Release::Codename="$SUITE" \
    -o APT::FTPArchive::Release::Architectures="${DEB_ARCHES[*]}" \
    -o APT::FTPArchive::Release::Components=main \
    release "dists/$SUITE") > "$work/Release"
  mv "$work/Release" "$dist/Release"
  apt_sign "$dist"
  echo "$out"
}

apt_sign() { # <dist dir holding Release>
  rm -f "$1/InRelease" "$1/Release.gpg"
  gpg --batch --clearsign -o "$1/InRelease" "$1/Release"
  gpg --batch --armor --detach-sign -o "$1/Release.gpg" "$1/Release"
}

# Writes the apt metadata: Packages files first, then Release, Release.gpg, and InRelease.
apt_metadata_write() { # <dir holding dists/>
  local dist=$1/dists/$SUITE arch f
  for arch in "${DEB_ARCHES[@]}"; do
    for f in Packages Packages.gz; do
      target_put "$dist/main/binary-$arch/$f" "deb/dists/$SUITE/main/binary-$arch/$f"
    done
  done
  for f in Release Release.gpg InRelease; do
    target_put "$dist/$f" "deb/dists/$SUITE/$f"
  done
}

# Publishes the archive public key as keys/archive.asc.
keys_write() {
  target_put "$ARCHIVE_PUB" keys/archive.asc
}
