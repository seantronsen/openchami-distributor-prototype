<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Archive key

The archive key signs everything the distributor publishes: every rpm, `repomd.xml`, and the apt
`Release` file. It's the one key users trust ([using](../../using/README.md)).

- Kept as the `ARCHIVE_GPG_KEY` secret (and `ARCHIVE_GPG_PASSPHRASE`). Workflows load it into a
  private GnuPG home that's shredded when the script exits.
- Its own primary key, certified by the offline root key, the same way the root certifies repo
  keys. dnf and apt ignore certifications, but the certification lets anyone check that a key is
  OpenCHAMI's, which matters most when switching to a new key after a compromise. A subkey of the
  root would instead make everything that trusts the root trust archive signatures too, and
  rotating it would mean editing the root key.
- Its public half is committed as `keys/archive.asc` and published at the same path.

`keys/` is the source of truth for the published keys and the keyring:

| File | When it exists |
|---|---|
| `archive.asc` | always: the current key |
| `archive-next.asc` | during a rotation, from step 1 until the switch |
| `archive-previous.asc` | during a rotation, from the switch until `rekey` finishes |
| `revoked-<fingerprint>.asc` | after a compromise: the revoked key |

Any change to `keys/` runs the `keyring` workflow, which releases `openchami-keyring` carrying
every key in `keys/`. Every poll checks that `ARCHIVE_GPG_KEY` is `keys/archive.asc` (it fails the
run if not, e.g. midway through a switch) and that it doesn't expire within
`archive_key.warn_days` ([issues](../issues.md)).

Packages keep the signature of the key that was current when they were published, so every key
change has to reach everything still published. State records which key signed each rpm
(`signed_with`), which is what lets `rekey` re-sign only what's left and resume after a failure.

- [Rotation](rotation.md): the planned yearly switch, with a grace period for clients.
- [Compromise](compromise.md): the same switch, immediately, plus revocation.

[Back to Operations](../README.md)
