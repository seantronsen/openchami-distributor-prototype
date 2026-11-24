<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# distributor (working name)

OpenCHAMI services release their own rpm and deb packages, each signed with its repo's key. Users
shouldn't need to trust each repo separately, or hunt across repos for packages. The distributor
gathers every service's signed releases into one dnf repository and one apt suite, signed with a
single OpenCHAMI archive key.

It polls the configured service repos, verifies each new release's signatures and contents,
publishes what passes, and keeps a public record of every decision. It runs entirely as GitHub
Actions workflows in this repo.

Goals:

- **One trust anchor for users.** Install `openchami-keyring` once; every package verifies against
  the archive key.
- **Nothing unverified gets published.** A release must carry a valid signature chain back to the
  OpenCHAMI root key, come from an allowed publisher, and follow the package rules.
- **No manual steps per release.** Tagging a release in a service repo is enough; the next poll
  picks it up.
- **An auditable record.** `state/state.json` records what was published or rejected, when, and why.

## Documentation

The [documentation index](docs/README.md) explains how the sections fit together.

| If you want to | Start at |
|---|---|
| install OpenCHAMI packages from the repositories | [Using the repositories](docs/using/README.md) |
| get your service's releases distributed | [Publishing a service](docs/publishing/README.md) |
| run or maintain this repo (config, keys, issues) | [Operations](docs/operations/README.md) |
| understand how it works and why | [Design](docs/design/README.md) |
| change the code or run the tests | [Development](docs/development/README.md) |
