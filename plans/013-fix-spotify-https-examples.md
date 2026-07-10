# Plan 013: Align Your Spotify examples with HTTPS OAuth requirements

> **Executor instructions**: Change placeholders and documentation only. Do not
> inspect real Spotify credentials or publish DNS/tunnel changes.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- analytics/.env.example analytics/README.md README.md proxy/README.md`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: docs
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

The analytics README correctly says Spotify requires HTTPS for non-localhost
redirects, but the copied example environment supplies HTTP host-IP endpoints.
Users following the template can configure endpoints Spotify rejects. The
primary example should reflect the intended tunneled production deployment.

## Current state

- `analytics/README.md:9` states the HTTPS requirement and line 19 asks for
  public HTTPS URLs.
- `analytics/.env.example:14` and line 16 use HTTP server-IP examples.
- `proxy/README.md:52` documents Cloudflare/NPM hostname routing for both the
  client and API.
- Compose passes the API/client endpoints at `analytics/compose.yml:16-17`.

## Target design

Use clearly fake HTTPS hostnames such as `https://api-spotify.example.com` and
`https://spotify.example.com` in `.env.example`. Document that both must match
the Spotify developer application and proxy/tunnel configuration. If retaining
localhost development examples, label them separately and do not use LAN IP
HTTP as the OAuth recommendation.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| HTTPS examples | `rg -n '^YOUR_SPOTIFY_(API|CLIENT)_ENDPOINT=https://' analytics/.env.example` | Two matches |
| No LAN HTTP examples | `rg -n '^YOUR_SPOTIFY_(API|CLIENT)_ENDPOINT=http://(YOUR_SERVER_IP|192\.)' analytics/.env.example` | No matches |
| Stack validation | `cd analytics && docker compose --env-file .env.example config --quiet` | Exit 0 |

## Scope

**In scope**: analytics example/README, root and proxy docs only if necessary
for consistency, plan status.

**Out of scope**: Spotify dashboard mutation, Cloudflare/NPM configuration,
credentials, ports, application code/images, or runtime startup.

## Steps

1. Replace primary endpoint examples with matching fake HTTPS hostnames.
2. Update README setup table and redirect URI examples consistently.
3. Cross-check proxy documentation uses container port 8080 for API upstream
   while public URL remains HTTPS.
4. Validate Compose and run documentation searches/diff checks.

## Test plan

- Both primary endpoint variables begin with `https://`.
- Neither primary endpoint uses a LAN-IP HTTP placeholder.
- Analytics configuration renders with the example environment.
- README redirect examples exactly match the example endpoint hostnames.

## Done criteria

- [ ] Both endpoint examples use HTTPS public placeholders.
- [ ] README and proxy examples agree on client/API roles.
- [ ] No credential or external dashboard was changed.
- [ ] Analytics config validates; Plan 013 is `DONE`.

## STOP conditions

- Upstream Spotify policy has materially changed and cannot be verified.
- Correct examples require a real user domain or credential value.

## Maintenance notes

Keep public origin URLs distinct from Docker service-to-service upstream
addresses and host-published ports.
