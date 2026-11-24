<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Concurrency

Every workflow that writes the target or state (`poll`, `keyring`, `rekey`) shares one
[concurrency group](https://docs.github.com/en/actions/using-jobs/using-concurrency), `poll`, with
`cancel-in-progress: false`:

- A run is never cancelled mid-write.
- Two runs never rebuild the same metadata at once.
- GitHub keeps at most one waiting run, so a burst of triggers collapses into one more poll.

Inside a run, jobs fan out and gather through artifacts (see the [pipeline](README.md)), so only
record commits state, and only one job per format writes that format's metadata.

A queued run starts on the commit it was queued on, which predates the state its predecessor
just committed. Reading that old state would rediscover what the previous run recorded. So
poll's first job resolves the latest `main` commit, and discover and admit both read state and
config from it. Prune checks out the latest `main` itself, since it must also see this run's own
record.

Record retries its push (fetch, reapply the delta, push) because a workflow outside the group
could still commit in between.

[Back to Design](README.md)
