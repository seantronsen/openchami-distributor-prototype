<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# State

`state/state.json` is the distributor's memory and its public record. Keys are releases,
`<owner>/<repo>@<tag>` (or `openchami-keyring@<version>`); `schemas/state.schema.json` defines the
rest.

```json
{
  "OpenCHAMI/smd@v2.20.4": {
    "status": "published", "at": "2026-10-20T12:00:00Z",
    "run": "https://github.com/…/actions/runs/123",
    "repo_key": "0BF1EED595FB2201ECF637CA79296C4986AE4087",
    "packages": [
      {"format": "rpm", "name": "smd", "version": "2.20.4", "arch": "x86_64",
       "filename": "smd-2.20.4-1.x86_64.rpm", "sha256": "…", "status": "published",
       "signed_with": "…"}
    ]
  }
}
```

- **One writer.** Only record commits state, applying each run's results as a delta onto the
  latest commit, fetched fresh, and retrying the push if another lands first. Parallel jobs never
  write it ([concurrency](concurrency.md)).
- **Validated before every commit,** against the schema, so `main` never holds a malformed state.
- **The source of truth.** It decides what's new ([discovery](discovery.md)), who owns a package
  name ([package names](../publishing/package-names.md)), and what's published. The target is
  only listed by prune, to remove files state doesn't know.
- **A public audit trail.** Every package the archive key signed, with its hash, the repo key
  that admitted it, and the run, plus every rejection and its reasons, is in public git history.
  Anyone can check what the archive key has vouched for, much like a CA's record of the
  certificates it issued. A package on the target that state doesn't list wasn't published here.

Recovery: a run that dies mid-way records nothing, and the next poll redoes the work
idempotently. As a last resort, core maintainers can delete or revert state: the next polls
rediscover every release, republish idempotently, and prune applies retention. It's not the normal
fix for anything.

[Back to Design](README.md)
