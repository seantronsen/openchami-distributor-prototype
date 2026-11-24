<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Admission

Admission decides whether a release may be published. One job per release runs every check in
order (`scripts/admit.sh`); the first failure ends it. Part of the [pipeline](README.md).

## Outcomes

| Outcome | When | What happens next |
|---|---|---|
| `published` | every check passes | publish adds its packages |
| `skipped` | a package has a prerelease version (`1.2.0~rc1`, `1.2.0-rc1`) | nothing; no issue |
| `rejected` | any check fails | a `Rejected release` issue lists every reason |
| (nothing) | an API call, download, or the runner fails | no record; the next poll retries the release |

A recorded release is never looked at again, rejected ones included. The only fix for a
rejection, even one the config caused (a missing `allow`, a publisher not yet listed), is a new
patch release. This keeps the decision for a tag final and auditable: a tag can't flip from
rejected to published because someone edited the config later.

## The checks

1. **Sidecars.** The release carries `checksums.txt`, its signature `checksums.txt.asc`, the
   release key, and the repo key (see [what a release provides](../publishing/release.md)).
2. **Publisher.** Everyone who pushed the tag, or ran or re-ran any of its push runs, is listed
   under `publishers` and allowed for this repo. Every run counts, because the API doesn't say
   which run published the release. People are matched by GitHub user ID, since a username can
   be renamed and then registered by someone else. A service's release workflow signs any `v*`
   tag for whoever pushed it, so this list, not the service repo, decides whose releases get
   published.
3. **Trust chain.** github-actions'
   [`gpg-verify-trust-chain.sh`](https://github.com/OpenCHAMI/github-actions/blob/main/scripts/gpg-verify-trust-chain.sh),
   pinned by commit, checks that the root key certified the repo key as
   `<owner>/<repo> RPM Signing Key`, that the repo key certified the release key, and that the
   release key signed `checksums.txt`. See the [trust model](trust-model.md).
4. **Denied key.** The repo key isn't on the repo's `deny` list. Any listed key rejects new
   releases, whatever the entry's `since`; `since` only limits what [prune](pruning.md) removes.
5. **Checksums.** Every `.rpm` and `.deb` listed in `checksums.txt` is attached and matches its
   hash. GitHub renames `~` to `.` in asset names, so both spellings are tried.
6. **Architectures.** Packages for an architecture outside the config's `architectures` are
   dropped from the release, not rejected.
7. **Versions.** Each package's version is `major.minor.patch` (a deb's epoch and revision
   don't count). [Retention](retention.md) depends on this.
8. **Names.** A package belongs to one repo, for good:
   - It must be named `<repo>` or `<repo>-*` (the repo's name, lowercased), or be in its `allow`.
   - A name another repo published first stays that repo's, even after its config entry is
     removed.
   - A name in another repo's `allow`, or matching a longer configured repo name (`smd-tools`
     when both `smd` and `smd-tools` are configured), belongs to that repo.
9. **Duplicates and re-tags.** No two packages in the release share a format, name, version,
   and arch. None of them was admitted before, with any hash: a version is published once, and a
   fix ships as a new patch version.

Checks 7 to 9 report every failing package, so one issue lists everything to fix before the
next release.

## Example

A release of `OpenCHAMI/smd` with a package named `magellan-client` is rejected, unless
`magellan-client` is in smd's `allow` and no other repo already owns the name:

```text
Rejected release: OpenCHAMI/smd@v2.21.0
- magellan-client_2.21.0_amd64.deb: magellan-client is not smd or smd-* and not in allow
```

[Back to Design](README.md)
