# Distributor spec (prototype)

The central repo from OpenCHAMI/github-actions#43 (decision A2). It pulls signed releases from
OpenCHAMI service repos, verifies them, and publishes their packages to dnf and apt repositories
signed with the OpenCHAMI archive key. "distributor" is a working name; the repo name is pending
a group decision.

This spec covers only the prototype. Everything else (the keyring package, archive key rotation,
keepalive, tests, hosting, more formats) is in [spec-deferred.md](spec-deferred.md).

Background: github-actions `docs/signing.md` (keys, release flow) and `docs/distribution.md`
(design summary).

## Scope

- rpm and deb only. One rpm repository and one apt suite (`stable`), covering amd64, arm64, and
  noarch/all.
- Publishes to a transient local target: each run's target is uploaded as a workflow artifact.
  All target access goes through the `target_*` functions in `lib.sh`, which is where S3 or a
  domain plugs in later.
- Signs with the `ARCHIVE_GPG_KEY` secret, or a throwaway key generated per job when it's unset,
  and publishes that key's public half as `keys/archive.asc` in the target.
- Shell scripts plus GitHub Actions workflows. Runs only in CI.

Not in scope: building service packages, container images (they have their own attestations),
anything a service repo does before its release is published.

## Design principles

- **Parallel by default.** This is close to an embarrassingly parallel problem. Per-release and
  per-package work fans out; only truly shared state (a format's repository metadata, the state
  file) is serialized.
- **Scatter/gather through artifacts.** Parallel jobs never write shared state. Each uploads its
  result as an artifact; one gathering job downloads them all and applies them.
- **Separate concerns.** Admit decides what may be published, publish only adds, prune only
  removes, record only writes state and issues.
- **Fail closed, heal on the next run.** A rejection is a normal outcome. An infrastructure
  failure records nothing, so the next poll retries the same work idempotently.

## Inputs

A service repo release is a candidate when it's published (not a draft) and not flagged as a
prerelease. It must carry the first four files below, under exactly these names:

| File | What it is |
|---|---|
| `checksums.txt` | GoReleaser's SHA-256 list of every release file; the manifest |
| `checksums.txt.asc` | detached signature over it, by the release key |
| `pubkey-signing.asc` | release key, certified by the repo key |
| `pubkey-repo.asc` | repo key (`<owner>/<repo> RPM Signing Key`), certified by the root key |
| `pubkey-org.asc` | root public key; optional and ignored (the pinned copy is used instead) |

Only `.rpm` and `.deb` files listed in `checksums.txt` are considered; everything else is ignored.

## Repository layout

```
config/repos.yaml          service repos, each with optional allow, deny, retain, keep-releases
state/state.json           what has been published, pruned, skipped, or rejected
scripts/                   discover.sh, admit.sh, publish.sh, prune.sh, record.sh
scripts/lib.sh             shared helpers (config, state, GitHub API, target, archive key)
scripts/lib-repo.sh        incremental rpm and apt metadata
scripts/lib.jq             shared jq definitions (published set, denied packages, retention)
.github/workflows/         poll.yml (schedule, config changes, dispatch); _discover.yml,
                           _admit.yml, _publish.yml, _record.yml, _prune.yml (reusable stages)
```

`config/repos.yaml`: one entry per service repo. Only `name` is required; a bare entry just polls
the repo. Removing an entry stops polling that repo; its published packages stay, under the
default retention rules.

```yaml
repos:
  - name: OpenCHAMI/smd
    keep-releases: ["1.4"]    # major.minor lines kept past EOL (quoted: unquoted 1.10 is 1.1)
    retain:                   # exact package versions never deleted
      - {package: smd, version: 2.19.4, reason: pinned by a live deployment}
  - name: OpenCHAMI/release
    allow: [openchami]        # extra package names beyond <repo> and <repo>-*
  - name: OpenCHAMI/github-actions-testbed
    allow: [testbed, testbed-quadlet]
    deny:                     # revoked repo keys: fingerprint (quoted) and why
      - fingerprint: "0000000000000000000000000000000000000000"
        since: "2026-01-01T00:00:00Z"   # optional: prune only what was admitted from then on
        reason: example; leaked and rotated
```

## Workflows

```
poll:   config -> discover -> admit (matrix) -> publish (per format) -> record -> prune
prune:  prune (per format) -> record
```

- `poll` runs about every 10 minutes, on pushes that change `config/repos.yaml` (so a new repo or
  `deny` takes effect right away), and on `workflow_dispatch`. Every stage is a reusable
  workflow (`_discover.yml`, `_admit.yml`, `_publish.yml`, `_record.yml`, `_prune.yml`), so
  `poll.yml` is only the wiring between them. Only poll
  declares the concurrency group, so a called stage never waits on its own caller.
