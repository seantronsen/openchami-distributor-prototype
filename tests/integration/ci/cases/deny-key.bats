# Denying a repo key prunes everything it admitted, opens a denial issue, and rejects its new
# releases.

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

@test "a denied repo key is pruned and its new releases rejected" {
  local repo name fpr
  repo=$(suite__service2_repo)
  name=$(suite__repo_name "$repo")
  fpr=$(keys__fpr service2)
  crafted__release "$repo" v1.0.0 "$name 1.0.0"
  poll__run > /dev/null
  distributor__push_config > /dev/null << EOF
repos:
  - name: $(suite__testbed_repo)
    allow: [testbed, testbed-quadlet]
  - name: $repo
    deny:
      - fingerprint: $fpr
        reason: distributor-it
EOF
  wait__check "no package still published" state__none_published "$repo"
  wait__check "pruned for the denied key" state__has --arg k "$repo@v1.0.0" \
    --arg r "denied repo key $fpr" '.[$k].packages | all(.status == "pruned" and .reason == $r)'
  wait__check "a denial issue" issues__has_denial "$repo" "$fpr"
  crafted__release "$repo" v1.1.0 "$name 1.1.0"
  poll__run > /dev/null
  wait__check "v1.1.0: rejected for the denied key" state__has \
    --arg k "$repo@v1.1.0" --arg f "$fpr" \
    '.[$k].status == "rejected" and (.[$k].reasons | any(startswith("repo key \($f) is denied")))'
}
