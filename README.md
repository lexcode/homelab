# Homelab

Personal infrastructure-as-code for Docker Compose stacks: media automation, document management, shell history sync, and lightweight host monitoring.

## Layout

| Directory | Purpose |
|-----------|---------|
| [`media/`](media/) | Servarr stack (qBittorrent over WireGuard PIA, Sonarr, Radarr, Lidarr, Bazarr, Seerr, Prowlarr, FlareSolverr, SuggestArr, deunhealth) — see **[media/README.md](media/README.md)**. |
| [`documents/`](documents/) | AI-powered document management (paperless-ngx + paperless-gpt with Ollama OCR and tagging) — see **[documents/README.md](documents/README.md)**. |
| [`monitoring/`](monitoring/) | [Beszel](https://github.com/henrygd/beszel) hub plus co-located agent — see **[monitoring/README.md](monitoring/README.md)**. |
| [`terminal/`](terminal/) | [Atuin](https://atuin.sh/) self-hosted shell history sync server — see **[terminal/README.md](terminal/README.md)**. |

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

## Documents

See **[documents/README.md](documents/README.md)** for the full setup including Ollama LAN configuration, how to generate the paperless-ngx API token, model roles, and the tag-based processing workflow.

> Ollama runs on a separate, more powerful machine on the LAN. paperless-ngx and paperless-gpt run on the server (e.g. Raspberry Pi).

Quick start:

```bash
cd documents
cp .env.example .env   # set PAPERLESS_SECRET_KEY, PAPERLESS_API_TOKEN, OLLAMA_HOST
docker compose up -d broker paperless-ngx
docker compose exec paperless-ngx python3 manage.py createsuperuser
docker compose exec paperless-ngx python3 manage.py drf_create_token <username>
# paste token into .env, then:
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

## Terminal

See **[terminal/README.md](terminal/README.md)** for Atuin sync server setup, Postgres notes, and how to point shell clients at this server.

Quick start:

```bash
cd terminal
cp .env.example .env   # set ATUIN_DB_NAME, ATUIN_DB_USERNAME, ATUIN_DB_PASSWORD
docker compose up -d
```

## Secrets and git

Do not commit real `.env` files or credentials. Runtime database and agent state under `media/data`, `documents/data`, `monitoring/data`, `terminal/database`, and similar paths are intended to stay local.