- Each caller's record applies only its own results: poll's artifacts are `poll-*` (admit
  results, publish deltas), prune's are `prune-delta-*`.
- One concurrency group (`poll`) with `cancel-in-progress: false` covers every workflow that
  writes the target or state, so a run is never cancelled mid-write, two runs never rebuild the
  same metadata at once, and GitHub keeps at most one waiting run.
- A waiting run starts on the commit it was queued on, which predates the state its predecessor
  just committed. So poll's first job, `config`, resolves the latest `main` commit, and discover
  and admit both check out that commit: the same state and config for both. Prune checks out
  the latest `main` itself, since it must also see this run's own record.
- Every job has `timeout-minutes: 30`.
- Jobs run on `ubuntu-latest` with its own tools (jq, curl, gpg, rpm, dpkg, mikefarah yq), with no
  container. Only publish and prune install what the runner lacks (`createrepo-c`, and
  `apt-utils` if needed), in those jobs only. Installs live in workflows, never in scripts.
- A job lists in `needs:` only the jobs whose outputs or results it reads.
- State is read from the run's commit: every job checks out `github.sha`, so all jobs in a run see
  the same state. State changes travel as artifacts and are applied only by record, so they're
  visible to the next run, not to other jobs in the same run.

### 1. Discover

- For each repo in `config/repos.yaml`, list its releases through the API.
- Keep releases that are published, not prereleases, and not already in state.
- Emit a matrix of `{repo, tag}`, oldest first, capped at 256 entries (GitHub's matrix limit; more
  fails the whole admit job). The rest wait for the next polls. An empty matrix ends the run
  after prune.

### 2. Admit (one job per release, in parallel)

`admit.sh <owner/repo> <tag> <outdir>` runs every check in one go. Any failed check rejects the
whole release: nothing from it is published, and it gets a rejection issue (see Record). A
rejection is a normal outcome; the job succeeds and the rest of the run is unaffected.

Infrastructure errors (API failures, rate limits, failed downloads) aren't rejections: the job
fails without recording anything, so the release stays first in the queue and the next poll
retries it.

1. Download the four required sidecar files. Missing any of them: reject.
2. Verify the trust chain and the `checksums.txt` signature with github-actions'
   `scripts/gpg-verify-trust-chain.sh`, fetched from its raw URL pinned by commit SHA (constant
   in `lib.sh`, updated by a Renovate custom regex manager). Root key and fingerprint come from
   the `MASTER_PUBLIC_ASC` / `MASTER_FPR` org secrets; `REPO` is the release's repo, so the repo
   key must be certified as `<owner>/<repo> RPM Signing Key`. This covers the chain, the repo
   key's name, expiry and revocation, and the signature. The script returns the repo key's
   fingerprint.
3. Reject if the repo key fingerprint is in the repo's `deny`, whatever its `since`.
4. Download each `.rpm` / `.deb` listed in `checksums.txt` and check its hash.
5. Read each package's metadata (`rpm -qp --qf`, `dpkg-deb -f`): name, version, arch. Packages for
   architectures outside scope (anything but `x86_64`/`aarch64`/`noarch` for rpm,
   `amd64`/`arm64`/`all` for deb) are ignored.
6. Check versions. The version (without a deb revision) must be `major.minor.patch`. With a
   prerelease part (`~rc`, `-rc1`, ...): record the release as `skipped`, no issue. Anything else:
   reject.
