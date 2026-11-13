# n8n

Docker Compose stack for [**n8n**](https://n8n.io/) — source-available workflow automation (fair-code licensed). Workflows, credentials, and settings are stored in a local **SQLite** database under `data/`.

n8n is routed by the existing Traefik stack at **`https://n8n.lexcode.dev`**. This is deliberately **LAN-only**: it has no host-published application ports and no Cloudflare Tunnel router. The existing `*.lexcode.dev` LAN DNS and DNS-01 wildcard certificate cover the one-label `n8n.lexcode.dev` hostname; no extra domain is needed.

## Prerequisites

- Docker and Docker Compose v2 on a 64-bit host
- LAN DNS resolving `*.lexcode.dev` to the Traefik host
- The [`proxy/`](../proxy/README.md) stack running after this stack, so Traefik can join `n8nnetwork` and `n8n-sandbox-network`

## First deployment

1. Create the private environment file and replace every placeholder. Do not commit it:

   ```bash
   cp .env.example .env
   ```

   Generate the `N8N_ENCRYPTION_KEY` value with `openssl rand -base64 48` (n8n requires at least 32 characters). Keep it permanently: n8n uses it to encrypt workflow credentials stored in SQLite — losing it makes saved credentials unrecoverable.

2. Create writable state directories before the first start. The official image runs as the `node` user (UID 1000), so give that user ownership rather than allowing Docker to create root-owned directories:

   ```bash
   mkdir -p data/n8n data/files
   sudo chown -R 1000:1000 data
   ```

3. Validate then start n8n. Start it before the proxy once so it creates its named Docker network:

   ```bash
   docker compose --env-file .env.example config --quiet
   docker compose up -d

   cd ../proxy
   docker compose up -d
   ```

4. Open `https://n8n.lexcode.dev` on the LAN and create the owner account on first visit.

## Routing and access

`n8n.lexcode.dev` has a normal `websecure` Traefik router with the `letsencrypt` certificate resolver. Traefik discovers the route from the `traefik.*` labels on the n8n service (Docker provider, `exposedByDefault=false`).

This stack intentionally does **not** include a Traefik `cloudflare` entrypoint router. Do not add `n8n.lexcode.dev` in Cloudflare Zero Trust → Tunnels → Public Hostnames; LAN DNS plus Traefik TLS is the selected access model. n8n's own login protects the editor; the hostname is not reachable outside the LAN.

`N8N_WEBHOOK_URL` is fixed to `https://n8n.lexcode.dev/` so the Webhook node generates URLs that resolve on the LAN. `N8N_RESTRICT_FILE_ACCESS_TO=/files` confines the Read/Write File nodes to `./data/files` (mounted at `/files`).

## n8n Assistant (optional)

n8n Assistant runs AI-generated code, so it needs an isolated sandbox. That sandbox is the sibling [`n8n-sandbox/`](../n8n-sandbox/README.md) stack — `sandbox-api`, a privileged Docker-in-Docker runner, and a bundled SearXNG. This stack owns `n8n-sandbox-network` and reaches `sandbox-api` by service name.

Enable it in `n8n/.env`:

1. Set `N8N_SANDBOX_SERVICE_API_KEY` to a value from `SANDBOX_API_KEYS` in `n8n-sandbox/.env` (they must match exactly).
2. Set `N8N_INSTANCE_AI_SANDBOX_ENABLED=true`.
3. Set a model and its key: `N8N_INSTANCE_AI_MODEL` (`provider/model`, e.g. `anthropic/claude-opus-4-8`) and `N8N_INSTANCE_AI_MODEL_API_KEY`.
4. Restart: `docker compose up -d`.

This stack **owns** `n8n-sandbox-network`, so it stays startable on its own: bring it up first, then `n8n-sandbox/` joins that network as external. n8n keeps working with the sandbox down; only n8n Assistant is affected. Web search uses the bundled SearXNG at `http://searxng:8080` unless `INSTANCE_AI_BRAVE_SEARCH_API_KEY` (no `N8N_` prefix) is set, which takes priority.

`N8N_INSTANCE_AI_SANDBOX_ENABLED` defaults to `false` here so the stack stays self-contained and `bash scripts/validate.sh` passes without the sandbox present.

**Env vars are not authoritative.** n8n stores the sandbox toggle in its own SQLite database (the `settings` row keyed `instanceAi.settings`) and a stored value beats `N8N_INSTANCE_AI_SANDBOX_ENABLED`. If `docker logs n8n | grep Sandbox` prints `enabled=false … (DB override)`, change it at Settings → Agents → Shared sandbox, or edit that JSON row with n8n stopped (`{"sandboxEnabled": true, "n8nSandboxServiceUrl": "http://sandbox-api:8080"}`). `enabled=true provider=n8n-sandbox` is the line you want. See [`n8n-sandbox/README.md`](../n8n-sandbox/README.md#troubleshooting).

## Querying TeslaMate's database

n8n joins `teslamatenetwork` (owned by [`teslamate/`](../teslamate/README.md)) so a Postgres node can read vehicle telemetry. Values for the n8n Postgres credential:

| Field | Value |
| --- | --- |
| Host | `teslamate_db` |
| Port | `5432` |
| Database | `teslamate` |
| User | `teslamate` |
| Password | `TM_DB_PASSWORD` from `teslamate/.env` |
| SSL | **Disable** |

Always use the service name `teslamate_db` (alias `database`), never an IP: both containers get dynamic addresses on `10.0.10.0/24`, so `10.0.10.5`-style values break on the next recreate.

Useful tables: `cars`, `drives`, `charging_processes`, `charges`, `positions`, `states`, `updates`, `geofences`, `settings`.

The database publishes no port to the host or LAN — this works only because n8n is a Docker-network peer in `teslamatenetwork`. Remove that network from `compose.yml` if no workflow needs it. Starting n8n before `teslamate/` has created the network fails with `network teslamatenetwork declared as external, but could not be found`.

## Operations

```bash
# Read-only container health/status from the repository root
bash scripts/status.sh n8n

# Follow logs
docker compose logs -f n8n

# Update images deliberately
docker compose pull
docker compose up -d
```

`data/n8n` is the authoritative n8n state: the SQLite database (`database.sqlite`), `~/.n8n` settings, and workflow/credential data. `data/files` is the optional file area exposed to workflows. Back up `data/` off-host; in particular keep `sqlite` backups together with the `N8N_ENCRYPTION_KEY` from `.env` or credentials cannot be restored.

## Boot with systemd (optional)

```bash
sudo cp ../systemd/n8n.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now n8n.service
```

Enable `proxy.service` too, and keep its ordering after `n8n.service`; Traefik attaches to the Docker network created by this stack.

## Layout

- `compose.yml` — n8n service with Traefik labels and SQLite persistence
- `.env.example` — non-secret configuration template
- `data/n8n/` — SQLite database and n8n state (not committed)
- `data/files/` — optional working files for Read/Write File nodes (not committed)
