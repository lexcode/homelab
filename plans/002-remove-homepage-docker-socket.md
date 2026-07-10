# Plan 002: Remove Homepage's direct Docker socket access

> **Executor instructions**: Follow every step and verification gate. Run the
> drift check first. Stop on any condition listed below instead of expanding
> scope. Update Plan 002 in `plans/README.md` when complete.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- homepage/compose.yml homepage/README.md homepage/data/homepage/config/docker.yaml`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: security
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Homepage currently mounts the Docker socket directly even though the stack
already provides a restricted Docker Socket Proxy. A read-only filesystem bind
does not make Docker API operations read-only. Removing the direct mount makes
the proxy's `POST=0` policy the only Docker access path available to Homepage.

## Current state

- `homepage/compose.yml:12` mounts `/var/run/docker.sock` into `homepage`.
- `homepage/compose.yml:79` defines `dockerproxy`; `POST=0` is set at line 88
  and that service alone mounts the socket at line 92.
- `homepage/data/homepage/config/docker.yaml:12` already points Homepage to
  `dockerproxy:2375`, so no endpoint migration should be required.
- `homepage/README.md:41` claims the proxy avoids granting Homepage full socket
  access, which is currently contradicted by the Compose file.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Stack validation | `cd homepage && docker compose --env-file .env.example config --quiet` | Exit 0 |
| Socket inventory | `cd homepage && docker compose --env-file .env.example config --format json | jq -r '.services | to_entries[] | select(any(.value.volumes[]?; .source == "/var/run/docker.sock")) | .key'` | Only `dockerproxy` |
| Formatting | `git diff --check` | Exit 0 |

## Scope

**In scope**: `homepage/compose.yml`, `homepage/README.md`, and
`plans/README.md` status only.

**Out of scope**: changing socket-proxy permissions, publishing port 2375,
widget credentials, dashboard YAML, image versions, or starting containers.

## Git workflow

- Branch: `advisor/002-remove-homepage-docker-socket`
- Suggested commit: `fix: restrict homepage docker access`
- Do not push or open a PR unless requested.

## Steps

### Step 1: Remove the direct socket volume

Delete only the `/var/run/docker.sock:/var/run/docker.sock:ro` entry from the
`homepage` service. Keep the socket mount on `dockerproxy` and retain `POST=0`.

**Verify**: run the socket inventory command. Expected output is exactly
`dockerproxy`.

### Step 2: Align documentation

Update `homepage/README.md` to state explicitly that Homepage reaches Docker
only through `dockerproxy:2375`, and that the raw socket is mounted only in the
proxy container. Keep the existing `docker.yaml` example.

**Verify**: `rg -n "dockerproxy|Docker socket|2375" homepage/README.md homepage/data/homepage/config/docker.yaml` shows a consistent proxy-only path.

### Step 3: Validate

Run the stack validation, socket inventory, `git diff --check`, and
`git diff --name-only` commands. Do not run `docker compose up`.

## Test plan

- Render with `.env.example`.
- Assert only `dockerproxy` has the socket source.
- Assert `docker.yaml` still names `dockerproxy` and port `2375`.

## Done criteria

- [ ] Homepage has no direct Docker socket mount.
- [ ] Dockerproxy retains the socket mount and `POST=0`.
- [ ] Rendered Compose passes and socket inventory returns only `dockerproxy`.
- [ ] Documentation describes proxy-only Docker access.
- [ ] Only in-scope files changed; Plan 002 is `DONE`.

## STOP conditions

- `docker.yaml` no longer points to `dockerproxy:2375`.
- A required Homepage feature demonstrably needs a raw socket rather than the
  configured proxy API.
- Verification requires broadening proxy permissions or starting containers.

## Maintenance notes

Review future Homepage changes for accidental reintroduction of the raw socket.
Changes to proxy API permissions require a separate security review.
