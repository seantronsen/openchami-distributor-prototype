<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Package names

Every package name belongs to exactly one repo, so one repo can never replace another's packages.

| Name | Who may publish it |
|---|---|
| `<repo>`, `<repo>-*` (the repo's name, lowercased) | that repo |
| any name in the repo's `allow` | that repo |
| a name already published by a repo | only that repo, from then on |

Ties are resolved toward the more specific claim:

- A name in another repo's `allow` is that repo's.
- With both `smd` and `smd-tools` configured, `smd-tools-cli` belongs to `smd-tools` (the longer
  matching repo name), not `smd`.
- Ownership comes from state, so it survives removing a repo's config entry. Moving a name to
  another repo's `allow` doesn't move it if the first repo already published it.

The name is read from the package metadata (`rpm` `NAME`, deb `Package`), never the filename.
Names in `allow` follow the rpm and deb naming rules; letters may be uppercase.

[Back to Publishing a service](README.md)
