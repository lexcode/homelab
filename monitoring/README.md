# Monitoring (Beszel + Dozzle)

Docker Compose stack combining:

- [**Beszel**](https://github.com/henrygd/beszel) — lightweight hub for system metrics and alerts, with a local agent reporting CPU, memory, disk, and Docker containers.
- [**Dozzle**](https://dozzle.dev) — real-time log viewer for Docker containers, with multi-host support via agents.

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

| Variable              | Purpose                                                                                                                                                                                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MONITORING_SUBNET`   | Docker bridge CIDR for `monitoringnetwork`. Must match `BESZEL_IP`.                                                                                                                                                                                                   |
| `BESZEL_IP`           | Static IPv4 for the `beszel` container on `monitoringnetwork`.                                                                                                                                                                                                        |
| `BESZEL_PORT`         | Host port published for the web UI (default `8090`).                                                                                                                                                                                                                  |
| `BESZEL_URL`          | Public URL you use to open Beszel (e.g. `http://localhost:8090` or `https://beszel.example.com`). Passed to the agent as `HUB_URL` and used by the hub as `APP_URL`. **Use the same scheme/host/port you actually browse to**, or the agent may not connect reliably. |
| `BESZEL_LOG_LEVEL`    | Hub log level (default `info`).                                                                                                                                                                                                                                       |
| `BESZEL_AGENT_KEY`    | Agent key from the Beszel UI (SSH-style line).                                                                                                                                                                                                                        |
| `BESZEL_AGENT_TOKEN`  | Agent token from the Beszel UI. **This token is unique per registered system** — remote machines each need their own token from the hub.                                                                                                                              |
| `BESZEL_AGENT_LISTEN` | Agent listen port (default `45876`); traffic reaches the agent via `network_mode: service:beszel`.                                                                                                                                                                    |
| `DOZZLE_IP`           | Static IPv4 for the `dozzle` container on `monitoringnetwork`.                                                                                                                                                                                                        |
| `DOZZLE_HOSTNAME`     | Display name for this machine in the Dozzle UI (e.g. `omarchy`). Shared by both `dozzle` and `dozzle-agent`.                                                                                                                                                          |
| `DOZZLE_REMOTE_AGENT` | Comma-separated `host:7007` addresses of **other** machines running `dozzle-agent`. Do not include this machine's own IP.                                                                                                                                             |

`.env.example` also lists `BESZEL_AGENT_LOG_LEVEL`; the current `compose.yml` does not pass it into the agent—add an `environment` entry there if the image documents support for it.

`.env.example` uses placeholder key/token; replace them with values from your hub.

## Architecture (this repo)

- **`beszel`**: Hub UI + API, data in `./data/beszel_data`.
- **`beszelagent`**: `network_mode: service:beszel` so the agent shares the hub's network namespace; no separate published ports for the agent process.
- **`dozzle`**: Log viewer UI on port `8181`, connects to remote agents via `DOZZLE_REMOTE_AGENT`.
- **`dozzle-agent`**: Exposes this machine's Docker socket to other Dozzle UIs on port `7007`.
- **Volumes**: `./data/beszel_agent_data` holds agent state; `./data/beszel_data` is the hub database and keys; `./data/dozzle_data` holds Dozzle session and auth data.

## Extra disks or file systems

By default the agent sees the host disks Docker exposes. To chart specific mount points (e.g. an NFS or bind mount), uncomment and adapt a line in `compose.yml` under `beszelagent` → `volumes`:

```yaml
# - /mnt/disk/.beszel:/extra-filesystems/sda1:ro
```

Mount a **directory** from the host read-only under `/extra-filesystems/<label>`; the exact label convention is described in [Beszel's docs](https://github.com/henrygd/beszel).

## Remote Beszel agents

This compose file runs **hub + agent on one machine**. Other hosts can run only `henrygd/beszel-agent` pointing `HUB_URL` at your hub's reachable URL; they are not defined here. Each remote machine needs its own token — in the Beszel UI go to **Systems → Add System**, copy the token shown, and set it as `TOKEN` in the agent's environment on that machine. The same `KEY` from this machine's `.env` is reused across all agents.

## Dozzle

This compose runs **two Dozzle services per machine**:

- **`dozzle`** — the web UI (port `8181`). Mounts the local Docker socket and connects to remote agents via `DOZZLE_REMOTE_AGENT`.
- **`dozzle-agent`** — exposes this machine's Docker socket to other Dozzle UIs on port `7007`.

This means the same `compose.yml` can be deployed on **multiple machines** (e.g. PC + Raspberry Pi). Each instance shows its own containers plus any remote agents you point it at.

### Multi-machine setup

On **each machine** running this compose, set in `.env`:

| Variable              | Description                                                                                                         |
| --------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `DOZZLE_HOSTNAME`     | Display name shown in the UI for this machine (e.g. `omarchy`, `raspberry-pi`).                                     |
| `DOZZLE_REMOTE_AGENT` | Comma-separated `host:7007` list of **other** machines running `dozzle-agent`. Never include this machine's own IP. |

Example `.env` values per machine:

```
# On PC (Omarchy)
DOZZLE_HOSTNAME=omarchy
DOZZLE_REMOTE_AGENT=192.168.0.x:7007,192.168.0.x:7007

# On Raspberry Pi
DOZZLE_HOSTNAME=raspberry-pi
DOZZLE_REMOTE_AGENT=192.168.0.x:7007,192.168.0.x:7007
```

### Machines not running this compose (e.g. Unraid)

For machines that manage Docker through their own app library, run only the agent:

```bash
docker run -d \
  --name dozzle-agent \
  --restart unless-stopped \
  -e DOZZLE_HOSTNAME=unraid \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -p 7007:7007 \
  amir20/dozzle:latest agent
```

Then add that machine's IP to `DOZZLE_REMOTE_AGENT` on the machines running the full compose.

## Layout

- `compose.yml` — services and network
- `.env.example` — template (no secrets)
- `./data/` — runtime data (gitignored in the parent repo)
