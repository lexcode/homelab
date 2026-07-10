# Plan 009: Gate database clients on readiness and restart backups

> **Executor instructions**: Add only native healthchecks and Compose
> dependencies. Do not start, stop, migrate, or inspect live databases.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- analytics/compose.yml analytics/README.md terminal/compose.yml terminal/README.md`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: bug
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Your Spotify and Atuin depend only on database container creation, not database
readiness. The Atuin backup sidecar also has no restart policy, so a cold-start
connection failure can silently remove scheduled backups until manual action.

## Current state

- `analytics/compose.yml:25` uses short `depends_on` for MongoDB; Mongo has no
  healthcheck.
- `terminal/compose.yml:16` and line 49 use short `depends_on` for Postgres.
- `terminal/compose.yml:35` backup service has no `restart` entry.
- Credentials are already passed through environment variables; never print
  their resolved values.

## Target design

Use image-native checks: `mongosh`/`mongo` availability must be confirmed for
the pinned `mongo:4.4` image before selecting the command, and Postgres should
use `pg_isready` with container environment variables. Convert dependents to
long-form `condition: service_healthy`. Add `restart: unless-stopped` to the
backup service. Do not change database versions or data mounts.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Analytics config | `cd analytics && docker compose --env-file .env.example config --quiet` | Exit 0 |
| Terminal config | `cd terminal && docker compose --env-file .env.example config --quiet` | Exit 0 |
| Structural assertions | Render JSON and use `jq` to assert DB healthchecks, healthy dependency conditions, and backup restart policy | All assertions true |

## Scope

**In scope**: analytics/terminal Compose and READMEs, plan status.

**Out of scope**: image upgrades, live cold-boot tests, database migrations,
backup restore design, credential encoding, data mounts, application changes.

## Steps

1. Confirm the health command exists in the documented image version without
   pulling/running it if local metadata/docs suffice. If uncertain, STOP rather
   than guessing Mongo shell syntax.
2. Add bounded healthchecks with start period, interval, timeout, and retries.
3. Convert application and backup dependencies to `service_healthy`.
4. Add backup restart policy.
5. Document readiness semantics and that health does not prove data integrity.
6. Validate structure through rendered JSON and run repository validation.

## Test plan

- Rendered MongoDB and Postgres services each contain a healthcheck.
- Rendered application dependencies use `service_healthy`.
- Rendered Atuin backup dependency uses `service_healthy` and its restart policy
  is `unless-stopped`.
- Analytics and terminal example configurations both render quietly.

## Done criteria

- [ ] Mongo and Postgres have valid native healthchecks.
- [ ] Applications and backup wait for healthy databases.
- [ ] Atuin backup restarts unless stopped.
- [ ] No image, mount, or credential changes occurred.
- [ ] Both stacks validate; Plan 009 is `DONE`.

## STOP conditions

- The Mongo 4.4 image health command cannot be verified confidently.
- Upstream clients intentionally implement stronger retry semantics that make
  a health gate harmful; report evidence.
- Testing requires touching live database state.

## Maintenance notes

Revisit health commands when database major versions change. Restore
verification remains a separate direction plan, not part of readiness.
