# Pulsearr

Pulsearr's production stack runs the published API and worker image with its
own PostgreSQL database and daily database backups. The API is available only
on the LAN or private tailnet; no reverse proxy or public ingress is configured.

The API joins `servarrnetwork`, the worker joins `notificationsnetwork`, and
both join the private `pulsearrnetwork`. PostgreSQL and its backup sidecar stay
on `pulsearrnetwork` only. Jellyfin remains on its separate Unraid host at
`192.168.0.149`.

## Prerequisites

- Docker and Docker Compose v2
- The `media` and `notifications` stacks running, so their external networks exist
- Tailscale installed and connected on the homelab host and any remote client
  that needs private API access
- The public `ghcr.io/lexcode/pulsearr:latest` image

## Setup

1. Create the local environment and persistent directories:

   ```bash
   cd ~/git/homelab/pulsearr
   cp .env.example .env
   mkdir -p data/database data/db_dumps
   ```

2. Set a strong `PULSEARR_DB_PASSWORD`, the TMDB v4 read-access token, Gotify
   application token, and Jellyfin API key in `.env`. Keep `.env` local. The
   worker uses the schedule values in that file: catalogue sync daily at 06:00,
   Jellyfin refresh every 15 minutes, and the weekly summary at 09:00 on Sunday
   (all in `APP_TIMEZONE`). Adjust the three cron expressions if needed.

3. Start the dependency stacks, then Pulsearr:

   ```bash
   docker compose -f ../media/compose.yml up -d
   docker compose -f ../notifications/compose.yml up -d
   docker compose pull
   docker compose up -d
   ```

The API entrypoint waits for PostgreSQL's healthcheck, applies pending Drizzle
migrations, and then starts the server. It is safe to restart; migrations are
explicit and idempotent.

## Verify

```bash
docker compose ps
curl --fail http://192.168.0.24:8700/api/v1/health
docker compose exec -T worker /app/scripts/container-entrypoint.sh worker status
docker compose exec -T worker /app/scripts/container-entrypoint.sh worker sync
docker compose exec -T worker /app/scripts/container-entrypoint.sh worker refresh-library
```

The worker runs `worker schedule` continuously and owns all scheduled work; no
host cron is needed. The first complete sync establishes the baseline without
sending a digest. An immediately repeated sync must report no duplicate
arrivals. `worker refresh-library` verifies Jellyfin connectivity and refreshes
the local library index. To send a weekly summary on demand, run
`docker compose exec -T worker /app/scripts/container-entrypoint.sh worker weekly`.
The worker reaches TMDB and Jellyfin over its normal outbound connection and
Gotify as `http://gotify:80` on `notificationsnetwork`.

For private remote access, run `tailscale up` on both the host and workstation,
then repeat the health request using the host's Tailscale IP or MagicDNS name.
Do not enable Funnel; Pulsearr has no public ingress.

## Backups and recovery

`backup` writes daily PostgreSQL dumps to `data/db_dumps` and retains seven
daily backups by default. Back up both `data/database` and `data/db_dumps`
off-host.

To restore a dump, stop the application containers while keeping PostgreSQL
available, inspect the chosen compressed dump, and pipe it into `psql`:

```bash
docker compose stop api worker backup
gunzip -c data/db_dumps/daily/CHOSEN_DUMP.sql.gz |
  docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose up -d
```

Restore into an empty database unless the dump's contents explicitly support a
different procedure. Preserve `data/database` before recovery so the previous
state remains available for rollback.

## Troubleshooting

- `network servarrnetwork not found`: start the `media` stack first.
- `network notificationsnetwork not found`: start `notifications` first.
- API unhealthy: inspect `docker compose logs api db`; migration or Zod errors
  name the missing configuration.
- Worker cannot reach Gotify: verify
  `docker compose exec -T worker getent hosts gotify` and the
  `GOTIFY_APP_TOKEN` application token.
- Worker cannot reach TMDB: verify outbound DNS/HTTPS and that
  `TMDB_API_TOKEN` is the v4 read-access token.
- Worker cannot reach Jellyfin: verify `JELLYFIN_URL`, `JELLYFIN_API_KEY`, and
  that the homelab host can reach the Unraid Jellyfin address.
- Scheduled work is not running: inspect `docker compose logs worker`, then
  verify `SYNC_CRON`, `LIBRARY_REFRESH_CRON`, `WEEKLY_SUMMARY_CRON`, and
  `APP_TIMEZONE` in `.env`.
- GHCR pull denied: confirm the package is public; no registry PAT should be
  needed on the host.
- Tailscale route unavailable: check `tailscale status` on both machines and
  use the host's real tailnet address, never `0.0.0.0`.
