# Plan 007: Restrict high-authority administration ports

> **Executor instructions**: This plan changes network reachability. Use
> configurable bind addresses with compatibility defaults chosen from existing
> documented use, never assume a specific LAN IP. Do not alter host firewalls.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- management monitoring proxy README.md management/README.md monitoring/README.md proxy/README.md`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: security
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Dockge and Dozzle have Docker-host authority, the Dozzle agent exports Docker
logs remotely, and Nginx Proxy Manager's admin UI is sensitive. Their ports are
currently bound to every host interface. Making bind addresses explicit lets
operators constrain these surfaces to loopback or a management LAN without
changing application behavior.

## Current state

- Dockge: `management/compose.yml:7`, writable socket at line 11.
- Dozzle UI: `monitoring/compose.yml:52`, writable socket at line 49.
- Dozzle agent: `monitoring/compose.yml:67`, read-only socket at line 65.
- NPM admin: `proxy/compose.yml:48`; public HTTP/HTTPS at lines 46-47 must
  remain available and are out of scope.
- Existing READMEs describe direct LAN and reverse-proxy access.

## Target design

Prefix only sensitive published ports with environment-configurable bind
addresses. Use service-specific variables such as `DOCKGE_BIND_ADDRESS`,
`DOZZLE_BIND_ADDRESS`, `DOZZLE_AGENT_BIND_ADDRESS`, and
`NPM_ADMIN_BIND_ADDRESS`. Default UI/admin binds to `127.0.0.1`; because remote
Dozzle agents intentionally support multi-host access, require its bind address
explicitly instead of silently defaulting public. Document setting a trusted
LAN address when remote access is required.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Repository validation | `bash scripts/validate.sh` | Exit 0 |
| Rendered bind audit | Render each affected stack as JSON and inspect `.ports[].host_ip` with `jq` | Sensitive UI/admin ports are loopback; agent uses configured test LAN address |
| Public NPM ports | `cd proxy && docker compose --env-file .env.example config --format json | jq -e '.services["nginx-proxy-manager"].ports | any(.target == 80) and any(.target == 443)'` | Exit 0 |

## Scope

**In scope**: affected Compose files, their `.env.example` files and READMEs,
root README if needed, plan status.

**Out of scope**: host firewall/router changes, authentication configuration,
Docker socket removal, NPM public ports 80/443, Beszel, application accounts,
or starting containers.

## Steps

1. Parameterize Dockge, Dozzle UI, Dozzle agent, and NPM admin host IPs.
2. Use required interpolation for Dozzle agent if no safe universal default
   preserves its documented remote-agent purpose; make the example explicit.
3. Update examples and docs with loopback, single trusted LAN address, and
   reverse-proxy implications. Warn that `0.0.0.0` restores broad exposure.
4. Validate with non-secret test bind values and assert rendered `host_ip`.
5. Confirm NPM ports 80 and 443 are unchanged.

## Test plan

- Default example render succeeds.
- Admin/UI ports render loopback.
- Agent renders only the example management address, not `0.0.0.0`.
- Public web ingress remains unchanged.

## Done criteria

- [ ] All four sensitive endpoints have explicit configurable host binds.
- [ ] Example configuration avoids all-interface exposure.
- [ ] Remote-agent LAN setup is documented.
- [ ] NPM public 80/443 behavior is unchanged.
- [ ] All affected stacks validate; Plan 007 is `DONE`.

## STOP conditions

- The maintainer requires broad LAN access but no trusted interface/address can
  be represented safely in `.env.example`.
- Docker Compose does not render host IP variables consistently.
- The change would require firewall or authentication mutations.

## Maintenance notes

Review published ports for every new host-authority service. Binding reduces
reachability but does not replace application authentication or firewall rules.
