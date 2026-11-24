---
name: arr-media-stack
description: Operate and troubleshoot the media/ stack in this repo — Radarr, Sonarr, Lidarr, Chaptarr, Prowlarr, Bazarr, Seerr, qBittorrent behind the PIA WireGuard container, FlareSolverr, slskd (Soulseek), Maintainerr, SuggestArr, Beets. Use when adding media, checking stack health, queues or history, diagnosing failed imports, stalled torrents, empty search results, missing subtitles, missing audiobooks, missing individual songs, or VPN and network problems in this stack.
---

# Arr media stack

`media/` is one Compose stack: the \*arr services plus a qBittorrent that has no network of its own, because it runs inside the VPN container's namespace. Libraries and downloads are CIFS shares of two NAS boxes, bind-mounted under `/data`. `media/README.md` holds the remediation prose; this file is the working model.

Run Compose commands from `media/`: `cd media && docker compose <cmd>`. The stack runs on `rasp5-1` at `192.168.0.24` — the live clone is `/home/lexcode/git/homelab`, and that is the only `media/data` whose keys authenticate.

## Ground rules

- Read freely. `POST`, `PUT` and `DELETE` change state — searches, imports, queue entries, deleted files. Explain the call and its blast radius, then get approval.
- Read an API key into a variable, never into output: `KEY=$(grep -oP '(?<=<ApiKey>)[^<]+' media/data/radarr/config.xml)`. Do not echo it, log it, or paste it into a README, issue or commit.
- Deletions with `deleteFiles=true`, queue removal and blocklist writes destroy real media files. Treat them as needing explicit approval for the specific items.
- Library-wide search commands (`MissingMoviesSearch`, `CutoffUnmetMoviesSearch`) hit every indexer at once. Scope to ids instead unless the bulk run is what was asked for.

## Addressing and API versions

| Service | Container | Host port | From other containers on `servarrnetwork` | API |
| --- | --- | --- | --- | --- |
| Radarr | `radarr` | 7878 | `http://radarr:7878` | `/api/v3` |
| Sonarr | `sonarr` | 8989 | `http://sonarr:8989` | `/api/v3` |
| Lidarr | `lidarr` | 8686 | `http://lidarr:8686` | **`/api/v1`** |
| Chaptarr | `chaptarr` | 8789 | `http://chaptarr:8789` | **`/api/v1`** |
| Prowlarr | `prowlarr` | 9696 | `http://172.39.0.2:9696` | `/api/v1` |
| qBittorrent | `qbittorrent` | 8080 | `http://172.39.0.2:8080` | `/api/v2` |
| FlareSolverr | `flaresolverr` | 8191 | `http://172.39.0.2:8191` (loopback from Prowlarr) | `POST /v1` |
| slskd | `slskd` | 5030 | `http://172.39.0.2:5030` | `/api/v0` |
| Bazarr | `bazarr` | 6767 | `http://bazarr:6767` | `/api` (no version) |
| Seerr | `seerr` | 5055 | `http://seerr:5055` | `/api/v1` |
| Maintainerr | `maintainerr` | 6246 | `http://maintainerr:6246` | none stable |
| SuggestArr | `suggestarr` | 5000 | `http://192.168.0.24:5000` | `network_mode: host` |
| Beets | `beets` | — | — | no daemon; `docker compose exec beets` |

Lidarr is the trap: it never moved to v3, so `/api/v3/...` returns `404` while everything else answers. A version mismatch looks like a missing endpoint, not an auth error. Chaptarr is the same — it inherits Readarr's v1 API, and its entity is `book`/`author` rather than `book`/`series`.

`prowlarr`, `qbittorrent`, `flaresolverr` and `slskd` carry `network_mode: service:vpn` — they share the VPN container's namespace, have no address of their own, and are unreachable by container name. `172.39.0.2` is `VPN_IP`; from inside that namespace `127.0.0.1` is the same machine. Container-name DNS (`http://flaresolverr:8191`) resolves to nothing.

Their Traefik labels live on the `vpn` container for the same reason, each router declaring its own port.