7. Check each package:
   - Name: `<repo>` or `<repo>-*` (repo name lowercased), or in the repo's `allow`, and not
     another repo's: a name matching a longer configured repo name's rule (`smd-tools` when both
     `smd` and `smd-tools` are configured) belongs to that repo, and a name already published by
     another repo (per state, even after that repo's entry is removed) stays that repo's.
   - Two packages in the release with the same format, name, version, and arch: reject.
   - The same format, name, version, and arch already in state (published or pruned), whatever
     its hash: reject. That's a re-tag of an existing version; fixes ship as new patch versions.
8. Upload `result.json` (status, reasons, repo key, and the admitted packages: name, version,
   arch, format, filename, sha256) plus the package files as the job's artifact. The sha256 is the
   one from `checksums.txt`, before archive signing changes the rpm. A release left with nothing
   to publish (only ignored packages) is still recorded as `published` with no packages.

### 3. Publish (one job per format)

Publish only adds. Its input is every admitted package of its format from the run's admit
artifacts; it adds all of them. It knows nothing about retention or denied keys.

1. Sign each new rpm with the archive key (`rpmsign --addsign`); debs carry no signature.
2. Upload the package files to the target. Uploads may fan out in parallel; filenames are unique
   per format and version, so they can't collide.
3. Then, serially, update the metadata without downloading old packages:
   - rpm: `createrepo_c` over the new rpms only; `mergerepo_c --all --omit-baseurl` with the
     existing repodata; sign `repomd.xml` (`repomd.xml.asc`).
   - apt: `apt-ftparchive packages` over the new debs only; merge those stanzas into each
     `binary-<arch>/Packages` (`all` packages go into every arch); gzip; `apt-ftparchive release`
     (written outside the scanned tree) for `dists/stable/Release`; sign as `InRelease` and
     `Release.gpg`.
4. Write `keys/archive.asc`.
5. Upload a delta artifact marking each package `published`.

Order: packages, then metadata, so metadata never points at a missing file. Publishing is
idempotent: before merging, existing metadata entries with the same filename as an incoming
package are dropped, so a retry replaces them instead of duplicating them.

### 4. Record

Gathers the run's admit results and deltas and applies them to state, then files issues.

- Applies each change as a delta onto the latest committed state, fetched fresh, never by writing
  back a copy read earlier. Commits only if state changed, and retries the push (fetch, reapply,
  push) up to 3 times if another push lands first. The poller bot has a bypass on the protected
  default branch.
- `record.sh <state|issues|all> <file>...` with explicit mode checks
  (`[[ $mode == state || $mode == all ]]`, ...), dying on any other mode. CI runs `state` inside
  the commit retry loop and `issues` once after it, so a retried push never files issues twice.
- Opens one issue per rejected release (`Rejected release: <repo>@<tag>`, label
  `rejected-release`) with the reasons, the run link, and: "Fix the problem and publish a new
  patch release; this release won't be processed again." If an open issue with that title
  already exists, it's left alone (no duplicate). Skipped (prerelease-version) releases get no
  issue.
- Issues are the notification channel: maintainers watching the repo get them by email through
  GitHub's normal notifications.

### 5. Prune

Prune only removes. It runs as poll's last job on every run, including the runs triggered by
config changes, so a new `deny` takes effect right away. It's a no-op when there's nothing to
remove.

1. From state, take each format's published packages and decide, per package (`decisions`):
   - Denied: admitted with a repo key in its repo's `deny` (all of them, or those admitted at or
     after `since`).
   - Retention (below), over what's left, per `(package, arch)`.
2. Rewrite the metadata without the pruned packages: rpm with `createrepo_c --update --skip-stat
   --recycle-pkglist --excludes <pruned>`; apt by dropping their stanzas by `Filename`. Re-sign.
3. Then delete the pruned package files and any superseded repodata files.
4. Record: mark each package `pruned` with a reason (`retention` or `denied repo key <fpr>`),
   through the same record logic and commit retry; open one issue per denied repo key and wave
   listing what was pruned (`Denied repo key: <repo> <fingerprint> (<date>)`). A package is
   denied only once, so a later wave for the same key (e.g. a `since` moved earlier) always gets
   a new issue, whether or not an earlier one is still open.

Prune works only from state, so a rerun is always safe and a failed prune retries on the next
poll. If the previous prune run also failed, a failure opens or updates a `Prune failing` issue;
the next successful prune closes it.

Accepted costs of the split: a second metadata rewrite and signature when something is pruned; a
superseded patch stays listed until prune runs right after publish; an older patch that arrives
late is published, then pruned.

> [!NOTE]
>
> Version retention policy (default; an assumption pending group discussion):
>
> - Current major (N) and previous major (N-1): keep the latest patch of every minor
>   (X.Y.latest for each Y). Superseded patches are deleted.
> - Majors N-2 and older: end of life; delete.
> - Never delete a package version in the repo's `retain` (live deployments, lockfiles in use,
>   security advisories), regardless of the rules above.
> - A release line in the repo's `keep-releases` (e.g. `["1.4"]`) is never deleted: the latest
>   patch of that major.minor stays for the repo's packages, even past EOL.
>
> N is computed per package, not globally. Retention reads major.minor.patch from each package's
> version (without a deb revision), which GoReleaser derives from the release tag.

## Target layout

```
rpm/packages/<file>.rpm
rpm/repodata/...
deb/pool/main/<first letter>/<name>/<file>.deb
deb/dists/stable/{Release,InRelease,Release.gpg}
deb/dists/stable/main/binary-{amd64,arm64}/Packages{,.gz}
keys/archive.asc
```

## State

`state/state.json`, keyed by `<owner>/<repo>@<tag>`:

