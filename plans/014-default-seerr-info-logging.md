# Plan 014: Default Seerr to informational logging

> **Executor instructions**: Make logging configurable; do not remove the
> ability to enable debug temporarily. Update Plan 014 in the index.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- media/compose.yml media/.env.example media/README.md README.md`

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: perf
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Seerr runs permanently at debug level while neighboring long-running services
default to info. Debug logs increase Docker log volume and disk I/O and obscure
important operational events. Operators should opt into debug only during
troubleshooting.

## Current state

- `media/compose.yml:238` hardcodes `LOG_LEVEL=debug` for Seerr.
- SuggestArr and FlareSolverr demonstrate configurable info defaults at lines
  285 and 292.
- `media/.env.example` has service-specific logging variables but none for
  Seerr.

## Target design

Use `LOG_LEVEL=${SEERR_LOG_LEVEL:-info}` and add
`SEERR_LOG_LEVEL=info` to the example environment near other optional service
settings. Document accepted values only if confirmed by upstream/current image.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Stack validation | `cd media && docker compose --env-file .env.example config --quiet` | Exit 0 |
| Default value | `cd media && docker compose --env-file .env.example config --format json | jq -e '.services.seerr.environment.LOG_LEVEL == "info"'` | Exit 0 |
| Override value | `cd media && SEERR_LOG_LEVEL=debug docker compose --env-file .env.example config --format json | jq -e '.services.seerr.environment.LOG_LEVEL == "debug"'` | Exit 0 |

## Scope

**In scope**: media Compose/example/README, root docs only if logging is listed,
plan status.

**Out of scope**: Docker daemon log rotation, other services' logging, image
versions, Seerr data, or starting containers.

## Steps

1. Replace hardcoded debug with the service-specific info-default variable.
2. Add the example variable and concise troubleshooting instructions: enable
   debug temporarily, reproduce, then restore info.
3. Run default and override assertions, repository validation, and diff checks.

## Test plan

- Example/default render produces `LOG_LEVEL=info` for Seerr.
- An explicit process-environment override produces `LOG_LEVEL=debug`.
- Media Compose still renders and no other service log level changes.

## Done criteria

- [x] Default rendered Seerr log level is info.
- [x] Explicit debug override still works.
- [x] Documentation explains temporary troubleshooting use.
- [x] Stack validates; Plan 014 is `DONE`.

## STOP conditions

- The current Seerr image does not support `info`/`debug` through `LOG_LEVEL`.
- Fixing log growth requires Docker daemon changes rather than this variable.

## Maintenance notes

Container log rotation is a separate host-level concern. Keep verbose logging
opt-in for long-running services.
