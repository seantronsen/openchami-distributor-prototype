#!/usr/bin/env bash
# Discover: list releases not yet in state.
# Prints a JSON matrix of {repo, tag}: the oldest new releases first, at most MAX_RELEASES (GitHub
# caps a matrix at 256 jobs); the rest wait for the next polls.
source "$(dirname "$0")/lib.sh"

MAX_RELEASES=256

cfg=$(config_json)

# State goes to jq on stdin: it outgrows the command-line argument limit.
new=$(mktemp)
while IFS= read -r repo; do
  releases=$(releases_list "$repo")
  state_json | jq -c --arg repo "$repo" --argjson rel "$releases" '
    . as $state
    | $rel[] | select((.draft or .prerelease) | not)
    | {repo: $repo, tag: .tag_name, published_at}
    | select($state["\(.repo)@\(.tag)"] == null)' >> "$new"
done < <(jq -r '.[].name' <<< "$cfg")

log "discover: $(wc -l < "$new") new release(s), admitting at most $MAX_RELEASES"
jq -s -c --argjson max "$MAX_RELEASES" 'sort_by(.published_at) | .[:$max] | map({repo, tag})' "$new"
