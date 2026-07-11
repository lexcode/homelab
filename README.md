# Homelab

Personal infrastructure-as-code for Docker Compose stacks: media automation, document management, shell history sync, lightweight host monitoring, container management, analytics, push notifications (Gotify and optional iGotify assistant for iOS), web-change monitoring (changedetection.io), DNS-level ad blocking, and a self-hosted dashboard.

```mermaid
flowchart LR
    subgraph docs["📄  documents/"]
        pngx[paperless-ngx :8001]
        pai[paperless-ai :3001]
        pgpt[paperless-gpt :8811]
        pg[(postgres)]
        rd[(redis broker)]
    end
    subgraph med["🎬  media/"]
        qbt[qBittorrent :8080 via WireGuard]
        prowlarr[Prowlarr :9696 via WireGuard]
        flare[FlareSolverr :8191 via WireGuard]
        sonarr[Sonarr :8989]
        radarr[Radarr :7878]
        lidarr[Lidarr :8686]
        bazarr[Bazarr :6767]
        seerr[Seerr :5055]
        suggestarr[SuggestArr :5000]
    end
    subgraph mon["📊  monitoring/"]
        beszel[Beszel :8090]
        dozzle[Dozzle :8181]
        beszelagent[beszel-agent]
    end
    subgraph mgmt["🐳  management/"]
        dockge[Dockge :5002]
    end
    subgraph ana["📈  analytics/"]
        yss[your_spotify_server :8080]
        ysc[your_spotify_client :3000]
        ysm[(mongo)]
    end
    subgraph term["💻  terminal/"]
        atuin[Atuin :8888]
        atuinpg[(postgres)]
        atuinbkp[/db backup/]
    end
    subgraph home["🏠  homepage/"]
        hp[Homepage :3003]
        dp[dockerproxy :2375]
    end
    subgraph dns["🛡️  dns/"]
        ag[AdGuard Home :3005]
    end
    subgraph notif["🔔 notifications/"]
        gotify[Gotify :8688]
        igotify[iGotify :8681]
        cd[changedetection :5001]
    end
    cf[☁️  proxy/cloudflared]
    ts[🔗 proxy/tailscale-funnel]
    npm[proxy/nginx-proxy-manager]
    subgraph desktop["🖥️  Desktop (LAN)"]
        ollama[Ollama :11434]
    end
    pai -- LAN --> ollama
    pgpt -- LAN --> ollama
    cf -- tunnel --> npm
    ts -- funnel --> npm
    npm -- HTTP --> hp
    npm -- HTTP --> ysc
```

## Layout

See **[docs/STRUCTURE.md](docs/STRUCTURE.md)** for a directory tree of the whole repo and each stack (compose files, `data/`, systemd units).

