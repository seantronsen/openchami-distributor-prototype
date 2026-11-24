<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Development

The distributor is shell scripts run by GitHub Actions workflows, with the decisions that need
JSON in jq modules. Nothing runs outside CI; the integration tests run it on real GitHub.

```text
.github/workflows/   poll.yml wires one reusable workflow per stage (_discover, _admit, …);
                     keyring.yml, rekey.yml, validate.yml stand alone
scripts/             one script per job step: discover, admit, publish, record, prune, …
scripts/lib/         shared bash: config, state, github, target, keys, package, metadata, log
scripts/jq/          shared jq modules: state, version, repo, publishers, retention, …
config/              distributor.yaml, the live config
schemas/             JSON Schemas for the config and state, and the check-jsonschema pin
state/               state.json, written only by record
keys/                the published archive keys (see operations)
keyring/             the openchami-keyring package definition (nfpm)
tests/integration/   the integration suites
```

How the pieces divide the work:

- **Workflows** hold triggers, permissions, secrets, and the job graph; anything longer than a
  one-line glue step lives in a script, so it can be linted and read on its own.
- **Scripts** are one job step each. Their `main` reads as the step's sequence; each function is
  one chunk of it ([conventions](conventions.md)).
- **Libs** are shared by several scripts, one concern per file, and never hold a script's own
  decisions.
- **jq modules** hold the JSON decisions shared by scripts (what's published, retention, publisher
  rules). Single-use jq stays inline.

Every change to code or config must pass both integration suites before review
([integration tests](integration-tests/README.md)).

[Back to the documentation index](../README.md)
