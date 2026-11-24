<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Setup

## Requirements

- podman (rootless) or docker; the clients suite needs rootless podman.
  Everything else runs in a transient `debian:13` tools container, and nothing
  is installed on the host.
- `yq` (either implementation) and `jq` on the host, for the configuration.
- `gh`, logged in with the `repo` scope (`gh auth refresh -s repo`). The token
  reaches the container on stdin only, never a file, its environment, or a
  command line.
- An SSH agent (`SSH_AUTH_SOCK`) holding a key GitHub accepts; git pushes
  through it.
- The code under test: by default this checkout's HEAD commit, which must have
  no uncommitted changes to tracked files (git worktrees work).

## Repos and bucket

```bash
tests/integration/init.sh        # three throwaway repos
tests/integration/init-aws.sh    # the test bucket and its IAM user
tests/integration/destroy.sh     # delete the repos, when done
tests/integration/destroy-aws.sh # delete the bucket and user
```

| Created                                       | Role                                                                                     |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `it-<random>-distributor`                     | the distributor under test                                                               |
| `it-<random>-testbed`                         | `service`: real release builds (github-actions-testbed)                                  |
| `it-<random>-testbed-tools`                   | `fixture`: crafted releases only; its name extends `service`'s, for the longer-name rule |
| bucket and IAM user `distributor-it-<random>` | the publish target; the user may only read, write, and delete in it                      |

They're recorded under `~/.local/state/distributor-it/` (`repos.yaml`,
`s3.json`, `s3-credentials.json`), outside the source tree, and reused by every
run. The destroy scripts delete exactly what's recorded, after you confirm. The
repos are overwritten completely on every run: use repos made for this only.

## Configuration

`tests/integration/config.defaults.yaml` documents every setting and its
default; don't edit it. Put overrides in `~/.config/distributor-it/config.yaml`,
only the keys you change. For example, to test a local checkout of the service:

```yaml
repos:
  service:
    checkout:
      path: ~/projects/openchami/github-actions-testbed
```

A checkout is a local `path` (its HEAD commit) or a GitHub `repo` with an
optional `ref`. The state files' values are merged in; setting one of them in
your config too is an error, naming both files.

## Running

```bash
tests/integration/pipeline/run.sh                  # every pipeline test
tests/integration/pipeline/run.sh retention noop   # these tests
tests/integration/clients/run.sh                   # after reviewing clients/
```

Results (TAP) go to stdout and `<output_dir>/<run id>/report.tap`; logs go to
stderr.

> [!WARNING]
>
> **Run one test at a time and one suite at a time.** Don't use bats `--jobs`,
> run both suites at once, or create extra repo sets to go faster. The tests
> create and delete releases, tags, issues, and workflow runs in bursts, and
> GitHub's abuse detection can flag or suspend your account when that's
> multiplied across parallel runs; its content-creation limits hit sooner too.
> The suites also share one set of repos and one bucket, so parallel runs would
> break each other.

[Back to Integration tests](README.md)
