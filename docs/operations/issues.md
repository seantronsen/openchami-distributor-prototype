<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Issues

The distributor reports through issues in this repo, so maintainers watching it hear about them
through GitHub's notifications. Each kind has its own label.

| Issue | Label | Opened when | Closed | What to do |
|---|---|---|---|---|
| `Rejected release: <repo>@<tag>` | `rejected-release` | a release fails admission | by a maintainer | tell the service's maintainers; the fix is a new patch release ([rejections](../publishing/rejections.md)) |
| `Denied repo key: <repo> <fingerprint> (<date>)` | `denied-repo-key` | prune removes packages admitted with a denied key | by a maintainer | check the list; the service repo republishes with its new key |
| `Prune failing` | `prune-failing` | prune fails in two poll runs in a row | automatically, when prune succeeds | read the failing run's log; a single failure only warns, since the next run retries it |
| `Archive key expiring` | `archive-key` | the archive key expires within `archive_key.warn_days`; polls fail meanwhile | automatically, once it doesn't | [rotate the key](archive-key/rotation.md) |
| `Archive key switch due` | `archive-key` | `keys/archive-next.asc` has been committed for `warn_days` | automatically, when it's removed by the switch | do the switch ([rotation](archive-key/rotation.md), step 3) |

An issue isn't duplicated while one with the same title and label is open. A denied-key issue is
the exception: each wave of removals for a key gets its own.

[Back to Operations](README.md)
