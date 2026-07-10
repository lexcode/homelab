# Plan 011: Align systemd state with Compose stack health

> **Executor instructions**: Execute only after Plan 006 establishes detached
> unit semantics. This plan designs observable health; do not install or restart
> units on the user's host.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- systemd/*.service systemd/README.md README.md scripts`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/006-fix-proxy-systemd-network-race.md`
- **Category**: tech-debt
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Systemd currently supervises Compose clients, while Docker restart policies and
healthchecks govern containers independently. An active unit therefore does
not mean its containers are running or healthy. Operators need a documented,
read-only status command and unit hooks whose failure semantics are explicit.

## Current state

- Every unit uses `Restart=on-failure`; containers also use Docker restart
  policies throughout the repository.
- Healthchecks exist only for selected services and do not affect systemd unit
  state.
- There is no repository command that summarizes expected/running/healthy
  services per stack.
- Plan 006 changes units to detached `Type=oneshot` ownership; do not undo it.

## Target design

Create `scripts/status.sh [stack|--all]`, a read-only command using
`docker compose ps --format json` from each stack directory. It should report
project/service state, health when available, and a non-zero exit status when
an expected service is absent, exited, restarting, or unhealthy. Profiles must
be explicit inputs so optional services are not treated as missing. Add
`ExecStartPost` config/state sanity only if it can reliably complete without
turning transient application warm-up into a unit failure; otherwise keep
health assessment in the status tool and document the boundary.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Shell syntax | `bash -n scripts/status.sh` | Exit 0 |
| Read-only scan | `rg -n 'compose (up|down|restart|pull)|docker (start|stop|rm)' scripts/status.sh` | No matches |
| Unit syntax | `systemd-analyze verify systemd/*.service` | No syntax errors |
| Config baseline | `bash scripts/validate.sh` | Exit 0 |

## Scope

**In scope**: new status script, systemd units only if a safe post-start check
is justified, systemd/root docs, plan status.

**Out of scope**: adding healthchecks to every third-party app, alerting
services, live systemctl/Docker mutations, changing restart policies, optional
profile defaults, or replacing monitoring tools.

## Steps

1. Define expected service selection from rendered Compose rather than a
   duplicated hardcoded inventory. Default profiles only unless supplied.
2. Parse Compose JSON robustly and classify running/healthy/no-healthcheck,
   restarting, exited, and missing states. Never print environment values.
3. Return 0 only when every expected default service is running and none with a
   healthcheck is unhealthy.
4. Decide whether `ExecStartPost` is reliable with current service warm-up. If
   not, explicitly document why unit active state means orchestration succeeded
   and `scripts/status.sh` is the health authority. Do not add brittle sleeps.
5. Document operator commands and run static checks.

## Test plan

- Use mocked JSON fixtures under `/tmp` or a script test mode for healthy,
  unhealthy, restarting, missing, and no-healthcheck cases; remove fixtures.
- Validate no mutating commands exist.
- Validate systemd syntax if units change.

## Done criteria

- [ ] One read-only command reports all stack service states.
- [ ] Failure exit codes cover missing/exited/restarting/unhealthy services.
- [ ] Optional profiles are not false failures.
- [ ] Systemd/Docker ownership boundary is documented accurately.
- [ ] No live services changed; Plan 011 is `DONE`.

## STOP conditions

- Installed Compose JSON format lacks stable fields needed for classification.
- Reliable unit health would require arbitrary sleeps or app-specific network
  polling across all services.
- Plan 006 has not landed or chose a different ownership model.

## Maintenance notes

Add status-fixture coverage when new Compose states or optional profiles are
introduced. Application-level monitoring remains Beszel/Dozzle territory.
