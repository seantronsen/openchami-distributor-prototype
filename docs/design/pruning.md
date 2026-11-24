<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Pruning

Prune removes what shouldn't be published any more, one job per format (`scripts/prune.sh`). It
only removes, runs on every poll, and works from state alone, so a rerun is always safe.

It removes three kinds of package:

| Kind | Rule | Recorded as |
|---|---|---|
| Denied | admitted with a repo key in its repo's `deny` (all of them, or those admitted at or after `since`) | `pruned`, `denied repo key <fingerprint>` |
| Retention | dropped by the [retention](retention.md) policy, over what's left | `pruned`, `retention` |
| Orphans | files on the target that state doesn't list as published, left by a run that died mid-publish | nothing (they were never in state) |

Then it rewrites the metadata without them and only then deletes the files, so metadata never
points at a missing file.

`since` limits only what prune removes. Admission rejects every new release signed with a denied
key, whatever `since` says ([admission](admission.md)).

A failing prune is retried by the next poll; two failures in a row open a `Prune failing` issue
([issues](../operations/issues.md)).

Accepted costs of keeping publish and prune separate: metadata is rewritten and re-signed twice
when something is pruned, a superseded patch stays listed until the same run's prune, and an older
patch that arrives late is published and then pruned.

[Back to Design](README.md)
