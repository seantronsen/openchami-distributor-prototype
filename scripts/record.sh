#!/usr/bin/env bash
# Record a run's results.
#
#   record.sh <state|issues|all> <file>...
#
# state: applies each file to $STATE as a delta: admit result.json files upsert their release
# entry; publish and prune delta files patch package entries (status, reason). Run it on freshly
# fetched state so concurrent writers never overwrite each other.
# issues: opens an issue per rejected release and per denied repo key, unless one is already
# open. CI runs state inside the commit retry loop and issues once after it.
source "$(dirname "$0")/lib.sh"

[[ $# -ge 2 ]] || die "usage: record.sh <state|issues|all> <result.json|delta.json>..."
mode=$1
shift
case $mode in state | issues | all) ;; *) die "unknown mode: $mode (state, issues, or all)" ;; esac

update_state() {
  # Release entries first, then the package patches that refer to them.
  local state f releases=() patches=()
  state=$(state_json)
  for f in "$@"; do
    if jq -e .key "$f" > /dev/null; then releases+=("$f"); else patches+=("$f"); fi
  done
  for f in "${releases[@]}" "${patches[@]}"; do
    state=$(jq -c --slurpfile d "$f" '
      $d[0] as $d
      | if $d.key then
          .[$d.key] = ($d | {status, at, run}
            + (if .status == "published" then {repo_key, packages: [.packages[] | del(.path)]}
               else {reasons} end))
        else
          reduce $d.patches[] as $p (.;
            if .[$p.release] == null then .
            else .[$p.release].packages |= map(
              if .filename == $p.filename then . + ($p | del(.release, .filename)) else . end)
            end)
        end' <<< "$state")
  done

  mkdir -p "$(dirname "$STATE")"
  jq -S . <<< "$state" > "$STATE.tmp"
  mv "$STATE.tmp" "$STATE"
  log "record: updated $STATE"
}

file_issues() {
  local f group
  for f in "$@"; do
    jq -e '.key and .status == "rejected"' "$f" > /dev/null || continue
    issue_ensure "Rejected release: $(jq -r .key "$f")" rejected-release "$(jq -r '
      "Release `\(.key)` was rejected, so none of its packages were published.\n\n"
      + (.reasons | map("- \(.)") | join("\n"))
      + "\n\nRun: \(.run)\n\nFix the problem and publish a new patch release; this release won'"'"'t be processed again."' "$f")"
  done
  # One issue per denied repo key and wave, across the rpm and deb deltas. A package is denied
  # only once, so a later wave for the same key gets its own issue.
  while IFS= read -r group; do
    issue_create "Denied repo key: $(jq -r '.[0] | "\(.repo) \(.fingerprint)"' <<< "$group") ($(date -u +%F))" \
      denied-repo-key \
      "$(jq -r '"These packages were admitted with a denied repo key and have been unpublished:\n\n"
        + (map("- `\(.filename)` (\(.release))") | join("\n"))' <<< "$group")"
  done < <(jq -c -s '[.[].denied // [] | .[]] | group_by([.repo, .fingerprint])[]' "$@")
}

[[ $mode == state || $mode == all ]] && update_state "$@"
[[ $mode == issues || $mode == all ]] && file_issues "$@"
exit 0
