<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# apt

Bootstrap with the published key file, install the keyring, then sign the source with the key the
keyring installed.

```bash
curl -fsSL --create-dirs -o /etc/apt/keyrings/openchami-bootstrap.asc \
  <base URL>/keys/archive.asc
echo "deb [signed-by=/etc/apt/keyrings/openchami-bootstrap.asc] <base URL>/deb stable main" \
  > /etc/apt/sources.list.d/openchami.list
apt-get update
apt-get install openchami-keyring

echo "deb [signed-by=/usr/share/keyrings/openchami-keyring.asc] <base URL>/deb stable main" \
  > /etc/apt/sources.list.d/openchami.list
rm /etc/apt/keyrings/openchami-bootstrap.asc
apt-get update
```

- `signed-by` limits the archive key to this source, instead of trusting it for every repository
  on the system.
- The keyring installs `/usr/share/keyrings/openchami-keyring.asc`, holding the current archive key
  and, during a rotation, the next one.
- apt only warns when a `Release` signature fails to verify. To make that an error (as the
  integration tests do), use `apt-get update --error-on=any`.

[Back to Using the repositories](README.md)
