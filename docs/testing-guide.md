# Testing the prototype in the wild

A manual sanity check: get one real, signed testbed release through poll and install its
packages from the result. The cases in step 6 are also the list the planned integration suite
automates ([spec-deferred.md](spec-deferred.md), Testing).

Status 2026-10-27: on seantronsen/openchami-distributor-prototype, the first end-to-end run
(40419147500, testbed v0.0.4) admitted, published, and installed with dnf and apt; every case in
step 6 except 12 and 13 (they need crafted releases) passes; the testbed releases from those
runs have since been deleted. GitHub's scheduler fires the `*/10` poll only a few times a day
(2 overnight), so dispatch poll by hand rather than waiting for it.

## 0. Before you start

- Commit the prototype on `main`.
- Keep github-actions commit `4dc5bc0` (PR 58's head) reachable: `VERIFY_CHAIN_URL` in
  `scripts/lib.sh` pins it. Don't force-push it away; if you do, re-pin.

## 1. A repo to run in

Use a personal sandbox repo (e.g. `seantronsen/openchami-distributor-prototype`). The org's
`main` ruleset (PRs and signed commits required) would block the bot's state commits, and a
personal repo also gets schedules and `workflow_dispatch` without merging anything.

```bash
gh repo create seantronsen/openchami-distributor-prototype --public
git remote add sandbox git@github.com:seantronsen/openchami-distributor-prototype.git
git push sandbox main
```

## 2. A signed testbed release

The testbed has no releases. Push a stable tag (not `-rc`, which is skipped by design) on the
testbed PR 17 branch; its release flow builds, signs (through PR 58's refactored check), attaches
the sidecars, and publishes.

```bash
cd ../github-actions-testbed
git checkout seantronsen/testing-pr-56
git tag v1.0.0 && git push origin v1.0.0
gh run watch -R OpenCHAMI/github-actions-testbed \
  "$(gh run list -R OpenCHAMI/github-actions-testbed -w release -L 1 --json databaseId -q '.[0].databaseId')"
gh release view v1.0.0 -R OpenCHAMI/github-actions-testbed --json isDraft,isPrerelease,assets \
  -q '{isDraft, isPrerelease, assets: [.assets[].name]}'
```

Expect a published, non-prerelease release with `checksums.txt`, `checksums.txt.asc`,
`pubkey-signing.asc`, `pubkey-repo.asc`, `pubkey-org.asc`, and the testbed rpms and debs.

## 3. Secrets on the sandbox

The root key is the org's `MASTER_PUBLIC_ASC`. The release you just made carries a copy as
`pubkey-org.asc`; that's fine for a sandbox (the distributor itself never trusts a release's
copy).

```bash
d=$(mktemp -d)
gh release download v1.0.0 -R OpenCHAMI/github-actions-testbed -p pubkey-org.asc -D "$d"
gh secret set MASTER_PUBLIC_ASC -R seantronsen/openchami-distributor-prototype < "$d/pubkey-org.asc"
gpg --show-keys --with-colons "$d/pubkey-org.asc" | awk -F: '$1=="fpr" {print $10; exit}' \
  | gh secret set MASTER_FPR -R seantronsen/openchami-distributor-prototype

# A test archive key, so every job signs with the same key.
export GNUPGHOME=$(mktemp -d)
gpg --batch --passphrase '' --quick-generate-key 'OpenCHAMI test archive key' rsa3072 sign 1y
gpg --batch --armor --export-secret-keys | gh secret set ARCHIVE_GPG_KEY -R seantronsen/openchami-distributor-prototype
unset GNUPGHOME
```

`config/repos.yaml` already lists the testbed with `allow: [testbed, testbed-quadlet]`.

## 4. Run poll

```bash
gh workflow run poll.yml -R seantronsen/openchami-distributor-prototype
run=$(gh run list -R seantronsen/openchami-distributor-prototype -w poll -L 1 --json databaseId -q '.[0].databaseId')
gh run watch -R seantronsen/openchami-distributor-prototype "$run"
```

Expect:

- discover: a matrix with `OpenCHAMI/github-actions-testbed` / `v1.0.0`.
- admit: the chain verifies; the job log ends with `published`.
- publish (rpm, deb): uploads `target-publish-rpm` and `target-publish-deb`.
- record: a `state: poll ...` commit on the sandbox's `main`.
- prune: nothing to remove.

```bash
git fetch sandbox && git show sandbox/main:state/state.json | jq .
```

## 5. Install from the result

```bash
# Separate dirs: both artifacts carry the same keys/archive.asc.
t=$(mktemp -d)
gh run download "$run" -R seantronsen/openchami-distributor-prototype -n target-publish-rpm -D "$t/rpm"
gh run download "$run" -R seantronsen/openchami-distributor-prototype -n target-publish-deb -D "$t/deb"

# Check the published key is the one you created.
gpg --show-keys "$t/rpm/keys/archive.asc"

# dnf, with package and repository signatures checked. Install testbed only: testbed-quadlet
# also needs distro packages (keep the distro repos enabled to install it too).
podman run --rm -v "$t/rpm:/repo:ro,Z" docker.io/library/fedora:42 bash -c '
  printf "[oc]\nname=oc\nbaseurl=file:///repo/rpm\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///repo/keys/archive.asc\n" \
    > /etc/yum.repos.d/oc.repo
  dnf -y install testbed && rpm -q testbed'

# apt, with the Release signature checked
podman run --rm -v "$t/deb:/repo:ro,Z" docker.io/library/debian:13 bash -c '
  install -Dm644 /repo/keys/archive.asc /etc/apt/keyrings/oc.asc
  echo "deb [signed-by=/etc/apt/keyrings/oc.asc] file:/repo/deb stable main" > /etc/apt/sources.list.d/oc.list
  apt-get update -qq && apt-get install -y testbed && dpkg -s testbed | grep ^Version'
```

## 6. Cases to run

Each case is one of two kinds:

- **GitHub**: needs a real run on the sandbox, because it tests what only GitHub does (triggers,
  the reusable-workflow wiring, artifacts between jobs, concurrency, `GITHUB_TOKEN` permissions,
  real commits and issues). Always a human, by hand. Rerun every GitHub case after any change to
  `.github/workflows/`; after a script-only change, case 2 is enough.
- **Local**: tests script logic only, so the unit tests (spec-deferred.md, Testing) can cover
  them without GitHub. They aren't built yet, so for now these are manual too, on the sandbox.

The planned integration suite will run every case, both kinds, against throwaway repos.

After each case, check the run, `state/state.json` on the sandbox's `main`, and the sandbox's
issues. Dispatch poll after each setup step (`gh workflow run poll.yml -R <sandbox>`).

Making releases on the testbed:

- A `v*` tag runs the testbed's release workflow: GoReleaser builds, signs, and publishes.
  GoReleaser builds the highest tag on the commit (github-actions#59), so every new `v*` tag must
  be the highest one on its commit.
- Crafted releases (cases 4-6) are made with `gh release create` under a non-`v*` tag (e.g.
  `test-retag`), so the release workflow doesn't fire and overwrite them. Discover sees every
  non-draft release whatever its tag, and admit reads versions from the packages. Pass
  `--latest=false`.
- Delete each crafted release and its tag right after its poll
  (`gh release delete <tag> --cleanup-tag --yes`): `gh release create` tags the default branch's
  head, and the testbed's PR builds then derive their snapshot version from that non-semver tag
  and fail (dpkg rejects `test-badsig-SNAPSHOT-...`). State keeps the rejection either way.

| # | Case | Kind | Last result |
|---|---|---|---|
| 1 | No-op poll | GitHub | pass 2026-10-27 |
| 2 | Publish and retention | GitHub | pass 2026-10-27 (v0.0.7) |
| 3 | Prerelease skip | Local | pass 2026-10-27 |
| 4 | Rejection: missing sidecars | Local | pass 2026-10-27 |
| 5 | Rejection: re-tagged version | Local | pass 2026-10-27 |
| 6 | Rejection: broken chain | Local | pass 2026-10-27 |
| 7 | Deny, and the config-push trigger | Local, trigger GitHub | pass 2026-10-27 |
| 8 | Deny with `since` | Local | pass 2026-10-27 |
| 9 | Cancelled or failed run | GitHub | pass 2026-10-27 |
| 10 | Prune failing | GitHub | pass 2026-10-27 |
| 11 | Install from the target (dnf, apt) | Local | pass 2026-10-26 (step 5) |
| 12 | Name, version, and ownership rules | Local | |
| 13 | 256-release cap | Local | |
| 14 | Overlapping runs | GitHub | pass 2026-10-27 (after the config-job fix) |

1. **No-op poll.** Dispatch poll (or let the schedule fire) with nothing new. Expect discover to
   find nothing, admit/publish/record skipped, prune to run with nothing to remove, and no state
   commit.
2. **Publish and retention.** Push a newer `v*` tag on the testbed. Expect it admitted and
   published, then prune marks every package of the previous patch `pruned` (reason
   `retention`) in the same run: two state commits, one from poll's record and one from prune's.
   The prototype's target is rebuilt in every run, so check state, not the `target-prune-*`
   artifact, for the removal.
3. **Prerelease skip.** Push a `-rc` tag (e.g. `v0.0.6-rc1`); GoReleaser marks it a prerelease.
   Expect no state entry and no issue.
4. **Rejection, missing sidecars.** `gh release create test-empty --notes test --latest=false`,
   with no assets. Expect `rejected` with a "missing ..." reason per sidecar and one
   `Rejected release: ...@test-empty` issue (label `rejected-release`). Later polls don't touch
   it, and no duplicate issue.
5. **Rejection, re-tagged version.** Download every asset of an admitted release and
   `gh release create test-retag ... <assets>`. Do it while that release's 1-day signing key is
   still valid, or admit rejects it for the chain instead. Expect `rejected` with "... was
   already admitted; ship a new patch version" for each package.
6. **Rejection, broken chain.** Same as 5, but replace `checksums.txt.asc` with a detached
   signature from any other key (`gpg --armor --detach-sign`); tag `test-badsig`. Expect
   `rejected` with "trust chain or checksums.txt signature didn't verify"; the admit log names
   the check that failed.
7. **Deny.** Add the testbed's repo key (state's `repo_key`) under `deny` in
   `config/repos.yaml` and push to the sandbox; the push itself must trigger poll. Expect every
   published testbed package `pruned` with `denied repo key <fpr>`, and one
   `Denied repo key: OpenCHAMI/github-actions-testbed <fpr>` issue. A later `v*` release is
   rejected at admit with "repo key ... is denied". Pruned packages don't come back when the
   entry is removed.
8. **Deny with `since`.** Needs two releases published at once: retention keeps the latest patch
   of each minor, so publish e.g. 0.0.7 and 0.1.0. Set `since` between their `at` times in state
   (use the later one's `at`). Expect only the later release's packages pruned, and one
   `Denied repo key` issue. Run before 7: 7 prunes everything.
9. **Cancelled or failed run.** Dispatch poll while a new release is waiting, and
   `gh run cancel` it once admit is running. Expect no state commit and no issue; the next poll
   admits and publishes the release as usual.
10. **Prune failing.** Set the sandbox's `ARCHIVE_GPG_KEY` to garbage, then give prune work
    (e.g. combine with 7 or 8): prune fails with "ARCHIVE_GPG_KEY doesn't import" and commits
    nothing. Dispatch again: the second failure opens a `Prune failing` issue (label
    `prune-failing`). Restore the key and dispatch: prune applies, and the issue is closed.
    Prune exits before reading the key when it has nothing to remove, so it needs work to fail.
11. **Install from the target.** Step 5: dnf with `gpgcheck` and `repo_gpgcheck`, apt with
    `signed-by`, from a run's `target-publish-*` artifacts.
12. **Name, version, and ownership rules.** Releases whose packages: aren't the repo's name or
    `<name>-*` and not in `allow`; are in another repo's `allow`; match a longer repo name; were
    first published by another repo; have a non-`major.minor.patch` version (rejected) or a
    prerelease version in a non-prerelease release (skipped); duplicate a package within the
    release. Expect each rejected or skipped with its reason. Needs a second service repo and
    crafted releases (the integration suite or the local harness).
13. **256-release cap.** More than 256 new releases at once. Expect the oldest 256 admitted and
    the rest on later polls. Needs crafted releases, as 12.
14. **Overlapping runs.** Dispatch poll twice in quick succession while a release is waiting.
    Expect the second run to wait for the first (concurrency group `poll`), then find nothing
    new; state stays consistent.

## 7. Presentation run

One fixed sequence from a clean slate, so the results read like a slide deck: each main case
in order, its offshoots right after it, and every tag, release, state commit, and issue in the
same order every time. Use it for the report to the team; the cases above are for debugging.

Clean slate: no testbed releases or `v*` tags, sandbox `state/state.json` = `{}`, no sandbox
issues, no `deny` in `config/repos.yaml`, `ARCHIVE_GPG_KEY` = the test key. Every `v*` tag goes
on the testbed PR branch in this order (each is the highest on its commit); dispatch poll after
each step unless it says otherwise, and record the run URL, state commit, and issues per step.
Delete each `test-*` release right after its step's poll (see step 6, Making releases).

| Step | Do | Case | Expect |
|---|---|---|---|
| 1 | tag `v1.0.0` | 2, 11 | published; install with dnf and apt (step 5) |
| 1a | poll again | 1 | no-op: no state commit |
| 1b | tag `v1.0.1-rc1` | 3 | ignored: no state entry, no issue |
| 2 | tag `v1.0.1` | 2 | published; every 1.0.0 package `pruned` (`retention`) |
| 3 | `test-retag`: all of v1.0.1's assets (same day) | 5 | rejected: already admitted; issue |
| 3a | `test-empty`: no assets | 4 | rejected: missing sidecars; issue |
| 3b | `test-badsig`: v1.0.1's assets, foreign `checksums.txt.asc` | 6 | rejected: trust chain; issue |
| 4 | tag `v1.1.0`; dispatch, cancel during admit | 9 | cancelled run: no state commit |
| 4a | poll again | 9 | v1.1.0 published; 1.0.1 kept (latest of 1.0) |
| 5 | tag `v1.2.0`; dispatch twice at once | 14 | second run waits, then no-op; 1.2.0 published |
| 6 | push `deny` with `since` = v1.2.0's `at` | 8 | push triggers poll; only 1.2.0 pruned; issue |
| 7 | set `ARCHIVE_GPG_KEY` to garbage; push `deny` without `since` | 10 | prune fails, no state commit |
| 7a | poll again | 10 | prune fails; `Prune failing` issue |
| 7b | restore the key; poll | 7, 10 | 1.0.1 and 1.1.0 pruned; new deny issue for this wave; `Prune failing` closed |
| 8 | tag `v1.2.1` | 7 | rejected: repo key is denied; issue |

Expected issues at the end, in order: three `Rejected release` (steps 3-3b), `Denied repo key`
(step 6), `Prune failing` (closed, step 7a), `Denied repo key` (step 7b), `Rejected release`
(step 8). Cases 12 and 13 need crafted releases and aren't part of this run.

## Cleanup

Delete every testbed release and tag the run made. Then reset the sandbox for the next run:
push `state/state.json` = `{}` and a `config/repos.yaml` without `deny`; delete its issues,
workflow runs (which removes their artifacts), and the labels the runs created; keep the
secrets, with `ARCHIVE_GPG_KEY` back on the test key. Or delete the sandbox.

```bash
T=OpenCHAMI/github-actions-testbed S=seantronsen/openchami-distributor-prototype
for t in $(gh release list -R $T -L 100 | cut -f3); do gh release delete "$t" -R $T --cleanup-tag --yes; done
for n in $(gh issue list -R $S --state all -L 100 --json number -q '.[].number'); do gh issue delete "$n" -R $S --yes; done
for id in $(gh api --paginate "repos/$S/actions/runs?per_page=100" -q '.workflow_runs[].id'); do
  gh api -X DELETE "repos/$S/actions/runs/$id"
done
for l in rejected-release denied-repo-key prune-failing; do gh label delete "$l" -R $S --yes; done
```
