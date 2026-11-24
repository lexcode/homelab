# Audiobookshelf

[**Audiobookshelf**](https://github.com/advplyr/audiobookshelf) is a
self-hosted audiobook, ebook and podcast server: it streams your library,
keeps progress per user, and can write metadata and covers into the library.
The official image supports `linux/arm64`, so it runs on the Raspberry Pi 5.

**This stack runs on the Raspberry Pi 5 Docker host**, the same host as
[`media/`](../media/README.md) and [`dns/`](../dns/README.md). The published
image is pulled from GHCR; nothing is built locally. It is deliberately a
separate stack from `media/`: Audiobookshelf is a library server, not an *arr
app, and it needs neither the VPN namespace nor the Servarr network.

It is routed by the existing Traefik stack at **`https://audio.lexcode.dev`**
and is **LAN-only by design**: there is no Cloudflare Tunnel hostname and no
`cloudflare` entrypoint router. The `*.lexcode.dev` LAN DNS record and the
existing DNS-01 wildcard certificate cover the hostname, so no extra DNS or
certificate work is needed.

## Files

- `compose.yml` — the `ghcr.io/advplyr/audiobookshelf` service, its own
  `audiobookshelfnetwork`, Traefik labels and a health check.
- `.env.example` — host port, bridge subnet, owner UID/GID, time zone and the
  three library paths.
- `data/audiobookshelf/` — `config/` and `metadata/` at runtime (not committed).

## Prerequisites

- Docker and Docker Compose v2 on the Pi
- LAN DNS resolving `*.lexcode.dev` to the Traefik host
- An audiobook library path on the Pi (and optionally ebook and podcast
  paths)
- The [`proxy/`](../proxy/README.md) stack running **after** this stack, so
  Traefik can join `audiobookshelfnetwork`

## First deployment

1. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Set `PUID`/`PGID` to the owner of the library, and point
   `AUDIOBOOKSHELF_AUDIOBOOKS_DIR` / `AUDIOBOOKSHELF_EBOOKS_DIR` /
   `AUDIOBOOKSHELF_PODCASTS_DIR` at the real host paths. All must exist before
   the first start; for a library type you do not use, create an empty folder
   rather than letting Docker create one as root.

2. **Create the state directories and mount the library.** The container runs
   as `PUID:PGID`, so it can only write where that user can:

   ```bash
   mkdir -p data/audiobookshelf/config data/audiobookshelf/metadata
   sudo chown -R 1000:1000 data/audiobookshelf
   ```

   The library is read and, when *Store metadata with item* is enabled,
   written by Audiobookshelf. Make sure `PUID`/`PGID` can read every file and
   write the folders it needs to update. On the reference host `/data` is a
   tree of CIFS mounts from the NAS; mount the audiobook share there (or point
   the variable at wherever it is mounted) as described in
   [`media/README.md`](../media/README.md#optional-remote-nas-for-movies-and-tv-persistent-cifs-mounts).

3. **Validate, then start this stack before the proxy** so it creates its
   Docker network:

   ```bash
   docker compose --env-file .env.example config --quiet
   docker compose up -d

   cd ../proxy
   docker compose up -d
   ```

4. **Open `https://audio.lexcode.dev`** (or `http://<pi-lan-ip>:13378` while
   testing the published port) and create the first account, which becomes the
   administrator. Add a library pointing at `/audiobooks` (and, if mounted,
   an ebook library at `/ebooks` and a podcast library at `/podcasts`).

5. **Configure the libraries in the UI** — folder structure, metadata
   providers, and whether metadata/covers are written into the library. Those
   settings live in `data/audiobookshelf/config` and are not environment
   variables.

## Ports and paths

| Item                | Default                              | Notes                                            |
| ------------------- | ------------------------------------ | ------------------------------------------------ |
| Host port           | `13378`                              | `AUDIOBOOKSHELF_PORT`; container listens on `80` |
| Traefik route       | `https://audio.lexcode.dev`          | LAN-only, `websecure` + wildcard certificate     |
| Audiobook library   | `/data/audiobooks` → `/audiobooks`   | `AUDIOBOOKSHELF_AUDIOBOOKS_DIR`                  |
| Ebook library       | `/data/ebooks` → `/ebooks`           | `AUDIOBOOKSHELF_EBOOKS_DIR`                      |
| Podcast library     | `/data/podcasts` → `/podcasts`       | `AUDIOBOOKSHELF_PODCASTS_DIR`                    |
| Config + SQLite     | `./data/audiobookshelf/config`       | `/config`; keep on local disk                    |
| Metadata / covers   | `./data/audiobookshelf/metadata`     | `/metadata`; keep on local disk                  |
| Docker bridge       | `172.39.10.0/24`                     | `AUDIOBOOKSHELF_SUBNET`                          |

The host port is published for direct LAN access, matching the other media
apps. Traefik ignores it and reaches the container over
`audiobookshelfnetwork`.

## Routing and access

Traefik discovers the route from the `traefik.*` labels in `compose.yml`
(Docker provider, `exposedByDefault=false`), using the normal `websecure`
entrypoint and the `letsencrypt` resolver.

This hostname is intentionally **not** in Cloudflare Zero Trust → Tunnels →
Public Hostnames. Audiobookshelf streams audio, and it should stay on the LAN
like the rest of the library apps. If remote access is ever needed, use a
private tailnet or a VPN rather than publishing it through Cloudflare.

## Backup and recovery

Back up both local state directories together:

- `data/audiobookshelf/config` — `absdatabase.sqlite`, settings and the
  generated secrets. Losing it loses users, listening progress and library
  definitions.
- `data/audiobookshelf/metadata` — downloaded covers and extracted metadata.

The media files are separate: they live wherever the `AUDIOBOOKSHELF_*_DIR`
paths point and are not copied by backing up this stack. Stop the container
before copying the SQLite database, or use SQLite's online backup, so the
snapshot is consistent:

```bash
docker compose stop audiobookshelf
tar -czf audiobookshelf-config-$(date +%F).tar.gz data/audiobookshelf
docker compose start audiobookshelf
```

## Updating

The image floats on `latest`, matching the rest of the repository. Update
deliberately and back up `config/` first:

```bash
docker compose pull
docker compose up -d
```

Audiobookshelf migrations run inside the container on start. If a rollback
might be needed, keep the pre-update `config/` copy until the new version has
been checked.

## Boot with systemd (optional)

```bash
sudo cp ../systemd/audiobookshelf.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now audiobookshelf.service
```

The stack owns `audiobookshelfnetwork`; `proxy.service` is ordered after
`audiobookshelf.service` so Traefik can join it. See
[`systemd/README.md`](../systemd/README.md).

## Operations

```bash
# Read-only container health/status from the repository root
bash scripts/status.sh audiobookshelf

# Logs
docker compose logs -f audiobookshelf
```

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Traefik returns `502` / `404` for `audio.lexcode.dev` | The proxy has not joined `audiobookshelfnetwork`, or the container is not running. Start this stack first, then `proxy/`. |
| `permission denied` writing covers or metadata | `PUID`/`PGID` do not match the owner of the library or `data/audiobookshelf`. Fix ownership, then restart. |
| Empty library even though files exist | The library folder was added as `/audiobooks`, `/ebooks` or `/podcasts` and the host path is wrong/empty. Check the bind mount with `docker compose config` and `docker compose exec audiobookshelf ls /audiobooks`. |
| Container exits on start with a port error | Another process uses `AUDIOBOOKSHELF_PORT` on the host. Change the host side in `.env`; the container side stays `80`. |

## Layout

```text
audiobookshelf/
├── compose.yml               # Audiobookshelf service, network, Traefik labels, health check
├── .env.example
├── README.md
└── data/                     # Not committed
    └── audiobookshelf/
        ├── config/           # SQLite DB, settings, generated secrets
        └── metadata/         # Covers and extracted metadata
```
