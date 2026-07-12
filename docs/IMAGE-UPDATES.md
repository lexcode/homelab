# Container image update policy

Every runtime image in this repository is pinned to a readable release tag and
an immutable multi-platform manifest digest. The tag makes reviews legible; the
digest ensures the same repository commit deploys the same artifact later.

## Tiers

- **Tier 1** covers images with Docker socket access, elevated privileges,
  ingress responsibility, persistent application state, or database duties.
  These require an immutable digest, a backup or rollback prerequisite, and a
  focused runtime smoke check.
- **Tier 2** covers ordinary stateless applications. These still use a tested
  release tag and digest, but generally need only configuration validation and
  an application-level smoke check.

Database major tags are deliberate compatibility boundaries. An image refresh
must not change `mongo:4.4`, `postgres:18`, or `redis:7` to another major as part
of routine maintenance.

## Inventory

The exact selected `tag@sha256` reference is authoritative in each listed
Compose file. All references below were verified on 2026-07-12 against their
official registry manifests and include `linux/arm64` support.

| Stack | Images | Tier | Classification |
| --- | --- | --- | --- |
| `proxy` | cloudflared 2026.7.1; Tailscale v1.98.8; Nginx Proxy Manager 2.15.1 | 1 | Ingress; Tailscale is privileged; NPM is stateful |
| `management` | Dockge 1.5.0 | 1 | Docker socket and stack control |
| `monitoring` | Beszel/agent 0.18.7; Dozzle v10.6.9 | 1 | Persistent metrics, host access, and Docker socket |
| `notifications` | Gotify 2.9.1; iGotify v1.5.1.3; changedetection.io 0.55.7 | 1 | Persistent notification and watch state |
| `documents` | Redis 7; paperless-ngx 2.20.15; Postgres 18; paperless-ai 3.0.9; paperless-gpt v0.26.1 | 1 | Document and database state; AI helpers share the stack |
| `analytics` | Your Spotify server/client 1.20.0; Mongo 4.4 | 1 | Listening history and database state |
| `media` | wireguard-pia 20260701; qBittorrent 5.2.3; deunhealth v0.3.0; Sonarr 4.0.19; Radarr 6.2.1; Lidarr 3.1.0; Bazarr 1.6.0; Seerr v3.3.0; Prowlarr 2.4.0; SuggestArr v2.9.1; FlareSolverr v3.5.0 | 1/2 | Privileged VPN, Docker socket, persistent media managers; stateless helpers are Tier 2 |
| `dns` | AdGuard Home v0.107.77 | 1 | Network-critical persistent configuration |
| `homepage` | Homepage v1.13.2; docker-socket-proxy v0.4.2 | 1/2 | Dashboard is Tier 2; proxy has Docker socket access |
| `terminal` | Atuin c28ac1b; Postgres 18; postgres-backup-local 18-debian-d257e5d | 1 | Shell history, database, and backups |

## Controlled update workflow

1. Check the upstream release notes and image registry. Confirm the proposed
   tag is stable, supports `linux/arm64`, and does not require a configuration
   or data migration.
2. For Tier 1 stateful services, confirm a recent backup exists and identify
   the previous `tag@digest` from Git before changing the reference. For
   database images, keep the existing major tag.
3. Inspect the candidate manifest without pulling or starting it:

   ```bash
   docker buildx imagetools inspect IMAGE:TAG
   ```

   Record the manifest-list digest and use `IMAGE:TAG@sha256:DIGEST` in the
   relevant Compose file. Update the inventory version and verification date.
4. From the changed stack directory, render the committed example:

   ```bash
   docker compose --env-file .env.example config --quiet
   ```

5. Run the repository gate before committing:

   ```bash
   bash scripts/validate.sh
   ```

6. Review the diff, then deploy only the changed stack during a maintenance
   window. This repository workflow does not pull, recreate, or restart runtime
   containers automatically.

## Runtime smoke checks

| Stack | Operator check after deployment |
| --- | --- |
| `proxy` | Tunnel is connected; NPM admin and one proxied hostname respond; optional Funnel remains opt-in |
| `management` | Dockge loads and lists the expected stacks without changing them |
| `monitoring` | Beszel receives agent data and Dozzle can read container logs |
| `notifications` | Gotify UI loads, a test notification arrives, iGotify `/api/Version` responds, and changedetection opens |
| `documents` | Paperless UI loads, database/Redis health is green, and one AI helper can reach the Paperless API |
| `analytics` | Client and API load, OAuth callback remains valid, and existing listening history is present |
| `media` | VPN reports the expected public IP; qBittorrent and each manager UI load; indexer test succeeds |
| `dns` | AdGuard UI loads and a LAN client resolves a known hostname through it |
| `homepage` | Dashboard renders and Docker-backed widgets populate through the socket proxy |
| `terminal` | Atuin sync succeeds and the backup container reports a successful scheduled/manual dump |

## Rollback

If a smoke check fails, stop expanding the rollout. Restore the previous image
reference from Git, render the stack configuration again, and recreate only the
affected service. Do not roll database data backward blindly: restore from the
pre-update backup if the application changed stored data incompatibly. Capture
the failure and upstream migration requirement before attempting another pin.

Review Tier 1 images monthly and Tier 2 images at least quarterly. Security
advisories can accelerate either cadence, but they do not remove the backup,
release-note, validation, or smoke-check requirements.
