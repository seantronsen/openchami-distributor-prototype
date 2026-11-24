<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Retention

Which published versions stay, applied by [prune](pruning.md) per package name and architecture:

| Versions | Kept |
|---|---|
| current major (N) and N−1 | the latest patch of each minor |
| N−2 and older | none |
| in the repo's `retain` | always |
| a `major.minor` in the repo's `keep_releases` | its latest patch, always |

N is the highest major published for that package, not a global version. With `smd` at
`3.1.2`, `3.1.1`, `3.0.4`, `2.5.0`, and `1.9.9`, prune keeps `3.1.2`, `3.0.4`, and `2.5.0`.

Versions must be `major.minor.patch` for this to work, which is why [admission](admission.md)
requires it. `retain` and `keep_releases` are kept by hand: nothing here can see which versions
live deployments or lockfiles depend on.

The keyring package follows the same policy, so only its latest version stays.

[Back to Design](README.md)
