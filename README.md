# distributor (working name)

Prototype of the central repo from OpenCHAMI/github-actions#43: it polls OpenCHAMI service repos
for signed releases, verifies them, and publishes their rpm and deb packages to dnf and apt
repositories signed with the OpenCHAMI archive key.

## Layout

- `scripts/`: `discover.sh`, `admit.sh`, `publish.sh`, `prune.sh`, `record.sh`; shared `lib.sh`,
  `lib-repo.sh`, `lib.jq`.
- `.github/workflows/`: `poll.yml` resolves the commit to read, then calls one reusable workflow
  per stage (`_discover.yml`, `_admit.yml`, `_publish.yml`, `_record.yml`, `_prune.yml`). Jobs
  run on `ubuntu-latest`; publish and prune install the few tools it lacks.
- `config/repos.yaml`: the service repos to poll, with their `allow`, `deny`, `retain`, and
  `keep-releases`.
- `state/state.json`: every release and package processed, and what happened to it.

Parked on branches: archive key rotation and the keyring package on
`seantronsen/wip/rekey-keyring`, the keepalive workflow on `seantronsen/wip/keepalive`, and the
tests on `seantronsen/wip/tests`.

## Running

`poll` runs on a schedule (every 10 minutes, though GitHub currently fires it only a few times a
day), on pushes that change `config/repos.yaml`, and on `workflow_dispatch`. It needs the
`MASTER_PUBLIC_ASC` and `MASTER_FPR` secrets (root public key and fingerprint).
`ARCHIVE_GPG_KEY` (and `ARCHIVE_GPG_PASSPHRASE`) is optional: without it, every publish and prune
job signs with its own throwaway key, so the result is for inspection only.

The publish target is transient: each job's copy is uploaded as a
`target-<publish|prune>-<format>` artifact. The variables are listed at the top of
`scripts/lib.sh`.
