<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Using the repositories

The distributor publishes one dnf repository and one apt suite (`stable`). Every OpenCHAMI service
that ships rpm or deb packages is in both, for `x86_64`/`amd64`, `aarch64`/`arm64`, and
architecture-independent packages.

Everything is signed with the OpenCHAMI archive key: rpms and the rpm metadata (`repomd.xml`), and
the apt `Release` file (debs themselves carry no signature in apt; the signed `Release` covers
them). You trust that one key, not each service's own keys; the distributor verifies those
before it publishes anything (see the [trust model](../design/trust-model.md)).

Setup has the same two steps on either system:

1. Bootstrap: trust the archive key from `keys/archive.asc` on the repository, install
   `openchami-keyring`.
2. From then on, trust the key the keyring installed. Keyring updates bring the next archive key
   before it's switched to, so a normal upgrade keeps you verifying across a key rotation.

- [dnf](dnf.md): Fedora, RHEL, Rocky, and other rpm-based systems.
- [apt](apt.md): Debian, Ubuntu.

What stays published: the latest patch of each minor version for the current and previous major
version of each package, plus versions a maintainer pinned. See [retention](../design/retention.md).

`<base URL>` below is the repository's public address, set by the deployment
([operations](../operations/deployment.md)).

[Back to the documentation index](../README.md)
