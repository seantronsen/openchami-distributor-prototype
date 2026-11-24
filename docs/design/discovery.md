<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Discovery

Discovery finds the work for a poll (`scripts/discover.sh`). For each configured repo it lists the
GitHub releases and keeps those that are published, not GitHub prereleases, and not in state yet.

- **State is the only memory.** A release with any state entry (published, skipped, rejected) is
  never looked at again. Nothing else tracks progress, so deleting state reprocesses everything
  (see [state](state.md)).
- **Oldest first, capped.** The result is sorted by publish time and cut at `max_releases`
  (at most 256, GitHub's limit on a job matrix). The rest wait for the next polls, still oldest
  first, so a backlog drains in order.
- **An empty result still prunes.** With nothing new, admit and publish are skipped, but prune runs,
  so config changes (a new `deny`, a changed `retain`) take effect on every poll.

Every poll lists every release of every repo, so this cost grows with history.

[Back to Design](README.md)