| Directory                    | Purpose                                                                                                                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`media/`](media/)           | Servarr stack (qBittorrent over WireGuard PIA, Sonarr, Radarr, Lidarr, Bazarr, Seerr, Prowlarr, FlareSolverr, SuggestArr, deunhealth) — see **[media/README.md](media/README.md)**. |
| [`documents/`](documents/)   | AI-powered document management (paperless-ngx + paperless-gpt with Ollama OCR and tagging) — see **[documents/README.md](documents/README.md)**.                                    |
| [`monitoring/`](monitoring/) | [Beszel](https://github.com/henrygd/beszel) hub plus co-located agent — see **[monitoring/README.md](monitoring/README.md)**.                                                       |
| [`management/`](management/) | [Dockge](https://github.com/louislam/dockge) Compose stack manager with click-to-update workflows — see **[management/README.md](management/README.md)**. |
| [`terminal/`](terminal/)     | [Atuin](https://atuin.sh/) self-hosted shell history sync server — see **[terminal/README.md](terminal/README.md)**.                                                                |
| [`analytics/`](analytics/)   | [Your Spotify](https://github.com/Yooooomi/your_spotify) self-hosted Spotify listening statistics — see **[analytics/README.md](analytics/README.md)**.                             |
| [`homepage/`](homepage/)     | [Homepage](https://gethomepage.dev) self-hosted dashboard with service widgets and Docker integration — see **[homepage/README.md](homepage/README.md)**.                           |
| [`notifications/`](notifications/) | [Gotify](https://gotify.net/) plus optional [iGotify assistant](https://github.com/androidseb25/iGotify-Notification-Assistent) for iOS push, and [changedetection.io](https://github.com/dgtlmoon/changedetection.io) for web-page change monitoring — see **[notifications/README.md](notifications/README.md)**. |
| [`proxy/`](proxy/)           | [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared) + Nginx Proxy Manager + optional [Tailscale Funnel](https://tailscale.com/kb/1223/funnel) for video/high-bandwidth services — see **[proxy/README.md](proxy/README.md)**.                                                  |
| [`dns/`](dns/)               | LAN DNS / filtering ([AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)) — **primary** on Raspberry Pi 5, **secondary** on Unraid; DHCP DNS via **UniFi Dream Machine Pro** — see **[dns/README.md](dns/README.md)**. |
| [`systemd/`](systemd/)       | Optional systemd units to start each stack at boot — see **Boot with systemd** below.                                                                                               |

Each stack owns its `compose.yml`, `.env.example`, and runtime data under `./data/` (not committed).

## Requirements

- Docker and Docker Compose v2
- Separate `.env` files per stack (copy from each `.env.example`)

Networks are isolated by design (for example media on `172.39.0.0/24`, monitoring on `172.39.1.0/24`, analytics on `172.39.2.0/24`, AdGuard Home on `172.39.5.0/24`, and management on `172.39.8.0/24`). Adjust subnets in `.env` if they clash with your LAN or other projects.

## Validate configuration

Run the repository-wide validation gate to validate every stack from its committed `.env.example` without starting containers or printing rendered configuration. It reports one pass or fail per stack and exits non-zero when any Compose configuration is invalid.

```bash
bash scripts/validate.sh
```

Use `bash scripts/validate.sh --list` to show the discovered stack directories.

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

## Container management

See **[management/README.md](management/README.md)** for Dockge setup, stack discovery, update guidance, reverse-proxy configuration, and Docker socket security considerations.

Quick start:

```bash
cd management
cp .env.example .env   # set HOMELAB_ROOT to this repository's absolute host path
mkdir -p data/dockge
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

## Analytics

See **[analytics/README.md](analytics/README.md)** for Spotify developer app setup, Cloudflare Tunnel configuration, DNS notes, and ARM/Raspberry Pi specifics.

Quick start:

```bash
cd analytics
cp .env.example .env   # set YOUR_SPOTIFY_API_ENDPOINT, YOUR_SPOTIFY_CLIENT_ENDPOINT, SPOTIFY_PUBLIC, SPOTIFY_SECRET
docker compose up -d
```

## Homepage

See **[homepage/README.md](homepage/README.md)** for config file layout, Docker integration via dockerproxy, background image setup, and service widget variables.

Quick start:

```bash
cd homepage
cp .env.example .env   # set HOMEPAGE_ALLOWED_HOSTS and service URLs/keys
docker compose up -d
```

## Notifications (Gotify + iGotify)

See **[notifications/README.md](notifications/README.md)** for ports, persistent data under `./data/gotify`, `./data/igotify`, and `./data/changedetection`, iOS assistant env vars, clients, and *arr Connect.

Quick start:

```bash
cd notifications
cp .env.example .env   # set GOTIFY_DEFAULTUSER_PASS; for Local iGotify set GOTIFY_* / SECNTFY_* per README
docker compose up -d
```

## Proxy

See **[proxy/README.md](proxy/README.md)** for Cloudflare Tunnel setup, adding public hostnames, and the optional [Tailscale Funnel](proxy/README.md#tailscale-funnel-optional) sidecar for publicly exposing a single service (for example Jellyfin) outside the Cloudflare CDN — Cloudflare’s terms prohibit proxying video.

Quick start:

```bash
cd proxy
cp .env.example .env   # set CLOUDFLARED_TOKEN; TS_AUTHKEY only if using Tailscale Funnel
docker compose up -d
```

This starts Cloudflare Tunnel and Nginx Proxy Manager only. After configuring
the optional variables, enable [Tailscale Funnel](proxy/README.md#tailscale-funnel-optional)
with `docker compose --profile tailscale up -d`.

## DNS (AdGuard Home)

See **[dns/README.md](dns/README.md)** for bridge networking, port defaults vs NPM, systemd-resolved, and **UniFi DMP** DHCP DNS (**primary** = Pi `dns/` stack, **secondary** = Unraid AdGuard).

Quick start:

```bash
cd dns
cp .env.example .env   # adjust ADGUARD_DNS_PORT / ADGUARD_HTTP_PORT if needed
docker compose up -d
```

## Boot with systemd (optional)

Unit files live in [`systemd/`](systemd/). They run each stack with `docker compose up` from the matching directory and are suitable for enabling stacks at boot on a single host.

The default `proxy.service` startup excludes the optional Tailscale Funnel
profile.

**Install (paths assume this repo at `/home/lexcode/code/homelab`; edit the unit files if your clone lives elsewhere):**

```bash
sudo cp systemd/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now media.service documents.service monitoring.service management.service analytics.service terminal.service homepage.service notifications.service dns.service proxy.service
```

**Why `proxy.service` lists other stacks in `After=`:** The proxy stack includes [Nginx Proxy Manager](https://nginxproxymanager.com/) joined to **external** Docker networks (`servarrnetwork`, `documentsnetwork`, etc.). Those networks are created when each respective `docker compose` stack starts. If `proxy.service` runs first, Compose fails with “network … not found.” So the proxy unit must start **after** every stack that defines those named networks.

Order is encoded only in `proxy.service`; other units only need `After=docker.service` and `Requires=docker.service`.

**`Requires=` vs `After=`:** Other stacks do not use `Requires=` on each other so one failing service does not block Docker or unrelated stacks. Only `proxy` needs strict ordering relative to the stacks whose networks it imports.

## Secrets and git

Do not commit real `.env` files or credentials. Never put tunnel tokens, API keys, or passwords in `compose.yml` comments. Runtime database and agent state under `media/data`, `documents/data`, `monitoring/data`, `management/data`, `terminal/data`, `analytics/data`, `notifications/data`, `dns/data`, and similar paths are intended to stay local.

`.cursor/` is listed in `.gitignore` so editor-specific rules stay on your machine and are not shared via the repo; remove that line if you intentionally want to version Cursor project config.
