# Shared jq definitions: `jq -L scripts 'include "lib"; ...'`.

# "1.2.3" -> [1, 2, 3]
def semver: split(".") | map(tonumber);

def repo_of: split("@")[0];

# Config entries keyed by repo name.
def by_name: map({key: .name, value: .}) | from_entries;

# Packages currently published, from state (input), with their release key and repo:
# [{release, repo, format, name, version, arch, filename, sha256}]
def published_packages:
  [to_entries[] | .key as $rel | .value as $r
    | select($r.status == "published")
    | ($r.packages // [])[] | select(.status == "published")
    | . + {release: $rel, repo: ($rel | repo_of), repo_key: $r.repo_key, at: $r.at}];

# Published packages admitted with a denied repo key (all, or admitted at or after `since`),
# from state (input): [{release, repo, format, name, filename, fingerprint}]
def denied_packages($cfg):
  [($cfg | by_name) as $c
    | published_packages[]
    | . as $p
    | (($c[$p.repo].deny // [])[]
        | select((.fingerprint | ascii_upcase) == ($p.repo_key // "" | ascii_upcase))
        | select(.since == null or (($p.at | fromdateiso8601) >= (.since | fromdateiso8601))))
    | {release: $p.release, repo: $p.repo, format: $p.format, name: $p.name,
       filename: $p.filename, fingerprint: (.fingerprint | ascii_upcase)}];

# Retention over candidate packages (input: [{repo, name, arch, version, ...}]); adds
# `keep: true|false` to each. Per (name, arch): majors N and N-1 keep the latest patch of each
# minor, older majors go; `retain` versions and `keep-releases` lines are always kept.
def retention($cfg):
  ($cfg | by_name) as $c
  | group_by([.name, .arch])
  | map(
      map(. + {v: (.version | semver)})
      | (map(.v[0]) | max) as $n
      | group_by(.v[0:2])
      | map((map(.v[2]) | max) as $latest | map(. + {latest: (.v[2] == $latest)}))
      | add
      | map(. as $p | ($c[$p.repo] // {}) as $rc
          | . + {keep: (
              ($p.latest and $p.v[0] >= $n - 1)
              or (($rc.retain // []) | any(.package == $p.name and (.version | tostring) == $p.version))
              or ($p.latest and (($rc["keep-releases"] // []) | any(tostring == "\($p.v[0]).\($p.v[1])")))
            )})
      | map(del(.v, .latest)))
  | add // [];
