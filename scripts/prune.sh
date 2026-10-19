#!/usr/bin/env bash
# Prune one format. Only removes.
#
#   prune.sh <rpm|deb> <outdir>
#
# Decides, from state, which published packages to remove: those admitted with a denied repo key,
# then the retention policy over the rest. Rewrites the repository metadata without them and
# deletes their files. Writes <outdir>/prune-<format>.json for record.
source "$(dirname "$0")/lib.sh"
source "$ROOT/scripts/lib-repo.sh"

[[ $# -eq 2 ]] || die "usage: prune.sh <rpm|deb> <outdir>"
fmt=$1 out=$2
[[ $fmt == rpm || $fmt == deb ]] || die "unknown format: $fmt"
mkdir -p "$out"
out=$(cd "$out" && pwd)
delta=$out/prune-$fmt.json

cfg=$(config_json)
state=$(state_json)

denied=$(jql -c --argjson cfg "$cfg" --arg fmt "$fmt" \
  'include "lib"; denied_packages($cfg) | map(select(.format == $fmt))' <<< "$state")
decisions=$(jql -c --argjson cfg "$cfg" --arg fmt "$fmt" --argjson denied "$denied" 'include "lib";
  published_packages | map(select(.format == $fmt)
    | select(. as $p | $denied | any(.release == $p.release and .filename == $p.filename) | not))
  | retention($cfg)' <<< "$state")
pruned=$(jq -c '[.[] | select(.keep | not)]' <<< "$decisions")

jq -n --arg fmt "$fmt" --argjson pruned "$pruned" --argjson denied "$denied" '
  {format: $fmt,
   patches: ([$pruned[] | {release, filename, status: "pruned", reason: "retention"}]
     + [$denied[] | {release, filename, status: "pruned", reason: "denied repo key \(.fingerprint)"}]),
   denied: $denied}' > "$delta"

remove=$(jq -c -s 'add' <<< "$pruned $denied")
if [[ $(jq length <<< "$remove") -eq 0 ]]; then
  log "prune $fmt: nothing to remove"
  exit 0
fi
log "prune $fmt: $(jq length <<< "$pruned") by retention, $(jq length <<< "$denied") for a denied repo key"

target_init
archive_key_init

work=$(mktemp -d)
excludes=$work/excludes
while IFS=$'\t' read -r name filename; do
  if [[ $fmt == rpm ]]; then echo "$filename"; else rel=$(package_path deb "$name" "$filename"); echo "${rel#*/}"; fi
done < <(jq -r '.[] | [.name, .filename] | @tsv' <<< "$remove") > "$excludes"

if [[ $fmt == rpm ]]; then
  meta=$(rpm_metadata "$work" "$work/new" "$excludes")
  rpm_metadata_write "$meta"
else
  meta=$(apt_metadata "$work" "$work/new" "$excludes")
  apt_metadata_write "$meta"
fi

# Metadata first, then deletes, so metadata never points at a missing file.
while IFS=$'\t' read -r name filename; do
  target_rm "$(package_path "$fmt" "$name" "$filename")"
done < <(jq -r '.[] | [.name, .filename] | @tsv' <<< "$remove")

log "prune $fmt: done ($PUBLISH_DIR)"