```json
{
  "OpenCHAMI/smd@v2.20.4": {
    "status": "published",
    "at": "2026-10-20T12:00:00Z",
    "repo_key": "0BF1EED595FB2201ECF637CA79296C4986AE4087",
    "run": "https://github.com/OpenCHAMI/<name>/actions/runs/123",
    "packages": [
      {"format": "rpm", "name": "smd", "version": "2.20.4", "arch": "x86_64",
       "filename": "smd-2.20.4-1.x86_64.rpm", "sha256": "...", "status": "published"}
    ]
  },
  "OpenCHAMI/foo@v1.0.0": {
    "status": "rejected",
    "at": "2026-10-20T12:10:00Z",
    "run": "https://github.com/OpenCHAMI/<name>/actions/runs/124",
    "reasons": ["checksums.txt.asc: bad signature"]
  }
}
```

- Release status: `published`, `skipped`, or `rejected`. Package status: `published` or `pruned`
  (with a `reason`).
- One file. Parallel jobs never write it; the only writers (poll's and prune's record steps)
  already share a concurrency group. Updates are key lookup and replace.
- State is the source of truth for "already processed" and for what's currently published, so
  nothing has to list the publish target.
- State is also the public record of publication. This repo is the one authority that publishes
  packages under the archive key, and every decision it makes (each package published or pruned,
  with its sha256, the repo key that admitted it, and the run; each rejected or skipped release,
  with its reasons) is committed to public history. Anyone can audit what the archive key has
  vouched for and when, much like a CA's public record of the certificates it issued, and any
  package in the target that state doesn't list wasn't published by this repo.

### Retries and recovery

- A rejected release is never processed again. The only fix, including for config-side causes
  such as a missing `allow`, is a new patch release.
- A run that dies mid-write (runner crash, GitHub outage) records nothing, so the next poll
  reprocesses the same releases and rewrites packages and metadata idempotently; prune likewise.
  The worst case, a half-written apt update (`Packages` written, `Release` not), breaks
  `apt update` until that next run, about 10 minutes. No separate validity check.
- Escape hatch, core maintainers only: deleting or reverting state heals the repo automatically.
  The next polls rediscover every release in batches of 256, republish them idempotently, and
  prune applies retention; the open-issue check keeps old rejections from filing duplicates. This
  is not the normal fix for anything.

## Key changes

### Repo key compromise or revocation

- Add the fingerprint to the repo's `deny`, with an optional `since` (RFC 3339 timestamp, quoted).
  From then on, every new release signed with that key is rejected at admit, whatever `since`
  says.
- The config push triggers prune, which removes already published packages admitted with that key
  (state records each release's repo key): all of them, or only those admitted at or after
  `since`. An issue lists what was pruned. The service repo replaces them with new patch releases
  signed with its new key.

### Root key

A root key compromise or rotation means re-certifying every repo key and updating the
`MASTER_PUBLIC_ASC` / `MASTER_FPR` org secrets. Published packages stay (they're signed with the
archive key); only future admission changes. Handled manually.

## Security

- Only an allowlist of maintainers has any write access; everyone else is read-only.
- No workflow triggers on `pull_request` or `pull_request_target`, so a PR can never reach a
  secret.
- The poller bot has a bypass on the protected default branch for state commits. A bypass can't
  be scoped to one file; the posture is to be revisited.
- Third-party actions pinned by SHA; the trust-chain script pinned by commit SHA in its URL.
- The root public key and fingerprint come only from org secrets, never from a release.
- **Who can push a `v*` tag in a service repo decides what gets published.** Signing runs on any
  `v*` tag push, with the repo key secret, on whatever commit the tag points at, including one
  that's only on an unmerged PR branch; the distributor then publishes the signed release like
  any other. So only maintainers may create, move, or delete `v*` tags: an org-wide tag ruleset
  for `v*` (OpenCHAMI's plan supports org rulesets) is a prerequisite for adding a repo to
  `config/repos.yaml`. A tag-only `release` environment for the repo key secret is the
  complement, so non-tag runs can't reach the key. A planned admit check (spec-deferred.md,
  Release publisher check) backs this up for the archive.
- The archive key (`ARCHIVE_GPG_KEY`) is available only to publish and prune.

## Phases

1. **Local core:** the scripts against the transient local target, with the throwaway archive
   key. Done; being reworked per review 1.
2. **Workflows:** poll with the admit and publish matrices, record (state commits, issues), and
   prune.

Later phases are in [spec-deferred.md](spec-deferred.md).

## PR description notes

- **Assumption pending group discussion:** the version retention policy (Prune, the NOTE). Its
  `retain` and `keep-releases` entries are maintained by hand, since a live deployment or
  lockfile can't be detected from here.
- **Assumption pending group discussion:** a denied repo key prunes the packages admitted with it
  (all, or since a timestamp), rather than only flagging them.
- **Security posture to revisit:** the poller bot's bypass on the default branch covers all
  files, not just `state/state.json`.
