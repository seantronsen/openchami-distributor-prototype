<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Pipeline suite

`tests/integration/pipeline/cases/`: the distributor's behavior, one concern per case. Every case
starts from the same baseline (no releases, tags, or issues; the distributor on its seed commit
with the default test config and empty state), so cases don't depend on each other, and ends by
checking that the state it left matches the schema.

| Area | Cases |
|---|---|
| admission | `admit-new-release`, `bad-signature`, `missing-sidecars`, `prerelease`, `retag`, `package-rules`, `publisher-not-listed`, `publisher-repo-scope`, `publisher-no-push-run`, `real-build` |
| config and polling | `config-invalid`, `noop`, `release-cap`, `cancel`, `overlapping-polls` |
| pruning | `retention`, `deny-key`, `deny-since`, `prune-failing` |
| bucket (read back over HTTPS) | `s3-publish`, `s3-prune`, `s3-orphans`, `s3-rekey` |
| archive key and keyring | `archive-key-required`, `check-keys-expiring`, `check-keys-mismatch`, `check-keys-switch-due`, `keyring`, `keyring-retention`, `keyring-rotation` |

Releases are crafted (tiny real rpms and debs, signed through the run's own key chain the way
github-actions signs) on the `fixture` repo, which has no workflows. `real-build` is the one case
that waits for a real release build on the `service` repo.

[Back to Integration tests](README.md)
