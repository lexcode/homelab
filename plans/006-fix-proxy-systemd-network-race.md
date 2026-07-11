# Plan 006: Make proxy startup wait for external Docker networks

> **Executor instructions**: Systemd lifecycle changes are operationally
> sensitive. Follow the exact scope, run static verification, and do not enable,
> restart, or stop host services. Update Plan 006 in the index.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- systemd/*.service systemd/README.md README.md proxy/compose.yml`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: bug
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

`proxy.service` uses `After=` to order itself after stacks that create external
networks, but those units are implicit `Type=simple` services running attached
`docker compose up`. Systemd considers them started when the Compose client is
launched, not when network creation succeeds. A parallel cold boot can still
start proxy too early and enter a restart loop.

## Current state

- `systemd/proxy.service:3` lists seven network-producing units in `After=`.
- All units use `ExecStart=/usr/bin/docker compose up`, `ExecStop=... down`,
  and no explicit `Type`; `systemd/media.service:8` is representative.
- `proxy/compose.yml:65-77` declares seven external networks.
- `README.md:240` promises that systemd ordering prevents missing networks.

## Target design

Make every stack unit use detached startup with `Type=oneshot` and
`RemainAfterExit=yes`, so successful unit activation means `docker compose up
-d` completed. Keep `ExecStop=docker compose down`. Preserve Docker dependency
lines and proxy's existing producer ordering. This plan establishes startup
completion semantics only; Plan 011 separately addresses health observability
and supervision policy.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Unit syntax | `systemd-analyze verify systemd/*.service` | No unit syntax/errors; environment permission warnings may be noted separately |
| Unit consistency | `for f in systemd/*.service; do rg -q '^Type=oneshot$' "$f" && rg -q '^RemainAfterExit=yes$' "$f" && rg -q '^ExecStart=/usr/bin/docker compose up -d$' "$f" || exit 1; done` | Exit 0 |
| Stack config | `bash scripts/validate.sh` | Exit 0 |

## Scope

**In scope**: all ten `systemd/*.service` files, `systemd/README.md`, root
README systemd section, and plan status.

**Out of scope**: installing units, `systemctl`, changing Compose restart
policies or healthchecks, adding network polling scripts, changing proxy
networks, path portability, or Funnel boot behavior.

## Steps

1. Apply identical `Type=oneshot`, `RemainAfterExit=yes`, and detached
   `ExecStart` semantics to every unit. Keep `ExecStop` and working directories.
2. Re-evaluate `Restart=on-failure`: oneshot units with `RemainAfterExit` may
   use it for startup failures, but confirm systemd accepts the combination.
   Preserve it if valid; do not invent a timer or polling loop.
3. Keep proxy's `After=` list matched exactly to external networks in
   `proxy/compose.yml`. Add no dependency on dns/notifications unless proxy is
   also changed to consume those networks, which is out of scope.
4. Update docs: activation now completes after detached Compose startup, while
   container health remains Docker/Compose responsibility.
5. Run unit syntax, consistency, repository validation, and `git diff --check`.

## Test plan

- Static verification of all units.
- Machine-check identical lifecycle directives across all ten units.
- Confirm proxy `After=` producers correspond to external network definitions.
- No live boot test in the user's host environment; document a later manual
  cold-boot observation step without executing it.

## Done criteria

- [x] Every unit has consistent oneshot/detached semantics.
- [x] Successful producer activation occurs after `compose up -d` returns.
- [x] Proxy ordering and external network inventory remain aligned.
- [x] Static unit and Compose validation pass.
- [x] No host systemd or Docker state changed; Plan 006 is `DONE`.

## STOP conditions

- `systemd-analyze verify` rejects the chosen lifecycle combination.
- A unit requires attached logs as a documented operational requirement.
- Fixing the race requires a live systemd installation or custom polling script.

## Maintenance notes

When adding a proxy external network, add its producer unit to `After=` and to
the documented ordering. Plan 011 should build health reporting on top of this
detached ownership model rather than reverting it accidentally.
