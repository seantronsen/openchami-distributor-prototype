# Integration tests

`tests/integration/` tests the distributor end to end with bats-core, in two suites:

- `ci/`: the CI integration tests. Each test makes releases on throwaway service repos,
  dispatches polls of a throwaway distributor on real GitHub, and checks its state, issues, and
  published repositories. One transient tools container, with no access to the container
  engine.
- `distro/`: the distro tests. Each distro's own package manager (dnf on Fedora, apt on Debian)
  installs from the distributor's published repositories, from the files and over HTTP from a
  temporary local S3 gateway. A test file first runs the CI tests that produce what it installs.

Unit tests (`tests/unit`, later) are the quick sanity check; these are the real insurance.

The throwaway repos are overwritten completely on every run. Use repos made for this only.

## Security: the distro tests start containers as you

**Review `tests/integration/distro/` (its cases and lib) before running the distro tests.**

The distro tests' tools container gets the API socket of your rootless podman, so code in it
can start containers as you: with your user's privileges, your files that it mounts, and the
network access your containers have. That's how it starts the per-distro containers and the S3
gateway next to itself. Rootless podman is required; the suite refuses docker, whose socket is
root's. This is a stopgap while alternatives are considered.

The CI tests don't get the socket: their container can reach GitHub with your token and push
over your SSH agent, nothing on your machine beyond its own mounts. They're safe to run
without that level of review.

## Requirements

- podman (rootless) or docker; the distro tests need rootless podman. Everything runs in a
  transient `debian:13` tools container (bats, gh, git, gpg, rpm and deb tools are installed
  there). Nothing is installed on the host.
- `yq` (either implementation) and `jq` on the host, for the configuration.
- `gh`, logged in, with the `repo` scope (`gh auth refresh -s repo`). The token reaches the
  container on stdin only: never a file, the container's environment, or a command line.
- An SSH agent (`SSH_AUTH_SOCK`) holding a key GitHub accepts (`ssh-add -l` lists it): git
  pushes over SSH through it. A key ssh finds on disk isn't enough; the container only sees the
  agent.
- The code under test: by default this checkout's HEAD commit (no uncommitted changes to tracked
  files; git worktrees work) and the testbed's latest release, fetched from GitHub. Either can
  be a local checkout or a GitHub repo at any ref (Configuration).

## Repos

```bash
tests/integration/init.sh      # create the three repos
tests/integration/destroy.sh   # delete them, when done
```

`init.sh` creates `it-<random>-distributor`, `it-<random>-testbed`, and
`it-<random>-testbed-tools` (public, empty) under your account and records them in its state
file, `~/.local/state/distributor-it/repos.yaml` (`IT_STATE` overrides), outside the source
tree. Every run reuses them until you destroy them. It refuses when the state file exists (to
keep those repos and make new ones, move the file aside) or when your config sets repos.

`destroy.sh` deletes exactly the repos in the state file, after checking each is yours and
named like init's, and only after you type `Y` having seen their names. Repos already gone are
reported and skipped. It also deletes the testbed's images in your GHCR namespace, then the
state file. It needs the `delete_repo` scope, and `delete:packages` for the images
(`gh auth refresh -s delete_repo,delete:packages`). It never touches repos set in your config.

Repos made by hand work too: set `repos` in your config, which then wins over the state file.
package-rules' longer-repo-name check runs only when the second service repo's name starts with
the testbed's name plus `-`.

## Configuration

`tests/integration/config.defaults.yaml` holds every setting with its default and what it
means: the code under test (`checkouts`), the repos (when not made by init.sh), the images, the
engine, the output directory, timeouts, `keep` (skip the end-of-run cleanup of the repos, to
inspect what a run left), and the S3 gateway's. Don't edit it.

Your settings go in `~/.config/distributor-it/config.yaml` (`$XDG_CONFIG_HOME` is respected;
`IT_CONFIG` picks another file), with only the keys you change; each overrides its default.
Nothing writes to it, and it's optional. For example, to test a local testbed checkout:

```yaml
checkouts:
  testbed:
    path: ~/projects/openchami/github-actions-testbed
```

A checkout is either `path` (a local checkout's HEAD commit; relative paths start at this repo's
root) or `repo` (owner/name on GitHub) with an optional `ref` (commit, tag, or branch; without
it, the latest release). Setting one replaces the whole default entry.

Before anything runs, the run scripts check the host, the settings they read, the repos, and the
code under test, and report every problem at once.
Then they hand the container the resolved settings (defaults applied, repos resolved, the run's
own directories) as one read-only file, also saved as `<output_dir>/<run id>/settings.json`. The
tests read only that file: no defaults of their own, no settings in the environment.

## Running

```bash
tests/integration/ci/run.sh                    # every CI test
tests/integration/ci/run.sh retention noop     # these tests (ci/cases/<name>.bats)
tests/integration/ci/run.sh --filter deny      # bats options pass through
tests/integration/distro/run.sh                # every distro test (review distro/ first)
```

