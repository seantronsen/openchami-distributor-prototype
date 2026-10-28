# Denying a repo key from a date prunes only what it admitted since then.

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lifecycle.sh"
  source "$BATS_TEST_DIRNAME/../lib/crafted.sh"
  source "$BATS_TEST_DIRNAME/../lib/distributor.sh"
  source "$BATS_TEST_DIRNAME/../lib/issues.sh"
  source "$BATS_TEST_DIRNAME/../lib/keys.sh"
  source "$BATS_TEST_DIRNAME/../lib/poll.sh"
  source "$BATS_TEST_DIRNAME/../lib/state.sh"
  source "$BATS_TEST_DIRNAME/../lib/suite.sh"
  source "$BATS_TEST_DIRNAME/../lib/wait.sh"
  lifecycle__reset
}

@test "a repo key denied since a date is pruned from that date only" {
  local repo name fpr since
  repo=$(suite__service2_repo)
  name=$(suite__repo_name "$repo")
  fpr=$(keys__fpr service2)
  crafted__release "$repo" v1.0.0 "$name 1.0.0"
  poll__run > /dev/null
  crafted__release "$repo" v1.1.0 "$name 1.1.0"
  poll__run > /dev/null
  since=$(state__get | jq -r --arg k "$repo@v1.1.0" '.[$k].at')
  distributor__push_config > /dev/null << EOF
repos:
  - name: $(suite__testbed_repo)
    allow: [testbed, testbed-quadlet]
  - name: $repo
    deny:
      - fingerprint: $fpr
        since: "$since"
        reason: distributor-it
EOF
  wait__check "v1.1.0: pruned for the denied key" state__has --arg k "$repo@v1.1.0" \
    --arg r "denied repo key $fpr" '.[$k].packages | all(.status == "pruned" and .reason == $r)'
  wait__check "v1.0.0: still published" state__has --arg k "$repo@v1.0.0" \
    '.[$k].packages | all(.status == "published")'
  wait__check "a denial issue" issues__has_denial "$repo" "$fpr"
}
