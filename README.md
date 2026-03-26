# Homelab

Personal infrastructure-as-code for Docker Compose stacks: media automation (*arr, VPN, torrent client) and lightweight host monitoring.

## Layout

| Directory | Purpose |
|-----------|---------|
| [`media/`](media/) | Servarr stack (qBittorrent over WireGuard PIA, Sonarr, Radarr, Lidarr, Bazarr, Seerr, Prowlarr, FlareSolverr, SuggestArr, deunhealth) — see **[media/README.md](media/README.md)**. |
| [`monitoring/`](monitoring/) | [Beszel](https://github.com/henrygd/beszel) hub plus co-located agent — see **[monitoring/README.md](monitoring/README.md)**. |

Each stack owns its `compose.yml`, `.env.example`, and runtime data under `./data/` (not committed).

## Requirements

- Docker and Docker Compose v2
- Separate `.env` files per stack (copy from each `.env.example`)

Networks are isolated by design (for example media on `172.39.0.0/24`, monitoring on `172.39.1.0/24`). Adjust subnets in `.env` if they clash with your LAN or other projects.

## Media

See **[media/README.md](media/README.md)** for environment variables, ports, qBittorrent/VPN notes, an **example `/data` directory tree** (libraries and download folders), and **optional persistent CIFS mounts** when movies and TV live on a remote NAS under `/data`.

Quick start:

```bash
cd media
cp .env.example .env   # edit with your secrets and LAN/VPN settings
docker compose up -d
```

## Monitoring

See **[monitoring/README.md](monitoring/README.md)** for Beszel hub and agent setup, environment variables, extra filesystem mounts, and remote agents.

Quick start:

```bash
cd monitoring
cp .env.example .env   # set BESZEL_URL; add BESZEL_AGENT_KEY / TOKEN from the UI after first visit
docker compose up -d
```

## Secrets and git

Do not commit real `.env` files or credentials. Runtime database and agent state under `media/data`, `monitoring/data`, and similar paths are intended to stay local.