LAN hostnames are `<app>.lexcode.dev`; only Seerr is routed publicly, through the `cloudflare` entrypoint.

## API keys

| Service | Key location | Header |
| --- | --- | --- |
| Radarr / Sonarr / Lidarr / Chaptarr / Prowlarr | `media/data/<app>/config.xml` → `<ApiKey>` | `X-Api-Key` |
| Bazarr | `media/data/bazarr/config/config.yaml` → `auth.apikey` | `X-API-KEY` |
| Seerr | `media/data/seerr/settings.json` → `main.apiKey` | `X-Api-Key` |
| qBittorrent | username/password only, stored as `WebUI\Username` + a PBKDF2 hash that cannot be read back | cookie |
| slskd | `SLSKD_USERNAME`/`SLSKD_PASSWORD` in `.env` for the UI; API keys are created in the UI and land in `media/data/slskd/slskd.yml` | `X-API-Key` |

Keys are per-installation: a key from a checkout that is not the running host returns `401` even though the file looks right. `GET /api/v3/system/status` returning `200` is the proof the key is live.

## Triage ladder

Work down and stop at the first rung that fails — everything below inherits the fault.

1. **Container state.** `bash scripts/status.sh media` from the repo root, then `cd media && docker compose ps`. Only `vpn`, `qbittorrent`, `seerr`, `maintainerr` and `deunhealth` have healthchecks; `running no-healthcheck` on the rest says nothing about whether the app works. Done when every service is running and nothing is restarting.
2. **App liveness without credentials** — separates a dead app from a bad key:
   ```bash
   H=192.168.0.24
   curl -s "http://$H:7878/ping" "http://$H:8989/ping" "http://$H:8686/ping" "http://$H:9696/ping"   # {"status":"OK"}
   curl -s -o /dev/null -w '%{http_code}\n' "http://$H:6767/"                                        # 200 = Bazarr
   curl -s "http://$H:5055/api/v1/status"                                                            # public
   curl -s -X POST -H 'Content-Type: application/json' -d '{"cmd":"sessions.list"}' "http://$H:8191/v1"
   ```
   A `000` here is the container or its published port, not the key.
3. **App state.** [`API-REFERENCE.md`](API-REFERENCE.md): health, queue, history, indexers, download client. Read the reason fields — `statusMessages`, `trackedDownloadState`, `trackedDownloadStatus`, `errorMessage` — not just counts.
4. **Logs.** `cd media && docker compose logs --since 30m <service>`, plus each app's own log under `media/data/<app>/logs/`. `docker compose logs vpn` names PIA registration failures explicitly.
5. **Compose/env.** Only now suspect `compose.yml` or `.env`: mounts, `*_IP` values, `PUID`/`PGID`, `TORRENTING_PORT`.

## Symptom → cause

