# TeslaMate

Docker Compose stack for [**TeslaMate**](https://docs.teslamate.org/) — Tesla vehicle telemetry collection, its PostgreSQL database, Mosquitto, Grafana dashboards, and daily PostgreSQL backups.

TeslaMate is routed by the existing Traefik stack at **`https://tesla.lexcode.dev`**. This is deliberately **LAN-only**: it has no host-published application ports and no Cloudflare Tunnel router. The existing `*.lexcode.dev` LAN DNS and DNS-01 wildcard certificate cover the one-label `tesla.lexcode.dev` hostname; no extra domain is needed.

## Prerequisites

- Docker and Docker Compose v2 on a 64-bit host (TeslaMate supports aarch64 and amd64)
- At least 1 GB RAM; TeslaMate recommends 2 GB
- LAN DNS resolving `*.lexcode.dev` to the Traefik host
- The [`proxy/`](../proxy/README.md) stack running after this stack, so Traefik can join `teslamatenetwork`
- A Tesla access token and refresh token, generated according to TeslaMate's [token guide](https://docs.teslamate.org/docs/installation/docker#usage)

## First deployment

1. Create the private environment file and replace every placeholder. Do not commit it:

   ```bash
   cp .env.example .env
   ```

   Generate the sensitive values with the commands noted in the template. Keep `TM_ENCRYPTION_KEY` permanently: TeslaMate uses it to encrypt the Tesla API tokens stored in PostgreSQL.

2. Create writable state directories before the first start. PostgreSQL, Grafana, and Mosquitto run as their own container users, so give those users ownership rather than allowing Docker to create root-owned directories:

   ```bash
   mkdir -p data/{database,grafana,mosquitto,import,db_dumps}
   sudo chown -R 999:999 data/database
   sudo chown -R 472:472 data/grafana
   sudo chown -R 1883:1883 data/mosquitto
   ```

3. Validate then start TeslaMate. Start it before the proxy once so it creates its named Docker network:

   ```bash
   docker compose --env-file .env.example config --quiet
   docker compose up -d

   cd ../proxy
   docker compose up -d
   ```

4. Open `https://tesla.lexcode.dev` on the LAN, then enter the Tesla access and refresh tokens. Open `https://tesla.lexcode.dev/grafana` and sign in with `TM_GRAFANA_USER` / `TM_GRAFANA_PASSWORD`.

5. In TeslaMate, open **Settings → URLs** and set:

   - **Web App:** `https://tesla.lexcode.dev`
   - **Dashboards:** `https://tesla.lexcode.dev/grafana`

## Routing and access

Both web applications have normal `websecure` Traefik routers. Grafana's router is restricted to `/grafana` and has higher priority than TeslaMate's root router, so TeslaMate and its dashboards share the same hostname safely.

This stack intentionally does **not** include a Traefik `cloudflare` entrypoint router. Do not add `tesla.lexcode.dev` in Cloudflare Zero Trust → Tunnels → Public Hostnames; doing so would expose an application that stores Tesla API credentials. LAN DNS plus Traefik TLS is the selected access model.

TeslaMate's upstream Traefik guide recommends HTTP Basic Authentication when publishing to the Internet. That is intentionally omitted here because this service is LAN-only; Grafana's own login remains enabled and anonymous access is disabled.

## Operations

```bash
# Read-only container health/status from the repository root
bash scripts/status.sh teslamate

# Follow collector logs
docker compose logs -f teslamate

# Update images deliberately
docker compose pull
docker compose up -d
```

`data/database` is the authoritative TeslaMate state, including encrypted API tokens. `data/grafana` contains Grafana state, `data/mosquitto` contains MQTT persistence, `data/import` is TeslaMate's import directory, and `data/db_dumps` contains daily PostgreSQL backups. Back up `data/` off-host. Database backup retention is controlled by the `TM_DB_BACKUP_KEEP_*` variables.

To restore a PostgreSQL custom-format dump, stop the application services, restore into the database container with `pg_restore`, then start the stack again. Test the exact restore procedure against a copy before relying on it for disaster recovery.

## Boot with systemd (optional)

```bash
sudo cp ../systemd/teslamate.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now teslamate.service
```

Enable `proxy.service` too, and keep its ordering after `teslamate.service`; Traefik attaches to the Docker network created by this stack.

## Layout

- `compose.yml` — TeslaMate, PostgreSQL, Grafana, Mosquitto, and database backup services
- `.env.example` — non-secret configuration template
- `data/database/` — PostgreSQL cluster (not committed)
- `data/grafana/` — Grafana state (not committed)
- `data/mosquitto/` — MQTT persistence (not committed)
- `data/import/` — TeslaMate imports (not committed)
- `data/db_dumps/` — daily PostgreSQL backups (not committed)
