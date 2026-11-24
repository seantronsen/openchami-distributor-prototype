<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Compromise

The [rotation](rotation.md) switch and `rekey`, done immediately with a freshly generated key and
no grace period. In addition:

1. Revoke the old key by hand, and commit its revoked public key as
   `keys/revoked-<fingerprint>.asc`. The next keyring carries the revocation.
2. Open an issue and announce the compromise.

Clients that only trust the compromised key can't verify a keyring signed with the new one. They
re-import the new key from `keys/archive.asc` over HTTPS, as in the initial setup
([using](../../using/README.md)), and can check its root certification first.

A compromised **repo key** isn't an archive key problem: deny it in the config
([config](../config.md)). A compromised **root key** means re-certifying every repo key and
replacing the `MASTER_PUBLIC_ASC` and `MASTER_FPR` org secrets; published packages stay valid,
since they're signed with the archive key, and only future admission changes.

[Back to Archive key](README.md)
