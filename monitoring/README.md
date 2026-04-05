# Monitoring (Beszel)

Docker Compose stack for [Beszel](https://github.com/henrygd/beszel): a small hub for metrics and alerts, plus a **Beszel agent** on the same host reporting CPU, memory, disk, Docker containers, and optional extra mount points.

## Prerequisites

- Docker and Docker Compose v2
- Agent needs read-only access to `/var/run/docker.sock` (already mapped in `compose.yml`)

## Quick start

1. **Environment**

   ```bash
   cp .env.example .env
   ```

2. **Create the folder structure**

   If you're using bind mounts (like this stack does), create the directories up front so Docker doesn't create them as root.

   ```bash
   mkdir -p \
     data/beszel_data \
     data/beszel_agent_data \
     data/dozzle_data
   ```

3. **Start the hub** (agent env vars can be placeholders for the first boot if you prefer to fill them after opening the UI):

   ```bash
   docker compose up -d
   ```

4. **Open Beszel** at the URL you configured (`BESZEL_URL`, port `BESZEL_PORT`). Create an account if prompted.

5. **Add this machine in the UI**  
   When you register the host, Beszel shows the values the agent needs. Copy them into `.env` as `BESZEL_AGENT_KEY` and `BESZEL_AGENT_TOKEN`, then:

   ```bash
   docker compose up -d
   ```

   Restart picks up the new agent credentials so the host appears online in the dashboard.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `MONITORING_SUBNET` | Docker bridge CIDR for `monitoringnetwork`. Must match `BESZEL_IP`. |
| `BESZEL_IP` | Static IPv4 for the `beszel` container on `monitoringnetwork`. |
| `BESZEL_PORT` | Host port published for the web UI (default `8090`). |
| `BESZEL_URL` | Public URL you use to open Beszel (e.g. `http://localhost:8090` or `https://beszel.example.com`). Passed to the agent as `HUB_URL` and used by the hub as `APP_URL`. **Use the same scheme/host/port you actually browse to**, or the agent may not connect reliably. |
| `BESZEL_LOG_LEVEL` | Hub log level (default `info`). |
| `BESZEL_AGENT_KEY` | Agent key from the Beszel UI (SSH-style line). |
| `BESZEL_AGENT_TOKEN` | Agent token from the Beszel UI. |
| `BESZEL_AGENT_LISTEN` | Agent listen port (default `45876`); traffic reaches the agent via `network_mode: service:beszel`. |

`.env.example` also lists `BESZEL_AGENT_LOG_LEVEL`; the current `compose.yml` does not pass it into the agent—add an `environment` entry there if the image documents support for it.

`.env.example` uses placeholder key/token; replace them with values from your hub.

## Architecture (this repo)

- **`beszel`**: Hub UI + API, data in `./data/beszel_data`.
- **`beszelagent`**: `network_mode: service:beszel` so the agent shares the hub’s network namespace; no separate published ports for the agent process.
- **Volumes**: `./data/beszel_agent_data` holds agent state (e.g. identity); `./data/beszel_data` is the hub database and keys.

## Extra disks or file systems

By default the agent sees the host disks Docker exposes. To chart specific mount points (e.g. an NFS or bind mount), uncomment and adapt a line in `compose.yml` under `beszelagent` → `volumes`:

```yaml
# - /mnt/disk/.beszel:/extra-filesystems/sda1:ro
```

Mount a **directory** from the host read-only under `/extra-filesystems/<label>`; the exact label convention is described in [Beszel’s docs](https://github.com/henrygd/beszel).

## Remote agents

This compose file runs **hub + agent on one machine**. Other hosts can run only `henrygd/beszel-agent` pointing `HUB_URL` at your hub’s reachable URL; they are not defined here.

## Layout

- `compose.yml` — services and network
- `.env.example` — template (no secrets)
- `./data/` — runtime data (gitignored in the parent repo)
