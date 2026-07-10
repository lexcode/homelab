# Plan 012: Define one authoritative Paperless AI API URL

> **Executor instructions**: This is a template/documentation correction. Do
> not read or change `documents/.env` or runtime data.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- documents/.env.example documents/compose.yml documents/README.md README.md`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: docs
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

`documents/.env.example` defines `PAPERLESS_API_URL` twice. The later value wins
silently, so editing the first does nothing, and the first value incorrectly
uses the host-published port for container-to-container traffic. A single
documented internal endpoint removes ambiguous onboarding behavior.

## Current state

- `documents/.env.example:11` defines `PAPERLESS_API_URL` using port 8001.
- `documents/.env.example:29` defines it again using container port 8000 and
  `/api`.
- `documents/compose.yml:74` passes the final value to paperless-ai.
- Paperless itself listens on container port 8000 and publishes host port 8001
  at `documents/compose.yml:27`.

## Target design

Keep exactly one `PAPERLESS_API_URL=http://paperless-ngx:8000/api` entry in the
paperless-ai section. Keep `PAPERLESS_BASE_URL` separately for paperless-gpt.
Document internal container URL versus user-facing host/public URL.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Definition count | `test "$(rg -c '^PAPERLESS_API_URL=' documents/.env.example)" -eq 1` | Exit 0 |
| Stack validation | `cd documents && docker compose --env-file .env.example config --quiet` | Exit 0 |
| Rendered value | `cd documents && docker compose --env-file .env.example config --format json | jq -e '.services["paperless-ai"].environment.PAPERLESS_API_URL == "http://paperless-ngx:8000/api"'` | Exit 0 |

## Scope

**In scope**: documents example/README, root docs only if they repeat the wrong
endpoint, plan status.

**Out of scope**: application provider settings, real environment, host port
8001, Paperless public URL, API tokens, or container startup.

## Steps

1. Remove the earlier duplicate and keep one internal API endpoint.
2. Group and comment variables by consumer (`paperless-ngx`, `paperless-ai`,
   `paperless-gpt`) without changing unrelated values.
3. Document why containers use service name and port 8000 while browsers use
   host port 8001 or the public URL.
4. Run definition count, rendered assertion, repository validation, and diff
   checks.

## Test plan

- Static count confirms one `PAPERLESS_API_URL` assignment.
- Rendered paperless-ai environment contains the internal port 8000 `/api`
  endpoint.
- Documentation distinguishes that internal endpoint from host port 8001.

## Done criteria

- [ ] Exactly one API URL definition exists.
- [ ] It renders to the correct internal endpoint for paperless-ai.
- [ ] Host/public/internal URL roles are documented.
- [ ] No secrets or runtime state changed; Plan 012 is `DONE`.

## STOP conditions

- Current paperless-ai upstream documentation requires a different path.
- Existing code has changed the service/container port.

## Maintenance notes

Keep environment templates free of duplicate keys; the validation baseline
should add a duplicate-key check if implemented portably.
