<!--
SPDX-FileCopyrightText: © 2026 OpenCHAMI a Series of LF Projects, LLC
SPDX-License-Identifier: MIT
-->

# Operations

For maintainers of this repo. Day to day, the distributor runs itself: `poll` admits, publishes,
records, and prunes on its own, and opens an issue whenever something needs a person. The work is
setting it up, changing the config, answering those issues, and rotating the archive key once a
year.

| Workflow | Runs | Does |
|---|---|---|
| `poll` | every 10 minutes, on pushes changing `config/distributor.yaml`, and by hand | checks the config and the archive key, then the whole [pipeline](../design/README.md) |
| `keyring` | on pushes changing `keys/`, and by hand | builds and publishes `openchami-keyring` from `keys/` |
| `rekey` | by hand | re-signs everything published with the current archive key ([rotation](archive-key/rotation.md)) |
| `validate` | on every pull request | checks the config and state against their schemas; make it a required check |

All of them except `validate` share one concurrency lock, so they never write the target or state
at the same time ([concurrency](../design/concurrency.md)).

> [!WARNING]
>
> **`poll`'s schedule is not every 10 minutes in practice.** It asks for every 10 minutes, but
> GitHub's [scheduler](https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#schedule)
> delays and drops scheduled runs under load; currently a scheduled poll runs about every 4
> hours. A new release can wait that long, unless someone dispatches `poll` by hand (config
> pushes still trigger it right away). Still to decide:
>
> - whether that delay is acceptable;
> - a re-arm workflow that forces polls on a tighter cadence;
> - an optional trigger from service repos: their release workflow dispatches `poll` once a
>   release is published. That's still safe, since it only starts a poll ahead of schedule; the
>   poll checks everything as usual.

- [Deployment](deployment.md): the bucket, CDN, domains, and the secrets the workflows need.
- [Config](config.md): what each setting in `config/distributor.yaml` does, and what a change
  triggers.
- [Issues](issues.md): every issue the distributor opens, and what to do about it.
- [Archive key](archive-key/README.md): the yearly rotation and the compromise procedure.

Security posture worth knowing:

- No workflow that holds a secret runs on `pull_request`; the only PR workflow, `validate`, is
  read-only.
- State commits come from the workflows' bot, which needs a bypass on the protected default
  branch. A bypass can't be limited to `state/state.json`.
- Only publish, prune, rekey, keyring, and the key check get the archive key.

[Back to the documentation index](../README.md)
