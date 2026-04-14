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
├── terminal/                 # Atuin sync server + Postgres
├── analytics/                # Your Spotify (API + web + MongoDB)
├── homepage/                 # Homepage dashboard + docker socket proxy
├── notifications/            # Gotify push notification server
├── proxy/                    # cloudflared + Nginx Proxy Manager (+ optional Tailscale)
├── dns/                      # AdGuard Home
└── systemd/                  # Optional unit files to start stacks at boot
```

---

## `media/`

```text
media/
├── compose.yml               # qBittorrent/VPN, Sonarr, Radarr, Lidarr, Bazarr, Seerr, Prowlarr, FlareSolverr, SuggestArr, deunhealth
├── .env.example
├── README.md                 # Ports, /data layout, optional NAS mounts
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
    └── suggestarr/
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
├── compose.yml               # Gotify (gotify/server)
├── .env.example
├── README.md                 # Ports, data dir, clients, Homepage widget
└── data/                     # SQLite + uploads (not committed)
    └── gotify/
```

---

## `proxy/`

```text
proxy/
├── compose.yml               # cloudflared, NPM, external Docker networks
├── .env.example
├── README.md                 # Tunnel token, hostnames
└── data/                     # NPM data, certs, tunnel state (not committed)
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

## `systemd/`

```text
systemd/
├── README.md                 # Install paths, ordering (proxy After= other stacks)
├── media.service
├── documents.service
├── monitoring.service
├── terminal.service
├── analytics.service
├── homepage.service
├── notifications.service
├── dns.service
└── proxy.service
```

Edit `WorkingDirectory=` in each unit if your clone is not at `/home/lexcode/code/homelab`.
