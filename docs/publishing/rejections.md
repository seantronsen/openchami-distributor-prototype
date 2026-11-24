<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Rejections

A rejected release gets one issue in this repo, titled `Rejected release: <owner>/<repo>@<tag>`
with the label `rejected-release`. It lists every reason and links the run. Maintainers watching
this repo get it through GitHub's notifications.

A rejected release is never processed again, so the fix is always a new patch release:

1. Fix the cause: in your release workflow, your packages, or, for config-side causes, by asking a
   maintainer of this repo to update `config/distributor.yaml` (a missing `allow` entry or
   publisher).
2. Tag the next patch version. The old tag stays rejected in the record.

Common reasons and their fix:

| Reason | Fix |
|---|---|
| `missing checksums.txt.asc` (or another sidecar) | release with the signing step ([release](release.md)) |
| `<login> (id …) may not publish <repo>` | have the publisher added, or tag from a listed account |
| `trust chain or checksums.txt signature didn't verify` | the repo key isn't certified by the root key for this repo, or the signature is wrong; see the run log |
| `repo key <fpr> is denied` | the key was revoked; sign with the repo's new key |
| `<file>: <name> is not <repo> or <repo>-* and not in allow` | rename the package, or have it added to `allow` ([package names](package-names.md)) |
| `<file>: <name> <version> <arch> was already admitted` | the version exists already; bump the patch |
| `<file>: version <v> isn't major.minor.patch` | fix the tag or the packaging version |

Why rejections are final, and every check in detail: [admission](../design/admission.md).

[Back to Publishing a service](README.md)