| Symptom | Likely cause in this stack |
| --- | --- |
| `401` with a key that looks right | key read from a checkout that is not the running host |
| `404` on every endpoint of one app | wrong API version — Lidarr is `/api/v1`, not `/api/v3` |
| Traefik 502/503 on `prowlarr.` / `qbittorrent.` | the label-owning `vpn` container is down or unhealthy |
| Prowlarr, FlareSolverr, qBittorrent or slskd unreachable after any VPN restart | recreating `vpn` orphans the containers sharing its namespace: `docker compose up -d --force-recreate vpn flaresolverr prowlarr qbittorrent slskd` |
| slskd searches work but queues are long, nothing ever uploads, peers report it as firewalled | expected: PIA's single forwarded port belongs to qBittorrent, so slskd has no inbound listen port (`50300`) by design. Not a fault; the options are in `media/README.md` → *Soulseek* |
| slskd logs in to Soulseek and then exits, or the UI refuses the login | `SLSK_USERNAME`/`SLSK_PASSWORD` are the **network** account from slsknet.org; `SLSKD_*` is only the web UI. They are not interchangeable |
| Soulseek singles never reach the library | they land in `/data/downloads-unraid/soulseek` and are filed by `./beets/beet.sh import-soulseek`; the hourly `import-auto` timer deliberately never touches that root |
| VPN restart loop, `curl: (28) Connection timed out` during `addKey` | a PIA region is unreachable. `PIA_LOC` is a fallback list; `PORT_FATAL=1` + `EXIT_ON_FATAL=1` + `deunhealth` turn one dead region into a restart loop by design |
| Torrents stall at 0 peers while outbound still works | qBittorrent `[BitTorrent] Session\Interface` must be `wg0`; `MTU=1280` and the IPv6-off sysctls are already set on `vpn` |
| Downloads finish but no inbound peers, ever | PIA's forwarded port must equal qBittorrent's listen port. Compare `media/data/pia-shared/port.dat`, `[BitTorrent] Session\Port` in `media/data/qbittorrent/qBittorrent/qBittorrent.conf`, `TORRENTING_PORT` in `.env`, and what the namespace actually binds: `docker exec vpn ss -lun` |
| Torrents download, nothing reaches the library | `[BitTorrent] Session\DefaultSavePath` must sit inside a mounted root (the `-unraid` shares or `/data/downloads-unraid`); a path outside them writes into the container's writable layer and vanishes on recreate |
| Import fails: "path does not exist" / "no files found" | qBittorrent and the \*arr app must see the same host path at the same container path. Check the storage map below before inventing a remote path mapping |
| Import fails: permission denied | `PUID`/`PGID` must match the CIFS mount options' `uid=`/`gid=`; CIFS ownership comes from the mount, not the server |
| Hardlink or instant move fails | download root and library root on different shares — see the storage map; two NAS boxes means copies |
| Searches return nothing from every indexer | Prowlarr indexer health (`/api/v1/health`, `/api/v1/indexerstatus`), then the FlareSolverr proxy, then the app's own download client and root folder. Results in `/api/v1/search` but none in the app's interactive search is a profile/rejection problem, not an indexer one |
| Prowlarr can't resolve `api.radarr.video`, update check fails | Docker's embedded DNS SERVFAILs on some names. `x-arr-dns` (`1.1.1.1`/`8.8.8.8`) must be merged into every `servarrnetwork` service and never into a `network_mode: service:vpn` service, which inherits the VPN resolver |
| Bazarr finds almost nothing | it only sees `/data`; then check how many subtitle providers are configured (`/api/providers`) — one provider is the usual cause |
| SuggestArr can't reach Jellyfin/Plex | by design it uses the host network so outbound calls carry the LAN address — use the LAN IP (`:8096`), never a container name or a `172.39.0.x` address |
| Radarr health: `Notifications unavailable due to failures: Emby / Jellyfin` | the `Emby / Jellyfin` connection has **Send Notifications** on, and Jellyfin does not implement Emby's `/emby/Notifications` (404). Not a network fault: turn Send Notifications off and keep **Update Library**, matching Sonarr's working config. Gotify carries the notifications |

## Storage map

`/data` is a plain directory on the Pi that carries ten host-side CIFS automounts, from two different NAS boxes. The \*arr containers see all of it through one `- /data:/data` bind.

| Host path | Backed by | Notes |
| --- | --- | --- |
| `/data/movies`, `/data/shows`, `/data/music`, `/data/documents` | `//192.168.0.10/...` | second NAS; Radarr `movieImportedCategory`, Sonarr and Lidarr read these |
| `/data/movies-unraid`, `/data/shows-unraid`, `/data/animes`, `/data/music-unraid`, `/data/music-inbox` | `//192.168.0.149/Media/...` | Unraid shares |
| `/data/downloads-unraid` | `//192.168.0.149/Media/Downloads` | qBittorrent's real download root |
| `/data/downloads-unraid/soulseek` | inside the same Unraid `Media/Downloads` share | slskd's `/downloads`; Beets sees it as `/soulseek-inbox`, Lidarr under `/data/downloads-unraid` |
| `/mnt/usb/downloads2`, `/mnt/usb2/downloads` | **plain directories on the Pi's SD card** | mounted into qBittorrent and the \*arr apps as `/data/downloads2` and `/data/downloads3`. The `usb` names are historical — no USB disk is mounted there |

