<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Target layout

The bucket holds one [rpm repository](https://rpm-software-management.github.io/createrepo_c/)
and one [Debian archive](https://wiki.debian.org/DebianRepository/Format) with a single suite,
`stable`, and component, `main`:

```text
rpm/packages/<file>.rpm
rpm/repodata/repomd.xml, repomd.xml.asc, …
deb/pool/main/<first letter>/<name>/<file>.deb
deb/dists/stable/Release, InRelease, Release.gpg
deb/dists/stable/main/binary-<arch>/Packages, Packages.gz
keys/archive.asc                (and the other files in keys/ during a rotation)
```

- One repository per format, not per distribution release: the services ship static binaries.
- `Packages` exists for each deb architecture but `all`; architecture-independent packages are
  listed in every one.
- Metadata uses relative paths, so the bucket works behind any domain.
- Packages are immutable (cached for a year); metadata and keys change, so they're cached for
  `metadata_max_age` ([deployment](../operations/deployment.md)).

[Back to Design](README.md)