Logs go to stderr; the results (TAP) go to stdout and to `<output_dir>/<run id>/report.tap`.
Files tests export go to `<output_dir>/<run id>/artifacts/<test>/` and stay after the run. Tee
stderr yourself to keep the log. The exit status is bats': 0 when every test passed.

Runs are serial on purpose: one test at a time, one run at a time, one set of repos. Don't run
tests in parallel (bats `--jobs`), run two suites at once, or create extra repo sets to speed
things up. The tests create and delete releases, tags, issues, and workflow runs in bursts, and
GitHub's abuse detection can flag or suspend an account for that kind of automated activity
when it's multiplied; its secondary rate limits on content creation hit sooner too. Tests also
share the one set of repos, so parallel runs would break each other.

### CI tests

1. Once (setup_suite): checks the repos (guard, below), generates a throwaway key chain (root, a
   repo key per service repo certified by the root, an archive key), wipes the repos (releases,
   tags, issues, labels, workflow runs), sets their secrets, and force-pushes the checkouts'
   HEAD commits with the suite's changes: the distributor gets the default test config, empty
   state, and no cron schedule (tests dispatch every poll); the testbed pushes its images to
   your GHCR namespace.
2. Before every test: resets the baseline, so no test depends on another: no releases, tags,
   issues, or labels; the distributor back on its seed commit (default config, empty state);
   no poll running.
3. Once at the end (teardown_suite): wipes the repos and deletes their secrets, unless `keep`.

Tests wait on GitHub by checking every `poll_interval` seconds up to `timeout` per wait, never by
sleeping a fixed time. Ctrl-C stops the running test and still runs the teardowns, which can
take a minute or more.

| Test | What it checks |
|---|---|
| admit-new-release | a new release is admitted and its packages published |
| noop | a poll with nothing new skips admission and commits nothing |
| retention | a new patch release prunes the previous patch's packages |
| prerelease | a GitHub prerelease is ignored (no state entry, no issue) |
| missing-sidecars | a release without signature sidecars is rejected once, with one issue |
| retag | a retagged copy of an admitted release is rejected |
| bad-signature | a release signed by an uncertified key fails the trust chain |
| deny-key | denying a repo key prunes it, opens an issue, rejects its new releases |
| deny-since | denying a key from a date prunes only what it admitted since |
| cancel | a poll cancelled mid-run commits nothing; the next one admits normally |
| prune-failing | a failing prune keeps an issue open until it recovers |
| package-rules | package name, version, and ownership rules across two repos |
| release-cap | one poll processes at most MAX_RELEASES releases (lowered to 3) |
| overlapping-polls | two polls dispatched together admit a release once |
| real-build | a real testbed release (GoReleaser, signing) is admitted and published; exports the published repositories to `artifacts/real-build` |

Every test but real-build uses crafted releases: tiny real rpm and deb packages, signed through
the run's key chain the way gpg-sign-artifacts signs. They're on the second service repo (no
workflows there, so tags trigger nothing), or on the testbed under tags that don't start with
`v` (its release workflow builds `v*` tags). real-build is the one test that waits for a real
release build.

### Distro tests

Each test file runs in phases: `setup_file` runs its stage 1 (the CI tests that produce what it
installs, with their own setup and teardown, on the throwaway repos), then each test is one
distro installing natively in a clean container, and `teardown_file` removes what `setup_file`
made.

| Test file | What it checks |
|---|---|
| ci-artifacts | real-build's published repositories install with dnf (Fedora) and apt (Debian), signatures checked: from the files, and over HTTP from a temporary local S3 gateway |

The gateway is versitygw: one public-read bucket (objects only; listing stays denied) with its
files in the run directory, on a private podman network the distro containers join, deleted
when the test file ends. It checks the published layout over HTTP the way S3 will serve it; the
distributor's own upload to S3 needs a reachable test bucket and isn't covered. Until the
keyring package exists, the archive key comes from the published files. Its credentials are
settings (`gateway.access_key`, `gateway.secret_key`): nothing outside its network reaches it,
and it serves public test data.

With `gateway.keep: true` it stays running after its test file, for inspection: published on
`127.0.0.1:<gateway.port>` only, with its files in `<output_dir>/<run id>/gateway/`. The end of
the test file logs its URL and credentials, and the commands that remove every kept gateway
(their container and network carry the label `distributor-it=gateway`):

```bash
podman rm -f --filter label=distributor-it=gateway
podman network prune -f --filter label=distributor-it=gateway
```

Nothing removes kept gateways automatically; while one holds the port, the next distro run's
gateway can't start, and says so.

## Guard

Before changing anything, setup and teardown refuse unless every repo is public, not a fork, and
either empty or carrying the `.distributor-it` marker file the suite pushes.

## Notes

- Not covered: the scheduler (GitHub's cron is unreliable), the release publisher check (not
  implemented yet), and the distributor's upload to S3 (not implemented yet).
- The testbed's trivy job fails in a personal account (it reads org packages), and its reuse
  check flags the marker file; releases don't depend on either.
- With docker, files the containers write in the output directory may be owned by root.
