# Plan 008: Make iGotify explicitly opt-in

> **Executor instructions**: Follow the Compose-profile pattern from Plan 001.
> Do not change iGotify tokens or inspect the real environment.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- notifications/compose.yml notifications/README.md notifications/.env.example README.md systemd/notifications.service`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/003-require-gotify-admin-password.md`, `plans/005-add-repository-validation-gate.md`
- **Category**: bug
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Documentation describes iGotify as optional, but ordinary notifications
startup always creates it, publishes port 8681, and enables its API explorer.
Gotify-only users should run only Gotify and changedetection unless they
explicitly enable the iOS assistant.

## Current state

- `notifications/compose.yml:38` defines `igotify` without a profile.
- It publishes port 8681 and enables Scalar UI at lines 50 and 59.
- `notifications/README.md:3` calls it optional; quick start at line 29 uses
  bare `docker compose up -d`.
- `systemd/notifications.service:8` uses bare Compose and should remain the
  default Gotify/changedetection mode.

## Target design

Add service profile `igotify`. Bare startup selects `gotify` and
`changedetection`; `docker compose --profile igotify up -d` selects all three.
Keep dependencies, healthchecks, ports, and environment unchanged.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Default services | `cd notifications && GOTIFY_DEFAULTUSER_PASS=test-only docker compose --env-file .env.example config --services` | `gotify`, `changedetection`; no `igotify` |
| Opt-in services | Same command with `--profile igotify` | All three services |
| Config validation | Run `config --quiet` for both modes | Exit 0 |

## Scope

**In scope**: notifications Compose/example/README, root README, plan status.

**Out of scope**: `systemd/notifications.service`, tokens, Scalar defaults,
port binding policy, Gotify password mechanics beyond Plan 003, or containers.

## Steps

1. Add exactly one `igotify` profile to the assistant service.
2. Update comments and quick start to distinguish default and iOS modes.
3. Document that the existing systemd unit excludes iGotify and that boot-time
   opt-in requires a separately reviewed override.
4. Assert exact service lists in both modes and run repository validation.

## Test plan

- Default service selection contains Gotify and changedetection only.
- Profiled service selection contains all three services.
- Both default and profiled configurations pass quiet rendering with a
  non-secret test Gotify password.
- Documentation searches find both the default and opt-in commands.

## Done criteria

- [x] Bare startup excludes iGotify.
- [x] Profile startup includes all three services.
- [x] Docs give exact commands and accurate systemd semantics.
- [x] No token or runtime state changed; Plan 008 is `DONE`.

## STOP conditions

- Existing operational requirements require systemd to start iGotify by default.
- The installed Compose version rejects profiles.
- Plan 003 is incomplete and prevents safe example-based validation.

## Maintenance notes

Keep optional services behind explicit profiles. If more notifiers are added,
give each independently optional integration its own named profile.
