<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# What a release provides

The distributor reads only the GitHub release, never the repo's code or workflow
runs (apart from who pushed the tag). A release is a candidate once it's
published (not a draft) and not marked as a GitHub prerelease.

It must carry these assets, under exactly these names:

| Asset                | What it is                                                                                            |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| `checksums.txt`      | SHA-256 of every release file ([GoReleaser](https://goreleaser.com/customization/checksum/)'s format) |
| `checksums.txt.asc`  | detached signature over `checksums.txt`, by the release key                                           |
| `pubkey-signing.asc` | the release key, certified by the repo key                                                            |
| `pubkey-repo.asc`    | the repo key, certified by the root key                                                               |

plus the `.rpm` and `.deb` files listed in `checksums.txt`. Anything else
attached is ignored, including `pubkey-org.asc`: the root key is pinned in the
distributor, never read from a release.

github-actions' release workflow and its signing step produce exactly this; see
its
[signing docs](https://github.com/OpenCHAMI/github-actions/blob/main/docs/signing.md).
The release key is a fresh short-lived key per release, so a leaked release key
can't sign anything later.

Versions:

- Each package's version must be `major.minor.patch`. GoReleaser derives it from
  the tag.
- A version with a prerelease part (`1.2.0~rc1`, `1.2.0-rc1`) makes the whole
  release `skipped`, quietly: prereleases aren't published.
- A version is published once. Re-tagging the same version with new files is
  rejected; ship by bumping the patch version number (e.g., `1.2.4` -> `1.2.5`) instead.

Only `x86_64`, `aarch64`, and `noarch` rpms and `amd64`, `arm64`, and `all` debs
are published (the config's `architectures`). Packages for other architectures
are left out without rejecting the release.

[Back to Publishing a service](README.md)
