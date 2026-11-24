<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Clients suite

`tests/integration/clients/cases/`: dnf (Fedora) and apt (Debian) installing from the test bucket
over its public HTTPS URL, each in a clean sibling container started through your podman socket.

`install.bats` publishes one crafted release and the keyring, then checks:

- a package installs with signatures checked against the archive key, and
- `openchami-keyring` installs, after which the repository verifies through the key it installed
  alone ([using the repositories](../../using/README.md) is the same procedure).

It runs the same lifecycle as the pipeline suite, on the same repos and bucket, so the two never
run at the same time.

[Back to Integration tests](README.md)
