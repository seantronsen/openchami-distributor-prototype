<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Conventions

These hold for `scripts/` and `tests/integration/` alike. [shellcheck](https://www.shellcheck.net/)
must be clean, lines are at most 100 characters, and every file carries an
[SPDX](https://reuse.software/) header.

## Files

- A file starts with a one-line statement of its purpose. If it can't be brief, the file mixes
  concerns and gets split.
- A lib file sources its own dependencies after an include guard, and dependencies flow one way:

  ```bash
  [[ -n "${_LIB_STATE_SH:-}" ]] && return 0
  _LIB_STATE_SH=1
  ```

- A script is laid out as: sources, UPPERCASE constants, functions, then `main`, called last after
  the usage check. `main` reads as the script's sequence, so a reader gets the whole flow from
  it alone.
- No lowercase globals. Functions take what they use as arguments into `local`s, even when it's
  redundant, because arguments are easier to trace than globals.
- Each script lists the environment it needs in its header and checks it first
  (`base__env_require`), so a missing variable is named instead of failing somewhere deep.

## Names

- Lib functions are `<lib>__<object>[_<action>]`: the object comes first so that related
  functions sort together (`github__issue_create`, `github__issue_close`), and the action comes
  last. Where the lib's name already says it, the object is dropped (`config__get`).
- Predicates start with `is_` (a state) or `has_` (existence, or something holding):
  `package__is_arch_supported`.
- jq definitions follow the same rule, with the module as part of the name where it reads well:
  `version::is_semver`, `state::published_packages`.
- Script-local functions are named for what they do, including whether they can end the run:
  `reject_if_repo_key_denied`, `skip_if_prerelease`.
- No clipped nouns or abbreviations in names (`release_assets`, not `assets`).

## Bash

- Variables are `${name}` and always double-quoted, unless the expansion has to split into
  several arguments (`for x in $(...)`).
- Every function has a doc comment between two banners of 80 `#`, with `Globals:`,
  `Arguments:`, `Inputs:`, `Outputs:`, and `Returns:` as they apply.
- Checks report every problem before failing. `log__fatal` exits; use it where the script can't
  go on.

[Back to Development](README.md)
