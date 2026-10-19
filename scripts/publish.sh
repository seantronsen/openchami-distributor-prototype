#!/usr/bin/env bash
# Publish one format. Only adds: no retention, no denied keys.
#
#   publish.sh <rpm|deb> <outdir> [admit-dir...]
#
# Takes the admitted packages of that format from each admit dir's result.json, signs the rpms,
# writes the packages to the publish target, then merges them into the repository metadata.
# Writes <outdir>/delta-<format>.json for record.
source "$(dirname "$0")/lib.sh"
source "$ROOT/scripts/lib-repo.sh"

[[ $# -ge 2 ]] || die "usage: publish.sh <rpm|deb> <outdir> [admit-dir...]"
fmt=$1 out=$2
shift 2
[[ $fmt == rpm || $fmt == deb ]] || die "unknown format: $fmt"
mkdir -p "$out"
out=$(cd "$out" && pwd)
delta=$out/delta-$fmt.json

new='[]'
for d in "$@"; do
  d=$(cd "$d" && pwd)
  new=$(jq -c --arg fmt "$fmt" --arg d "$d" --slurpfile r "$d/result.json" '
    . + [$r[0] | select(.status == "published") | .key as $k
         | .packages[] | select(.format == $fmt)
         | . + {release: $k, path: "\($d)/\(.path)"}]' <<< "$new")
done

jq -n --arg fmt "$fmt" --argjson new "$new" \
  '{format: $fmt, patches: [$new[] | {release, filename, status: "published"}]}' > "$delta"

if [[ $(jq length <<< "$new") -eq 0 ]]; then
  log "publish $fmt: nothing new"
  exit 0
fi
log "publish $fmt: $(jq length <<< "$new") new"

target_init
archive_key_init

work=$(mktemp -d)
newdir=$work/new
excludes=$work/excludes
# Drop existing metadata entries with the same filename as a new package, so a retried publish
# replaces them instead of duplicating them.
while IFS=$'\t' read -r name filename; do
  if [[ $fmt == rpm ]]; then echo "$filename"; else rel=$(package_path deb "$name" "$filename"); echo "${rel#*/}"; fi
done < <(jq -r '.[] | [.name, .filename] | @tsv' <<< "$new") > "$excludes"

while IFS=$'\t' read -r name filename path; do
  rel=$(package_path "$fmt" "$name" "$filename")
  dest=$newdir/${rel#*/}
  mkdir -p "$(dirname "$dest")"
  cp "$path" "$dest"
  [[ $fmt == rpm ]] && rpm_sign "$dest"
done < <(jq -r '.[] | [.name, .filename, .path] | @tsv' <<< "$new")

if [[ $fmt == rpm ]]; then
  meta=$(rpm_metadata "$work" "$newdir" "$excludes")
else
  meta=$(apt_metadata "$work" "$newdir" "$excludes")
fi

# Packages first, then metadata, so metadata never points at a missing file. Package names are
# unique, so the writes run in parallel.
jq -r '.[] | [.name, .filename] | @tsv' <<< "$new" | while IFS=$'\t' read -r name filename; do
  rel=$(package_path "$fmt" "$name" "$filename")
  printf '%s\0%s\0' "$newdir/${rel#*/}" "$rel"
done | xargs -0 -n 2 -P 8 bash -c 'source "$0"; target_put "$1" "$2"' "$ROOT/scripts/lib.sh"

if [[ $fmt == rpm ]]; then rpm_metadata_write "$meta"; else apt_metadata_write "$meta"; fi

keys_write
log "publish $fmt: done ($PUBLISH_DIR)"