Current root folders (`GET /api/v3/rootfolder` is authoritative): Radarr `/data/movies`, `/data/movies-unraid`; Sonarr `/data/shows`, `/data/animes`, `/data/shows-unraid`; Lidarr `/data/music`, `/data/music-unraid`. Chaptarr (`GET /api/v1/rootfolder`) points at a book root under `/data` — normally `/data/audiobooks`, the same host path Audiobookshelf's `AUDIOBOOKSHELF_AUDIOBOOKS_DIR` scans. That root is not in the mount table above unless a book share is mounted: an empty local `/data/audiobooks` is the failure mode where the library fills on the SD card and Audiobookshelf shows nothing.

What follows, and what to re-check before touching a mount:

- Identical container paths on both sides is what makes imports work without remote path mapping. Adding a host path for one side only breaks every in-flight import from that root.
- The mounts are host-side autofs. When one drops, the container keeps a valid bind to an empty directory and the app reports the path as accessible — an empty library is the symptom, not an error.
- Hardlinks and atomic moves need one filesystem. The two NAS boxes plus the SD card are three, so an import across them copies. Check with `stat -f -c %d <download-root> <library-root>` on the Pi.
- Downloads default to `/data/downloads-unraid/qbittorrent/completed`; the `radarr`, `tv-sonarr` and `lidarr` categories inherit that path. Writing torrent data to `/data/downloads2` or `/data/downloads3` means writing to the SD card.

## Chaptarr

Books, not film: a Readarr fork (Readarr retired June 2025, still labelled beta upstream) that is the acquisition half of `audiobookshelf/`. Audiobookshelf never downloads anything — it serves files — so "the book never arrived" is a Chaptarr question, and "the file is on disk but absent from Audiobookshelf" is an Audiobookshelf rescan question.

- Same plumbing as the other \*arr apps: Prowlarr as indexer source, qBittorrent at `http://172.39.0.2:8080`, imports into a root folder under `/data`.
- Empty search results are usually **indexers**, not configuration: the installed trackers are film/TV. Book trackers need accounts; MAM-style indexers go through FlareSolverr.
- Empty metadata (no title, no author, no cover) is the metadata provider, not the download: Settings → Metadata needs Hardcover (API token), Goodreads or Audible.
- Config lives in `media/data/chaptarr/`, the API key in `config.xml` — but the entrypoint starts as root, chowns `/config`, then drops to `PUID`. `media/data/chaptarr` is local disk, never a share.

Workflow and the Audiobookshelf side: `media/README.md` → *Chaptarr*.

## Soulseek (slskd)

The path for **one song** Lidarr cannot get: Lidarr matches whole releases, Soulseek shares individual files. Downloads land in `/data/downloads-unraid/soulseek` and enter the library only through `./beets/beet.sh import-soulseek` (`--singletons`, reviewed, `Artist/Singles/Title`). `media/data/slskd/slskd.yml` holds the options edited in the UI; its SQLite state must stay on local disk, never on a share.

It is a **firewalled** client on purpose (VPN privacy over inbound reachability), so "no uploads, slow queues" is the design, not a bug. Do not publish `50300` or add a router forward to "fix" it — that exposes the house IP, which the stack's VPN posture exists to prevent.

## Beets

Manual music-inbox organizer, not a daemon and not a Lidarr replacement: every command runs through `./beets/beet.sh` (`inbox`, `import`, `retry`, `stats`) and matches are reviewed before files move. Workflow, quiet mode and CIFS ownership traps: `media/README.md` → *Beets*.

## Pointers

- [`API-REFERENCE.md`](API-REFERENCE.md) — endpoints, request shapes and verified field names, per service.
- `media/README.md` — VPN remediation, Beets, Maintainerr, Seerr logging, CIFS setup.
- `media/compose.yml` — source of truth for addresses, labels and mounts; `media/.env.example` for variables.
- `scripts/status.sh` — read-only stack/container comparison; `bash scripts/validate.sh` for the repo-wide config gate.
- `docs/STRUCTURE.md` — where the stack sits in the repo.
