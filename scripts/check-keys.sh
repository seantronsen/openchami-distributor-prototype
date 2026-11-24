#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
# SPDX-License-Identifier: MIT

# Check the archive key, at the start of every poll.
#
#   check-keys.sh
#
# Fails when ARCHIVE_GPG_KEY isn't keys/archive.asc (keys__archive_load) or expires within the
# config's archive_key.warn_days, and keeps the "Archive key expiring" and "Archive key switch
# due" issues open or closed to match. Fails without ARCHIVE_GPG_KEY, so a poll never runs
# without the key.
#
# Environment: GITHUB_TOKEN, GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID, ARCHIVE_GPG_KEY
#  (required); ARCHIVE_GPG_PASSPHRASE (optional).
source "$(dirname "$0")/lib/base.sh"
source "$(dirname "$0")/lib/config.sh"
source "$(dirname "$0")/lib/github.sh"
source "$(dirname "$0")/lib/keys.sh"

EXPIRING="Archive key expiring"
SWITCH_DUE="Archive key switch due"

################################################################################
# Days until the archive key's primary key or a signing subkey expires.
# Outputs:
#   The days on stdout, or nothing if it never expires.
################################################################################
days_to_expiry() {
  local expires
  expires="$(gpg --batch --with-colons --list-keys "${ARCHIVE_FPR}" \
    | awk -F: '($1=="pub" || ($1=="sub" && $12 ~ /s/)) && $7 != "" {print $7}' | sort -n | head -1)"
  [[ -z "${expires}" ]] || echo $(((expires - $(date +%s)) / 86400))
}

################################################################################
# Opens the expiring issue within the warning days of expiry, else closes it.
# Arguments:
#   <warning days>
# Returns:
#   1 within the warning days of expiry, so the run fails.
################################################################################
fail_if_archive_key_expiring() {
  local warn_days="$1" days
  days="$(days_to_expiry)"
  if [[ -n "${days}" && "${days}" -lt "${warn_days}" ]]; then
    log__info "check-keys: archive key ${ARCHIVE_FPR} expires in ${days} day(s)"
    github__issue_ensure_open "${EXPIRING}" archive-key \
      "Archive key \`${ARCHIVE_FPR}\` expires in ${days} day(s). Rotate it \
(docs/operations/archive-key/rotation.md). Run: $(github__current_run_url)"
    return 1
  fi
  github__issue_close "${EXPIRING}" archive-key \
    "The archive key no longer expires within ${warn_days} days."
}

################################################################################
# Days since keys/archive-next.asc was first committed.
# Outputs:
#   The days on stdout, or nothing if it isn't there.
################################################################################
days_since_next_key_committed() {
  local added
  [[ -f "${ROOT}/keys/archive-next.asc" ]] || return 0
  added="$(git -C "${ROOT}" log --diff-filter=A --format=%ct -- keys/archive-next.asc | tail -1)"
  [[ -n "${added}" ]] \
    || log__fatal "keys/archive-next.asc has no history (check out with full history)"
  echo $((($(date +%s) - added) / 86400))
}

################################################################################
# Reminds a maintainer to switch keys once the grace period is over. Never fails the run.
# Arguments:
#   <grace period, days>
################################################################################
update_switch_due_issue() {
  local warn_days="$1" days
  days="$(days_since_next_key_committed)"
  if [[ -z "${days}" ]]; then
    github__issue_close "${SWITCH_DUE}" archive-key \
      "keys/archive-next.asc is gone: the switch is done."
  elif [[ "${days}" -ge "${warn_days}" ]]; then
    github__issue_ensure_open "${SWITCH_DUE}" archive-key \
      "\`keys/archive-next.asc\` was committed ${days} days ago, so clients have had the keyring \
carrying it for the grace period. Switch keys now \
(docs/operations/archive-key/rotation.md, step 3)."
  fi
}

################################################################################
# Loads the archive key, then runs both checks with the config's archive_key.warn_days.
################################################################################
main() {
  local warn_days
  base__env_require GITHUB_TOKEN GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_RUN_ID ARCHIVE_GPG_KEY
  warn_days="$(config__get .archive_key.warn_days)"
  keys__archive_load
  update_switch_due_issue "${warn_days}"
  fail_if_archive_key_expiring "${warn_days}"
  log__info "check-keys: archive key ${ARCHIVE_FPR} OK"
}

main "$@"
