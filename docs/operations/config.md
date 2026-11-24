<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Config

`config/distributor.yaml` is the live configuration: poll reads it from the latest `main` on
every run. Its comments describe every setting; `schemas/distributor.schema.json` defines what's
valid, and `validate` checks it on every pull request. This page covers what the comments don't:
what a change sets in motion.

| Section | What it controls |
|---|---|
| `target` | where to publish ([deployment](deployment.md)) |
| `architectures`, `max_releases`, `archive_key` | what's published, how many releases one poll admits, the archive key's warning period |
| `publishers` | who may push the tags of releases that get published |
| `repos` | which service repos are polled, and each one's `allow`, `deny`, `retain`, and `keep_releases` |

What a change does:

- **Any push changing the file triggers a poll right away.** A new repo starts being polled, and a
  new `deny` or retention change is applied by that poll's prune.
- **A bad config fails the whole run** before anything is admitted, so it can never reject a
  release. Fix it and push again.
- **Config-caused rejections are permanent.** A release rejected for a missing `allow` or
  publisher isn't retried after the config is fixed; the service repo ships a new patch release.
  Add repos, publishers, and `allow` entries before the first release, not after.

Common changes:

- **Add a repo.** Add it under `repos` (`OpenCHAMI/fru-tracker: {}` for no extra settings), and
  check its [publishing prerequisites](../publishing/README.md) first.
- **Add a publisher.** Look up their user ID (`gh api users/<username> -q .id`) and add it under
  `publishers`, with `repos` to limit them to their projects.
- **Revoke a repo key.** Add its fingerprint to the repo's `deny`, optionally with `since`. New
  releases signed with it are rejected, and prune removes what it admitted
  ([pruning](../design/pruning.md)); a `Denied repo key` issue lists what was removed.
- **Keep a version.** Add it to the repo's `retain` (one version) or `keep_releases` (a whole
  `major.minor` line); [retention](../design/retention.md) never removes those.

Removing a repo's entry stops polling it. Its packages stay published under the default retention,
and its package names stay its own.

[Back to Operations](README.md)
