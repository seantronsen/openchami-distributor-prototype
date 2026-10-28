# Package name, version, and ownership rules across two service repos.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../lib/crafted.sh"
  source "$BATS_TEST_DIRNAME/../lib/distributor.sh"
  source "$BATS_TEST_DIRNAME/../../lib/log.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

################################################################################
# Whether a release ended with a status and, if given, a reason containing some text.
# Arguments:
#   owner/name, tag, status, reason text (optional).
# Returns:
#   0 when it did, 1 otherwise.
################################################################################
outcome() {
  state__has --arg k "$1@$2" --arg s "$3" --arg r "${4:-}" \
    '.[$k].status == $s and ($r == "" or any(.[$k].reasons[]?; contains($r)))'
}

@test "package names, versions, and ownership follow the rules" {
  local testbed service2 me longer=false
  testbed=$(suite__testbed_repo)
  service2=$(suite__service2_repo)
  me=$(suite__repo_name "$service2")
  # The longer-name rule needs the second repo's name to start with the testbed's plus "-".
  if [[ $me == "$(suite__repo_name "$testbed")"-* ]]; then longer=true; fi

  distributor__push_config > /dev/null << EOF
repos:
  - name: $testbed
    allow: [testbed, testbed-quadlet, it-shared, it-twice]
  - name: $service2
    allow: [it-twice]
EOF
  crafted__release "$service2" v1.0.0-a "zzz-other 1.0.0"
  crafted__release "$service2" v1.0.0-b "it-twice 1.0.0"
  if $longer; then crafted__release "$testbed" it-c "$me-x 1.0.0"; fi
  crafted__release "$testbed" it-d1 "it-shared 1.0.0"
  crafted__release "$service2" v1.0.0-e "$me 1.0"
  crafted__release "$service2" v1.0.0-f "$me 1.0.0~rc1"
  crafted__release "$service2" v1.0.0-g "$me-dup 1.0.0 1" "$me-dup 1.0.0 2"
  poll__run > /dev/null
  wait__check "a: a name the repo can't claim" outcome "$service2" v1.0.0-a rejected \
    "zzz-other is not $me or $me-* and not in allow"
  wait__check "b: a name in another repo's allow" outcome "$service2" v1.0.0-b rejected \
    "it-twice is in another repo's allow"
  if $longer; then
    wait__check "c: a name a longer repo name claims" outcome "$testbed" it-c rejected \
      "belongs to a repo with a longer matching name"
  else
    log__info "c: left out ($me doesn't start with $(suite__repo_name "$testbed")-)"
  fi
  wait__check "d1: an allowed name" outcome "$testbed" it-d1 published
  wait__check "e: not major.minor.patch" outcome "$service2" v1.0.0-e rejected \
    "version 1.0 isn't major.minor.patch"
  wait__check "f: a prerelease version" outcome "$service2" v1.0.0-f skipped
  wait__check "g: a duplicate package" outcome "$service2" v1.0.0-g rejected \
    "duplicate deb package $me-dup 1.0.0"

  # Moving it-shared to the second repo's allow doesn't hand it over: the testbed published it.
  distributor__push_config > /dev/null << EOF
repos:
  - name: $testbed
    allow: [testbed, testbed-quadlet, it-twice]
  - name: $service2
    allow: [it-twice, it-shared]
EOF
  crafted__release "$service2" v1.0.0-d2 "it-shared 2.0.0"
  poll__run > /dev/null
  wait__check "d2: a name another repo published first" outcome "$service2" v1.0.0-d2 rejected \
    "it-shared is already published by $testbed"
}
