<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Publishing

Publish adds the run's admitted packages to the target, one job per format (`scripts/publish.sh`).
It only adds: it knows nothing about retention or denied keys.

1. Sign each new rpm with the archive key (debs carry no signature).
2. Upload the packages, in parallel; filenames are unique per version, so uploads can't collide.
3. Update the metadata without downloading old packages: build metadata for the new packages
   only and merge it with what's on the target (rpm: [createrepo_c](https://github.com/rpm-software-management/createrepo_c)
   and `mergerepo_c`; apt: `apt-ftparchive`, merging `Packages` stanzas). Sign it: `repomd.xml.asc`
   for rpm, `InRelease` and `Release.gpg` for apt.
4. Publish `keys/`.
5. Hand record a delta marking each package published, with the key that signed each rpm.

Why it's safe to retry:

- **Packages before metadata.** Metadata never points at a file that isn't there yet.
- **Idempotent merge.** Before merging, entries with the same filename as an incoming package are
  dropped, so a retry replaces them instead of listing them twice.
- **Signatures last.** For rpm, the signature is uploaded before `repomd.xml`, so between the two
  writes dnf sees a mismatch and fails closed instead of reading a list that points at missing
  files. The worst case on apt is `Packages` updated but `Release` not, which breaks `apt update`
  until the next run.

[Back to Design](README.md)
