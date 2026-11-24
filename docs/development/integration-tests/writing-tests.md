<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Writing tests

A case is a bats file under `<suite>/cases/`; nothing registers it anywhere else. It sources
`lib/harness.sh`, which loads every lib.

```bash
setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/harness.sh"
  lifecycle__reset
}

teardown() {
  lifecycle__check_state
}

@test "a release with a version that isn't major.minor.patch is rejected" {
  ...
}
```

The lifecycle (`lib/suite/lifecycle.sh`):

- **Once per suite:** check the repos are the suite's own (public, not forks, empty or carrying
  the marker file), make a throwaway key chain and set the secrets, seed the repos.
- **Before every test:** `lifecycle__reset` puts the repos back to the baseline.
- **After every test:** `lifecycle__check_state` validates the state the test left.
- **Once at the end:** wipe the repos and delete their secrets, unless `keep_repos` is set.

Rules that keep cases reliable:

- Wait on GitHub with `wait__until` or `wait__check`, never a fixed sleep: its APIs lag.
- Settings come only from `settings__get` in the container (`config__get` on the host): no
  defaults in code, no settings in the environment. A new setting goes in
  `config.defaults.yaml`.
- Reusable routines go in the libs: `lib/` for the generic ones, `lib/suite/` for the suite's,
  `pipeline/lib/` and `clients/lib/` for one suite's.
- The [conventions](../conventions.md) apply.

[Back to Integration tests](README.md)
