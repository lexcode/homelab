# Repository layout

This document uses the same style as common monorepo README trees: **what lives where**, with short comments. Runtime state under `*/data/` is usually **not** committed (see `.gitignore`); paths shown are the intended layout after `docker compose up`.

---

## Whole project (`homelab/`)

```text
homelab/
├── README.md                 # Top-level overview, quick starts, systemd notes
├── .gitignore
├── docs/
│   └── STRUCTURE.md          # This file
├── media/                    # Servarr + VPN + *arr stack
├── documents/                # paperless-ngx, AI helpers, broker, DBs
├── monitoring/               # Beszel hub + agent, Dozzle
├── management/               # Dockge Compose stack manager
├── terminal/                 # Atuin sync server + Postgres
├── analytics/                # Your Spotify (API + web + MongoDB)
├── homepage/                 # Homepage dashboard + docker socket proxy
├── notifications/            # Gotify, iGotify assistant, changedetection.io
├── resonarr/                 # Resonarr API and persistent download worker
├── ai/
│   └── ai-memory/            # Shared coding-agent memory server
├── proxy/                    # cloudflared + Nginx Proxy Manager (+ optional Tailscale)
├── dns/                      # AdGuard Home
└── systemd/                  # Optional unit files to start stacks at boot
```

---

## `media/`

```text
media/
├── compose.yml               # qBittorrent/VPN, Sonarr, Radarr, Lidarr, Bazarr, Seerr, Prowlarr, FlareSolverr, SuggestArr, Beets, deunhealth
├── .env.example
├── README.md                 # Ports, /data layout, optional NAS mounts, Beets workflow
├── beets/                    # Beets image and config (committed)
│   ├── Dockerfile            # beets + fpcalc + flac; idle container, manual imports only
│   ├── config.yaml           # Mounted read-only at /config/config.yaml
│   └── beet.sh               # Wrapper for the common `docker compose exec beets` commands
└── data/                     # Per-app config (not committed); create dirs before first run — see media/README.md
    ├── pia/
    ├── pia-shared/
    ├── qbittorrent/
    ├── sonarr/
    ├── radarr/
    ├── lidarr/
    ├── bazarr/
    ├── seerr/
    ├── prowlarr/
    ├── suggestarr/
    └── beets/                # library.db, import.log
```

Host media libraries and downloads are expected under **`/data`** on the machine (bind mounts), as described in **media/README.md**.

---

## `documents/`

```text
documents/
├── compose.yml               # paperless-ngx, paperless-ai, paperless-gpt, broker, Redis, Postgres
├── .env.example
├── README.md                 # Ollama LAN, API token, tagging workflow
└── data/                     # DB volumes, app data (not committed)
```

---

## `monitoring/`

```text
monitoring/
├── compose.yml               # Beszel hub, Beszel agent, Dozzle
├── .env.example
├── README.md                 # Keys, mounts, remote agents
└── data/                     # Hub/agent state (not committed)
```

---

## `management/`

```text
management/
├── compose.yml               # Dockge UI and management network
├── .env.example
├── README.md                 # Setup, updates, proxying, and security guidance
└── data/
    └── dockge/               # Dockge settings (not committed)
```

Dockge mounts this repository at the same absolute host/container path and mounts the Docker socket with write access so it can manage the existing Compose stacks.

---

## `terminal/`

```text
terminal/
├── compose.yml               # Atuin server + Postgres + daily backups
├── .env.example
├── README.md                 # Client configuration
└── data/                     # Not committed
    ├── config/               # Atuin server config
    ├── database/             # Postgres data (PG 18+ layout under cluster dir)
    └── db_dumps/             # Backup images from postgres-backup-local
```

---

## `analytics/`

```text
analytics/
├── compose.yml               # your_spotify server + client + MongoDB
├── .env.example
├── README.md                 # Spotify app, tunnel, ARM notes
└── data/                     # MongoDB and app data (not committed)
```

---

## `homepage/`

```text
homepage/
├── compose.yml               # Homepage + Docker Socket Proxy
├── .env.example
├── README.md                 # Widget env vars, dockerproxy
└── data/
    └── homepage/
        ├── config/           # Dashboard YAML/JS/CSS (some files committed as templates)
        │   ├── settings.yaml
        │   ├── services.yaml
        │   ├── widgets.yaml
        │   ├── bookmarks.yaml
        │   ├── docker.yaml
        │   ├── kubernetes.yaml
        │   ├── proxmox.yaml
        │   ├── custom.js
        │   └── custom.css
        └── images/           # Background assets referenced from settings
```

Secrets belong in **`.env`** via `HOMEPAGE_VAR_*`; keep tokens out of committed YAML when possible.

---

## `notifications/`

```text
notifications/
├── compose.yml               # Gotify, iGotify assistant, changedetection.io (notificationsnetwork)
├── .env.example
├── README.md                 # Ports, data dir, clients, Homepage widget
└── data/                     # Per-service state (not committed)
    ├── gotify/
    ├── igotify/
    └── changedetection/
```

---

## `ai/ai-memory/`

```text
ai/
└── ai-memory/
    ├── compose.yml           # ai-memory server (aimemorynetwork)
    ├── .env.example
    ├── README.md             # Pi setup, migration, and client configuration
    └── data/                 # Wiki, database, logs, and other state (not committed)
```

---

## `proxy/`

```text
proxy/
├── compose.yml               # cloudflared, traefik, optional tailscale-funnel, external Docker networks
├── .env.example
├── README.md                 # Tunnel token, hostnames, Tailscale Funnel setup, routing model
├── config/
│   ├── traefik/
│   │   └── dynamic/
│   │       └── external.yml  # static routes for external-routed (non-Docker) backends (committed)
│   └── tailscale-funnel/
│       └── serve.json        # Tailscale Serve/Funnel config (committed template)
└── data/                     # Traefik certs, tunnel and tailscale state (not committed)
    ├── traefik/
    ├── nginx-proxy-manager/  # former NPM data, left as rollback insurance
    └── tailscale-funnel/
```

---

## `dns/`

```text
dns/
├── compose.yml               # AdGuard Home
├── .env.example
├── README.md                 # Ports, DHCP/DNS, UniFi notes
└── data/                     # AdGuard workdir (not committed)
```

---

## `resonarr/`

```text
resonarr/
├── compose.yml               # API behind Traefik plus a private queue worker
├── .env.example              # GHCR image pin, Spotify, auth, frontend-origin configuration
├── README.md                 # First deployment, OAuth, updates, rollback, backups
├── data/                     # SQLite state (not committed)
└── downloads-staging/        # Incomplete worker output (not committed)
```

The permanent music library is a host bind mount configured by
`RESONARR_MUSIC_HOST_PATH`; Resonarr finalizes completed files directly there.

---

## `systemd/`

```text
systemd/
├── README.md                 # Install paths, ordering (proxy After= other stacks)
├── media.service
├── documents.service
├── monitoring.service
├── management.service
├── terminal.service
├── analytics.service
├── homepage.service
├── notifications.service
├── dns.service
├── ai-memory.service
├── resonarr.service
└── proxy.service
```

Edit `WorkingDirectory=` in each unit if your clone is not at `/home/lexcode/git/homelab`.
