<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# dnf

Bootstrap with the published key file, install the keyring, then point the repository at the key
the keyring installed.

```ini
# /etc/yum.repos.d/openchami.repo
[openchami]
name=OpenCHAMI
baseurl=<base URL>/rpm
gpgcheck=1
repo_gpgcheck=1
gpgkey=<base URL>/keys/archive.asc
skip_if_unavailable=0
```

```bash
dnf install openchami-keyring
sed -i 's|^gpgkey=.*|gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-openchami|' \
  /etc/yum.repos.d/openchami.repo
dnf makecache
```

- `gpgcheck` verifies each rpm's signature; `repo_gpgcheck` verifies the signed `repomd.xml`, so
  a tampered package list is refused too. Keep both on.
- `skip_if_unavailable=0`: without it, dnf skips a repository that fails verification and
  carries on, which hides the failure.
- The keyring installs `/etc/pki/rpm-gpg/RPM-GPG-KEY-openchami`, holding the current archive key
  and, during a rotation, the next one.

[Back to Using the repositories](README.md)
