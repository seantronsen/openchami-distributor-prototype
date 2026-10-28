# shellcheck shell=bash
# The run's throwaway key chain and the repo secrets made from it:
#
#   root      certify-only; MASTER_PUBLIC_ASC and MASTER_FPR on every repo
#   testbed   repo key, certify-only, user ID "<owner>/<repo> RPM Signing Key", certified by
#   service2  the root; GPG_REPO_CERT_KEY_B64 on the testbed (the second repo never builds)
#   archive   signs the distributor's published repositories; ARCHIVE_GPG_KEY on the distributor

[[ -n ${_IT_KEYS_SH:-} ]] && return 0
_IT_KEYS_SH=1

source "$(dirname "${BASH_SOURCE[0]}")/../../lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/suite.sh"

################################################################################
# gpg on the run's GnuPG home (in the shared directory).
# Arguments:
#   gpg arguments.
################################################################################
keys__gpg() {
  GNUPGHOME="$(suite__share_dir)/gnupg" gpg "$@"
}

################################################################################
# A key's fingerprint, as keys__create recorded it.
# Arguments:
#   Role: root, testbed, service2, or archive.
# Outputs:
#   The fingerprint on stdout.
################################################################################
keys__fpr() {
  cat "$(suite__share_dir)/keys/$1.fpr"
}

################################################################################
# Generates a key without a passphrase.
# Arguments:
#   User ID, algorithm, usage, expiry (gpg --quick-generate-key's arguments).
# Outputs:
#   The fingerprint on stdout.
# Returns:
#   0, or 1 when generation failed.
################################################################################
keys__new() {
  local fpr
  fpr=$(keys__gpg --batch --yes --status-fd 1 --passphrase '' --pinentry-mode loopback \
    --quick-generate-key "$@" 2> /dev/null | awk '$2 == "KEY_CREATED" {print $4}')
  if [[ -z $fpr ]]; then
    log__error "can't generate a key for $1"
    return 1
  fi
  echo "$fpr"
}

################################################################################
# Certifies one key with another.
# Arguments:
#   Certifier fingerprint, subject fingerprint.
# Returns:
#   0, or 1 when certification failed.
################################################################################
keys__certify() {
  if ! keys__gpg --batch --yes --pinentry-mode loopback --passphrase '' \
    --quick-sign-key --local-user "$1" "$2" > /dev/null 2>&1; then
    log__error "$1 can't certify $2"
    return 1
  fi
}

################################################################################
# Creates the key chain and records each fingerprint (see keys__fpr). Repo keys outlive
# gpg-sign-artifacts' 30-day expiry check.
# Returns:
#   0, or 1 when a key couldn't be made.
################################################################################
keys__create() {
  local dir root testbed service2 archive
  dir=$(suite__share_dir)
  install -d -m 700 "$dir/gnupg" "$dir/keys"
  root=$(keys__new 'distributor-it root <it-root@invalid>' ed25519 cert 7d) || return 1
  testbed=$(keys__new "$(suite__testbed_repo) RPM Signing Key" ed25519 cert 60d) || return 1
  service2=$(keys__new "$(suite__service2_repo) RPM Signing Key" ed25519 cert 60d) || return 1
  archive=$(keys__new 'distributor-it archive <it-archive@invalid>' rsa3072 sign 7d) || return 1
  keys__certify "$root" "$testbed" || return 1
  keys__certify "$root" "$service2" || return 1
  echo "$root" > "$dir/keys/root.fpr"
  echo "$testbed" > "$dir/keys/testbed.fpr"
  echo "$service2" > "$dir/keys/service2.fpr"
  echo "$archive" > "$dir/keys/archive.fpr"
  log__info "keys: root $root, testbed $testbed, service2 $service2, archive $archive"
}

################################################################################
# Sets the archive key secret on the distributor. Secrets reach gh on stdin only.
# Arguments:
#   "valid" for the run's archive key, or "garbage" for an unusable one.
# Returns:
#   0, or 1 when the secret wasn't set.
################################################################################
keys__set_archive_secret() {
  if ! keys__archive_secret "$1" |
    gh secret set ARCHIVE_GPG_KEY -R "$(suite__distributor_repo)"; then
    log__error "can't set ARCHIVE_GPG_KEY"
    return 1
  fi
}

################################################################################
# The archive key secret's value.
# Arguments:
#   "valid" for the run's archive key, or "garbage" for an unusable one.
# Outputs:
#   The value on stdout.
################################################################################
keys__archive_secret() {
  if [[ $1 == garbage ]]; then
    printf garbage
  else
    keys__gpg --armor --export-secret-keys "$(keys__fpr archive)"
  fi
}

################################################################################
# Sets every secret the repos need from the key chain.
# Returns:
#   0, or 1 when a secret wasn't set.
################################################################################
keys__set_secrets() {
  local repo
  for repo in "$(suite__distributor_repo)" "$(suite__testbed_repo)" "$(suite__service2_repo)"; do
    if ! keys__gpg --armor --export "$(keys__fpr root)" |
      gh secret set MASTER_PUBLIC_ASC -R "$repo" ||
      ! printf '%s' "$(keys__fpr root)" | gh secret set MASTER_FPR -R "$repo"; then
      log__error "can't set the root key secrets on $repo"
      return 1
    fi
  done
  if ! keys__gpg --armor --export-secret-keys "$(keys__fpr testbed)" | base64 -w0 |
    gh secret set GPG_REPO_CERT_KEY_B64 -R "$(suite__testbed_repo)"; then
    log__error "can't set GPG_REPO_CERT_KEY_B64"
    return 1
  fi
  keys__set_archive_secret valid
}

################################################################################
# Deletes every secret on the three repos.
# Returns:
#   0, or 1 when a secret couldn't be deleted.
################################################################################
keys__delete_secrets() {
  local repo name failed=false
  for repo in "$(suite__distributor_repo)" "$(suite__testbed_repo)" "$(suite__service2_repo)"; do
    for name in $(gh secret list -R "$repo" --json name -q '.[].name'); do
      gh secret delete "$name" -R "$repo" || failed=true
    done
  done
  if $failed; then
    log__error "couldn't delete every secret"
    return 1
  fi
}
