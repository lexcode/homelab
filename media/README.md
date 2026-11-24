# Media stack (Servarr + VPN)

Docker Compose stack for qBittorrent (through a WireGuard PIA VPN), Sonarr, Radarr, Lidarr, Chaptarr, Bazarr, Seerr, Prowlarr, FlareSolverr, slskd (Soulseek), SuggestArr, Maintainerr, Beets, and deunhealth. Config lives under `./data/`; libraries and downloads are expected on the host at **`/data`** (bind-mounted into the containers).

## Prerequisites

- Docker and Docker Compose v2
- A host path `/data` that your `PUID`/`PGID` user can read and write (see optional NAS section below)
- [Private Internet Access](https://www.privateinternetaccess.com/) (or adapt `compose.yml` for another VPN image)

## Quick setup

1. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Edit `.env` and set at least:
   - `PUID` / `PGID` — host user/group that owns `/data` and `./data/*` configs (commonly `1000` / `1000`)
   - `TZ`
   - `SERVARR_SUBNET` and each `*_IP` — must stay inside the same subnet; defaults match `compose.yml`
   - `OPENVPN_USER` / `OPENVPN_PASSWORD` — PIA credentials
   - `PIA_LOC` — PIA location slug, or a comma-separated fallback list (e.g. `ireland,nl_amsterdam,swiss`)
   - `LOCAL_NETWORK` — your LAN CIDR (e.g. `192.168.0.0/24`) so the VPN container allows local access
   - `SLSK_USERNAME` / `SLSK_PASSWORD` — your Soulseek network account; `SLSKD_USERNAME` / `SLSKD_PASSWORD` — the slskd web UI login (see [Soulseek](#soulseek-single-tracks-slskd))

2. **Create the folder structure**

   If you're using bind mounts (like this stack does), create the directories up front so Docker doesn't create them as root.

   ```bash
   mkdir -p \
     data/pia \
     data/pia-shared \
     data/qbittorrent \
     data/sonarr \
     data/radarr \
     data/lidarr \
     data/chaptarr \
     data/bazarr \
     data/seerr \
     data/prowlarr \
     data/suggestarr/config_files \
     data/maintainerr \
     data/beets \
     data/slskd
   ```

   slskd also needs its download directory on the host: `/data/downloads-unraid/soulseek`, owned by `PUID`/`PGID`. It is **not** `data/slskd` — that holds slskd's SQLite databases, which upstream requires to stay on local disk.

3. **PIA WireGuard data** (first run)

   The `vpn` service uses `./data/pia` and `./data/pia-shared`. These are pre-created in the step above.

4. **Start**

   From this directory:

   ```bash
   docker compose up -d
   ```

5. **qBittorrent**

   In **Settings → Advanced**, set **Network interface** to `wg0` (WireGuard in the VPN container). If torrents stall, symptoms often match MTU or IPv6 issues; the compose file already sets IPv6 off on the VPN service and an MTU hint.

## Ports (defaults)

| Service      | Port (host) | Notes                                    |
| ------------ | ----------- | ---------------------------------------- |
| qBittorrent  | `8080`      | Published via VPN container              |
| Torrenting   | `6881`      | TCP/UDP BitTorrent port via VPN container (`TORRENTING_PORT`) |
| Sonarr       | `8989`      |                                          |
| Radarr       | `7878`      |                                          |
| Lidarr       | `8686`      |                                          |
| Chaptarr     | `8789`      | `CHAPTARR_PORT`                          |
| Bazarr       | `6767`      |                                          |
| Seerr        | `5055`      |                                          |
| Prowlarr     | `9696`      | Via VPN container                        |
| FlareSolverr | `8191`      | Via VPN container                        |
| SuggestArr   | `5000`      | `network_mode: host` — binds on the host |
| Maintainerr  | `6246`      | `MAINTAINERR_PORT`                       |
| Beets        | —           | No web UI; CLI only, via `docker compose exec` |
| slskd        | `5030`      | Via VPN container. Soulseek's own listen port `50300` is **not** published — see [Soulseek](#soulseek-single-tracks-slskd) |

**DNS:** Apps on `servarrnetwork` use public DNS (`1.1.1.1` / `8.8.8.8`) where noted in `compose.yml`, so lookups like Radarr’s API host work reliably. Do not add that YAML anchor to services using `network_mode: service:vpn`.

**SuggestArr** uses the host network so outbound calls to Jellyfin/Plex on the LAN use the host’s source address (avoids LAN firewalls that drop traffic from the Docker bridge range).

## Connections between services

In-app settings that follow from the network namespaces and the mount layout — set these once per app:

| Where | Value | Why |
| --- | --- | --- |
| Radarr / Sonarr / Lidarr / Chaptarr → Download Clients → qBittorrent | host `172.39.0.2` (or the host LAN IP `192.168.0.24`), port `8080` | qBittorrent has no address of its own; `172.39.0.2` is the `VPN_IP` of the container whose namespace it shares, and the LAN IP reaches it through the published port |
| Prowlarr → Apps | Radarr `http://radarr:7878`, Sonarr `http://sonarr:8989`, Lidarr `http://lidarr:8686`, Chaptarr `http://chaptarr:8789` | plain `servarrnetwork` DNS |
| Prowlarr → Settings → Indexer Proxies → FlareSolverr | `http://172.39.0.2:8191` (or `http://127.0.0.1:8191`) | Prowlarr and FlareSolverr share the `vpn` namespace, so both are the same machine — `http://flaresolverr:8191` does not resolve |
| Bazarr → Settings → Sonarr / Radarr | `http://sonarr:8989` / `http://radarr:7878` | same network |
| Seerr → Settings → Services | `http://radarr:7878` / `http://sonarr:8989` | same network |
| Maintainerr → media server and \*arr connections | container names on `servarrnetwork` | same network |
| slskd API consumers (a Kima instance, soularr, `curl`) → slskd | `http://172.39.0.2:5030`, or `http://<host>:5030` / `https://slskd.lexcode.dev` from outside Docker | `slskd` has no address of its own — it shares the `vpn` namespace, so `http://slskd:5030` does not resolve |

The download client’s save path and category have to land inside `/data/downloads2`, `/data/downloads3` or `/data/downloads-unraid`. Those are the only download roots mounted into qBittorrent, and it and the \*arr apps see all three at identical container paths — which is what makes imports work without remote path mapping.

## Reverse proxy

The proxy stack joins `servarrnetwork`. `sonarr`, `radarr`, `lidarr`, `chaptarr`, `bazarr`, `maintainerr`, `seerr`, and `suggestarr` each carry `traefik.*` labels routing them at `<name>.lexcode.dev` — LAN-only, like every other hostname here that isn't listed in the Cloudflare Tunnel ingress. Seerr also has a `cloudflare` router: set its Cloudflare Tunnel public hostname origin to `http://traefik:8081`, not the host-published `http://192.168.0.24:5055`, so public traffic stays on Docker's internal networks.

Two cases need a non-default backend address:

- `prowlarr`, `qbittorrent`, `flaresolverr` and `slskd` run with `network_mode: service:vpn`, so their routing labels live on the `vpn` container instead (each router declares its own `loadbalancer.server.port` explicitly).
- `suggestarr` runs with `network_mode: host`, so it has no IP on `servarrnetwork` for Traefik's Docker provider to discover. Its router therefore declares `loadbalancer.server.url` pointing at the host's LAN IP and `SUGGESTARR_PORT` — that address must stay reachable from the Traefik container.

FlareSolverr is not currently routed publicly.

## Maintainerr

[**Maintainerr**](https://github.com/maintainerr/maintainerr) automates library cleanup by applying rules (e.g. "unwatched for 30 days") against Plex/Jellyfin, then removing matching media via Radarr/Sonarr. It sits on `servarrnetwork` so it can reach the other *arr apps by container name; set its media-server and *arr connections from the Maintainerr UI (`http://<host>:6246`) after startup. Set `MAINTAINERR_GITHUB_TOKEN` in `.env` if you hit GitHub API rate limits.

## Chaptarr (audiobook and ebook manager)

[**Chaptarr**](https://github.com/Chaptarr/chaptarr) is the book equivalent of
Sonarr/Radarr: it monitors authors, searches indexers through Prowlarr, sends
grabs to qBittorrent, and imports the finished files into a library root. It is
the **acquisition half** of the [`audiobookshelf/`](../audiobookshelf/README.md)
stack — Audiobookshelf only serves files already on disk, so without something
like Chaptarr a requested book never arrives by itself.

Chaptarr is a fork of Readarr, which was retired in June 2025. Upstream labels
it **beta**: keep the recycling bin enabled, and do not point it at a library
you could not restore from backup.

### Wiring it up

Nothing is configured by environment variables beyond `PUID`/`PGID`/`TZ`; the
rest is in the UI at `http://<host>:8789` (or `https://chaptarr.lexcode.dev`):

| Setting | Value |
| --- | --- |
| Settings → Indexers | add Prowlarr as the indexer source (or add indexers directly). On the Prowlarr side add Chaptarr under **Apps** as `http://chaptarr:8789` with its API key, the same way Sonarr/Radarr are added. |
| Settings → Download Clients → qBittorrent | host `172.39.0.2`, port `8080` — qBittorrent has no address of its own (see [Connections between services](#connections-between-services)) |
| Settings → Media Management → Root Folders | `Audiobooks` → `/data/audiobooks`; optionally `Ebooks` → `/data/books` |
| Category | use a dedicated category such as `chaptarr`, kept inside a mounted download root (`/data/downloads-unraid`) |
| Settings → Metadata | pick a book metadata provider (Hardcover, Goodreads, Audible). Hardcover needs a free API token; without a provider, searches return nothing |

The root folder is the same host path that Audiobookshelf's
`AUDIOBOOKSHELF_AUDIOBOOKS_DIR` points at, mounted here as `/data/audiobooks` by
the `- /data:/data` bind. Two consequences worth knowing:

- **The root must be a real mount.** If `/data/audiobooks` is merely an empty
directory on the Pi (an automount that did not come up), Chaptarr will happily
fill the SD card and Audiobookshelf will see nothing. `findmnt /data/audiobooks`
before the first import.
- **Imports usually copy, not hardlink.** `/data/downloads-unraid` and the book
library are different CIFS shares, so finishing a book costs a second copy and
the peak space of both.

Audiobookshelf picks the files up from the library folder (its own library
watcher, or a manual rescan from the library menu; a CIFS-backed library may not
emit inotify events reliably).

Root folders also carry per-media-type automation options — audiobook quality
profile, monitored-on-add, and `Write cover into Audiobookshelf folder` — so the
cover audiobook metadata provides lands next to the files that Audiobookshelf
then displays.

### The limiting factor is indexers

The existing indexers in Prowlarr are film and TV trackers. Audiobooks come from
book-specific trackers (for example MyAnonamouse or AudioBookBay, sometimes via
the FlareSolverr proxy at `http://172.39.0.2:8191`) or from usenet, and those
need accounts. With only movie/TV indexers configured, Chaptarr's searches return
nothing and it looks broken when it is simply unconfigured. Book metadata
matching is also weaker than TMDB: expect to fix some matches by hand.

## Beets (music inbox organizer)

[**Beets**](https://beets.io/) takes the flat pile of FLAC files that SpotiFLAC produces, identifies them against MusicBrainz, writes clean tags, and **moves** them into the library as `Artist/Album/NN - Title.flac`.

Lidarr is unchanged and keeps its existing role (monitoring artists, grabbing releases via Prowlarr/qBittorrent). Beets is only responsible for the **manual inbox** — the files that arrive from the phone and that Lidarr never asked for.

### Architecture

```text
Android
  └─ SpotiFLAC                      downloads FLAC as flat files, no album folders
       └─ Syncthing (Android)
            └─ Syncthing (Unraid)   →  Unraid share  Media/Music-Inbox
                                            │
Pi 5, CIFS mount                            ▼
  /data/music-inbox  ──────────────►  beets container  /music-inbox
                                            │  beet import --group-albums
                                            │  identify → tag → rename → MOVE
                                            ▼
  /data/music-unraid ◄─────────────  beets container  /music
       │
       └─ Unraid share  Media/Music/Artist/Album/NN - Title.flac
                                            │
                                            ▼
                                        Navidrome
```

Both host paths are CIFS mounts of Unraid shares, so nothing is copied across the network twice: Beets reads from one share and writes to the other, and Navidrome (running on Unraid, outside this repo) serves the result straight off local disk.

The container itself has no daemon; it idles on `sleep infinity` and every import is a command run against it via `docker compose exec`, either by hand or by the optional [`import-auto` systemd timer](#automated-quiet-import). Start with manual imports until you trust the matching — see [First import](#first-import-manual).

### Files

| Path | Purpose |
| ---- | ------- |
| `beets/Dockerfile` | Image: beets + `fpcalc` (fingerprinting) + `flac` (integrity checks) |
| `beets/config.yaml` | Version-controlled config; the whole `beets/` dir is mounted read-only as `BEETSDIR=/beets` |
| `beets/beet.sh` | Wrapper for the common `docker compose exec` invocations |
| `data/beets/` | `library.db`, `state.pickle`, `import.log` — local disk, not committed |

Config is mounted **read-only**, so edit `beets/config.yaml` in the repo rather than in place; `beet config -e` will not work by design. Each `beet` command is a fresh process that re-reads the file, so edits and `git pull`s apply immediately with no restart.

`beets/` is mounted as a **directory**, not as the single `config.yaml` file. That is deliberate: git replaces a file by writing a new inode and renaming over it, and a single-file bind mount keeps serving the old inode — a `git pull` would appear to succeed on the host while the container silently kept running the old config until it was force-recreated.

Because `BEETSDIR` is read-only, `config.yaml` sets `library`, `statefile`, and `import.log` to explicit paths under `/config`. Adding a new beets feature that writes state means pointing it at `/config` too, or it will fail on a read-only filesystem.

### Setup

1. **Host mounts.** The Pi needs both Unraid shares mounted before the container starts. Add to `/etc/fstab` (same credentials file and `uid`/`gid` as the rest of the stack — see [Optional: remote NAS](#optional-remote-nas-for-movies-and-tv-persistent-cifs-mounts)):

   ```fstab
   //192.168.0.149/Media/Music       /data/music-unraid cifs x-systemd.automount,uid=1000,gid=1000,credentials=/home/lexcode/.smbcredentials,iocharset=utf8 0 0
   //192.168.0.149/Media/Music-Inbox /data/music-inbox  cifs x-systemd.automount,uid=1000,gid=1000,credentials=/home/lexcode/.smbcredentials,iocharset=utf8 0 0
   ```

   ```bash
   sudo mkdir -p /data/music-unraid /data/music-inbox
   sudo systemctl daemon-reload
   sudo mount /data/music-unraid /data/music-inbox
   ```

   `uid`/`gid` **must** match `PUID`/`PGID` in `.env`, or Beets will fail to move files.

2. **Environment.** `.env` already carries defaults; override only if your paths differ:

   ```ini
   MUSIC_INBOX_DIR=/data/music-inbox
   MUSIC_LIBRARY_DIR=/data/music-unraid
   BEETS_IP=172.39.0.11
   ```

3. **Build and start.**

   ```bash
   docker compose build beets
   docker compose up -d beets
   docker compose exec beets beet version
   ```

   The build takes a few minutes on a Pi (it compiles nothing, but `pip` and `apt` are slow over ARM). Rebuild with `docker compose build --pull beets` to pick up a newer beets.

### First import (manual)

**Do not skip straight to a bulk import.** Match quality on SpotiFLAC files varies a lot depending on how much metadata was embedded, and `import.move: yes` means a bad match relocates real files. Work up in stages.

1. **See what's waiting:**

   ```bash
   ./beets/beet.sh inbox
   ```

2. **Dry run — no changes, just show what Beets would decide:**

   ```bash
   docker compose exec -it beets beet import --group-albums --pretend /music-inbox
   ```

3. **Import one album first**, so you can look at a single decision closely:

   ```bash
   docker compose exec -it beets beet import --group-albums "/music-inbox/<one album's files>"
   ```

   At the prompt: `A` apply, `S` skip, `U` use as-is (keep existing tags), `E` edit tags inline, `G` group albums differently, `?` help. Skipping leaves the files untouched in the inbox — always the safe answer.

4. **Verify it landed correctly**, then widen:

   ```bash
   ls -R /data/music-unraid/<Artist>
   ./beets/beet.sh stats
   ```

5. **Run the full inbox** once you trust the matching:

   ```bash
   ./beets/beet.sh import
   ```

   `--group-albums` is what makes a flat directory work: Beets clusters the loose files by their album tags instead of assuming one directory equals one album. If files arrive already in per-album folders, use `./beets/beet.sh import-tree` instead. For genuine one-off tracks, `./beets/beet.sh import-singles` files them under `Artist/Singles/`.

   `import.incremental` is on, so re-running only looks at items it hasn't already processed — **including ones you skipped**. A file left on `S` stays in the inbox but does *not* get reprompted on the next run; a later `import`/`import-singles` pass will report `Skipped N paths` and move on without asking again. To deliberately revisit one:

   ```bash
   ./beets/beet.sh retry "/music-inbox/<file or dir>"
   ```

   This runs with `--noincremental` on just that path, so beets forgets the earlier skip and prompts again.

### Automated (quiet) import

Once you trust the matching (step 5 above), you can stop running imports by hand. `./beets/beet.sh import-auto` runs `beet import --group-albums -q /music-inbox` — beets' **quiet mode**: it never prompts. For each candidate it applies the match only if beets' own recommendation is **"strong"** (the same bar tightened by `match.strong_rec_thresh: 0.10` in `config.yaml`); anything weaker is **skipped automatically**, exactly as if a human had pressed `S`. `import.move: yes` still applies, so a strong match still moves real files — quiet mode changes who clicks "apply" on the confident cases, not the safety bar itself.

`systemd/media-beets-import.timer` runs `import-auto` hourly so new SpotiFLAC drops get organized without a manual step. Before each run, its service requires and verifies that both `/data/music-inbox` and `/data/music-unraid` are active mount points; if either CIFS mount is unavailable, the import fails before Beets can move files into a shadow directory on the Pi. It's opt-in — install it only if you want that:

```bash
sudo cp ../systemd/media-beets-import.service ../systemd/media-beets-import.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now media-beets-import.timer
```

Because `import.incremental` is on, a quiet-mode skip is recorded exactly like a manual `S` — it will **not** be reprompted by a later `import-auto` run, nor by a plain interactive `./beets/beet.sh import`. Files that quiet mode couldn't confidently match just accumulate in the inbox until you look at them:

```bash
./beets/beet.sh inbox                          # what's still sitting there
tail -f data/beets/import.log                  # what got imported vs. skipped, and why
./beets/beet.sh retry "/music-inbox/<file or dir>"  # force one back to an interactive prompt
```

`journalctl -u media-beets-import.service` shows each run's output if you want to check the timer itself is firing.

### Library commands

```bash
./beets/beet.sh stats                # totals: tracks, albums, size, playtime
./beets/beet.sh ls                   # everything in the library
./beets/beet.sh ls albumartist:Radiohead
./beets/beet.sh dupes                # duplicate albums
./beets/beet.sh missing              # albums with tracks missing
./beets/beet.sh check                # FLAC integrity across the library (slow)
./beets/beet.sh shell                # shell in the container
./beets/beet.sh beet <anything>      # arbitrary beet command
./beets/beet.sh import-auto          # unattended quiet-mode import (strong matches only)
./beets/beet.sh import-singles       # standalone tracks from /music-inbox
./beets/beet.sh import-soulseek      # standalone tracks from /soulseek-inbox (slskd downloads)
./beets/beet.sh retry <path>         # re-prompt for one previously skipped item
```

Import failures and skips are recorded in `data/beets/import.log`.

### Resulting layout

```text
/data/music-unraid/
└── Artist/
    └── Album/
        ├── 01 - Track.flac
        ├── 02 - Track.flac
        └── cover.jpg
```

Singles land under `Artist/Singles/Title.flac`. Compilations use the same `Artist/Album/` shape (the `comp` path in `config.yaml` overrides the beets default, which would otherwise create a separate `Compilations/` root).

### Troubleshooting

**Permission denied when moving files.** The container runs as `${PUID}:${PGID}`. The CIFS mounts must be mounted with matching `uid=`/`gid=` — CIFS ownership comes from the mount options, not from the server, so a mismatch here is the usual cause. Check with:

```bash
docker compose exec beets id
stat -c '%u %g %n' /data/music-inbox /data/music-unraid
```

All three numbers should agree.

**`Transport endpoint is not connected` / empty inbox.** The `x-systemd.automount` mount dropped. The container keeps its stale bind mount, so remount on the host and then restart the container:

```bash
sudo mount -a
docker compose restart beets
```

**A re-run prints `Skipped N paths` and doesn't prompt for a file you skipped earlier.** Expected — `import.incremental` remembers skip decisions, not just successful imports, so it won't re-ask on its own. Use `./beets/beet.sh retry "<path>"` to force that one item back to a prompt.

**Files import but Navidrome doesn't see them.** Navidrome scans the Unraid share directly; confirm the file actually landed on Unraid (not in a shadowed local directory that exists underneath the mount point) and trigger a rescan. A common trap: if the CIFS mount fails, `/data/music-unraid` is still a valid empty local directory and Beets will happily write into the Pi's SD card instead. `mountpoint -q /data/music-unraid` before a large import.

**Every album reports "No matching release found", even clean well-tagged ones.** The `musicbrainz` plugin is missing from the `plugins` list. In beets 2.x MusicBrainz is a plugin rather than built in, and the stock config is `plugins: [musicbrainz]` — setting an explicit list *replaces* that default instead of extending it, leaving the autotagger with no metadata source at all. Check with:

```bash
docker compose exec beets beet version | grep plugins
```

`musicbrainz` must appear. Keep it first in `config.yaml`'s `plugins` list whenever that list is edited.

**Nothing matches / everything is a low-confidence guess.** SpotiFLAC left too few tags. `fromfilename` and `chroma` (acoustic fingerprinting) are both enabled to cover that, but fingerprinting needs network access to AcoustID — verify with `docker compose exec beets fpcalc -version` and check the container resolves DNS (it uses the `1.1.1.1` / `8.8.8.8` override shared with the *arr services).

**Slow imports.** Expected. Each album is a MusicBrainz lookup plus, on weak metadata, a fingerprint of every track, and writes go over SMB. Import in batches rather than one 5,000-file run.

## Soulseek (single tracks, slskd)

[**Soulseek**](https://www.slsknet.org/) is a peer-to-peer network where users share individual music files. [**slskd**](https://github.com/slskd/slskd) is its client-server implementation — a browser UI plus a REST API — running as the `slskd` service.

### Why this exists next to Lidarr

Lidarr is **album**-oriented: it matches whole releases against MusicBrainz, and it will not grab one track that was never catalogued as a release it can match — a single, a compilation-only B-side, a radio rip, a track from a mix. Those are exactly what Soulseek is good at, because it indexes *files people have*, not releases a database knows about.

This is not a Lidarr replacement. Lidarr keeps monitoring artists and grabbing releases through Prowlarr/qBittorrent; slskd is where you go when Lidarr's search comes back empty for one specific song.

### Why slskd and not a GUI client in a container

[realies/soulseek-docker](https://github.com/realies/soulseek-docker) packages the SoulseekQt desktop application behind a noVNC browser view. It works, but it has no API, no automation surface, and on this host it runs under **Box64 emulation** (`linux/arm64` via emulation, not native). slskd publishes native `arm64` images, and its API is what every other tool in this space binds to — including automation you may add later.

### The VPN trade-off (read before use)

`slskd` runs with `network_mode: service:vpn` — the same posture as qBittorrent, so Soulseek traffic never leaves from the house IP.

The cost is the **inbound listening port**. On Soulseek, uploads are connections that *other people* open to you, so a client without a reachable port is "firewalled": it can still search, and it can still download (the transfers it starts are outbound), but peers cannot connect to it. In practice that means longer queue positions on busy users, some users refusing firewalled clients outright, and **no uploading at all**.

PIA forwards exactly one port per account, and `./scripts/port-sync.sh` already hands it to qBittorrent — two services cannot share it. So there are only three ways to get slskd a real listening port, none of them free:

| Option | Cost |
| --- | --- |
| Leave it as shipped (firewalled behind PIA) | Slower queues, no sharing. Downloads still work |
| A second VPN with its own port forwarding, exposing the port to slskd | A second PIA session or another provider; whether a PIA account can hold two forwards at once is **unverified** here — test before relying on it |
| Publish `50300` on the host and port-forward it on the router | Peers (and anything watching the network) see the house IP — defeats the reason qBittorrent is behind the VPN. Not recommended |

Sharing is therefore left **off** by default: while firewalled, a shared folder is one nobody can download from. If you ever give slskd a reachable port, share read-only and keep the scan cheap on the Pi:

```yaml
    environment:
      - SLSKD_SHARED_DIR=/music
      - SLSKD_SHARE_CACHE_STORAGE_MODE=Disk  # memory is the default; the library is large
      - SLSKD_SHARE_CACHE_WORKERS=2          # defaults to one per core
    volumes:
      - ${MUSIC_LIBRARY_DIR:-/data/music-unraid}:/music:ro
```

### Setup

1. **Soulseek account.** Required before slskd can log in, and it is free — but there is **no web sign-up**: slsknet.org's registration path answers `403`, and slskd has no account-creation feature of its own. An account is created from inside a Soulseek client's login window. The reference client is [SoulseekQt](https://www.slsknet.org/news/) (download page → Windows/macOS builds); registering from its login dialog asks for a username, password and email. Already had a Soulseek account in any client? Reuse it — `SLSK_USERNAME` / `SLSK_PASSWORD` are just that login.
2. **Environment.** In `.env`, set `SLSK_USERNAME` / `SLSK_PASSWORD` for the network account and `SLSKD_USERNAME` / `SLSKD_PASSWORD` for the web UI. Upstream's web default is `slskd` / `slskd`; do not leave it there. Empty `SLSK_*` values do not stop the container — it starts and simply never connects.
3. **Host directory.** `mkdir -p data/slskd /data/downloads-unraid/soulseek`, both owned by `PUID`/`PGID`.
4. **Start.** `docker compose up -d slskd` (it waits for the `vpn` health check).
5. **Log in.** `https://slskd.lexcode.dev` or `http://<host>:5030`, with the `SLSKD_*` credentials.

The order is not strict: with empty `SLSK_*` values the container still starts and simply stays offline, so an account can be obtained afterwards. `.env` is read at container creation, so after adding credentials re-create the service (`docker compose up -d --force-recreate slskd`) — a plain `restart` keeps the old environment. Log out of any desktop Soulseek client once slskd is connected; two sessions on one username is at best confusing.

Options — search/transfer limits, download naming, API keys, shares — are edited **in the UI** and written to `data/slskd/slskd.yml`, because `SLSKD_REMOTE_CONFIGURATION=true`. That makes `data/slskd/slskd.yml` the file to back up; the SQLite databases next to it are only search/transfer state.

### Downloading one track

1. **Search** in slskd, e.g. `Radiohead Lift`.
2. **Pick a file**, preferring a peer with free slots, then download. `SLSKD_DOWNLOADS_DIR=/downloads` is host `/data/downloads-unraid/soulseek`, mounted into the `beets` container as `/soulseek-inbox` and already visible to Lidarr under `/data/downloads-unraid`.
3. **Import it into the library** — reviewed, tagged, moved to `Artist/Singles/`:

   ```bash
   ./beets/beet.sh import-soulseek
   ```

   Same rules as every other import path in this stack: interactive prompt, `import.move: yes`, and `paths.singleton: $artist/Singles/$title`. Nothing is filed until you accept the match (or use `retry <path>` later for one you skipped). **This is deliberately not automatic**: the hourly `import-auto` timer only covers `/music-inbox`, so a partly-downloaded or badly-named Soulseek file never ends up in the library unannounced.

Soulseek filenames are whatever the uploader typed into their own file manager, so expect `fromfilename` to do real work here; fix bad matches with `E` at the prompt rather than letting them through.

### Troubleshooting

**The container runs but slskd never connects.** Empty or wrong `SLSK_USERNAME` / `SLSK_PASSWORD` — those are the *network* account, not the web login. `docker compose logs slskd` names the rejected login; the UI's own connection indicator shows the same state.

**Searches return nothing, or nothing downloads.** Firewalled clients see fewer peers, and some users reject them. Try a different uploader, and remember that a search for a track name only matches files whose names contain it.

**slskd unreachable after a VPN restart.** It shares the `vpn` namespace, so it is orphaned by a bare `docker compose up -d vpn`: `docker compose up -d --force-recreate vpn flaresolverr prowlarr qbittorrent slskd`.

**Nothing shows up in the library after downloading.** The files are in `/data/downloads-unraid/soulseek` until you run `./beets/beet.sh import-soulseek`; check `./beets/beet.sh beet ls -a` and `data/beets/import.log` after accepting a match.

**Permission denied writing downloads.** `/data/downloads-unraid/soulseek` must be owned by `PUID`/`PGID`, and the CIFS mount must carry matching `uid=`/`gid=` — same rule as the rest of the stack.

### Wiring other tools to it

slskd's API is reachable at `http://172.39.0.2:5030` from `servarrnetwork` (it shares the `vpn` namespace, so the container name does not resolve), or over the LAN/ingress URL above. Create an API key in slskd's UI options:

- [Kima](https://github.com/Chevron7Locked/kima-hub)'s "slskd (external)" Soulseek mode takes that URL + key, and reads finished downloads out of a folder you mount into it.
- [Soularr](https://github.com/mrusse/soularr) automates it the other way round: it reads Lidarr's **wanted albums** and drives slskd. That is album-shaped work Lidarr already attempts, adds a service plus two API keys, and duplicates Prowlarr's job — so it is not part of this stack. Worth revisiting only if Lidarr's own coverage becomes the bottleneck.

## VPN (PIA) troubleshooting

The `vpn` container fails closed if PIA's WireGuard key registration does not complete. A single unreachable region looks like this in `docker compose logs vpn`:

```text
[wg-gen] Registering public key with PIA endpoint; id: uk, cn: Server-10876-2a, ip: 85.203.46.130
curl: (28) Connection timed out after 15001 milliseconds
...
Registration failed
Failed to generate WireGuard config for the selected location/s: uk
```

`PIA_LOC` accepts a comma-separated list, and the image tries each location until one registers (the Compose default is `ireland,nl_amsterdam,swiss`). If every location fails, list PIA's current regions with `docker compose exec vpn /scripts/wg-gen.sh -a` and pick one whose endpoint is reachable from your network; regional PIA WireGuard endpoints are occasionally unreachable while the rest of PIA's API stays up.

The `ping` health check reports `Operation not permitted` while `wg0` is down because the image installs a default-drop firewall before the tunnel exists. That is expected during startup, not the cause of a failed start.

Prowlarr, FlareSolverr, and qBittorrent use `network_mode: service:vpn`, so recreating the `vpn` container leaves them in the old network namespace. Recreate them together after a manual VPN replacement:

```bash
docker compose up -d --force-recreate vpn flaresolverr prowlarr qbittorrent
```

## Keeping the listen port on PIA's forwarded port

PIA forwards a single port for inbound torrent traffic. qBittorrent has to *listen* on exactly that port or no peer can connect to you in — downloads still work, so the failure is silent. The forwarded port is published at `./data/pia-shared/port.dat`, and `PORT_PERSIST=1` asks PIA to keep the same port across restarts (usually for weeks, but not guaranteed: a reconnect or a `PIA_LOC` region fallback can hand out a different one).

`scripts/port-sync.sh` closes that gap. The `vpn` container runs it through the image's `PORT_SCRIPT` hook whenever a port is bound, passing the port as its first argument. The script posts that port to qBittorrent's `app/setPreferences` API over loopback — the two containers share a network namespace, and qBittorrent's `WebUI\LocalHostAuth=false` lets loopback clients skip the password, so it needs no credentials. It retries for about a minute while qBittorrent starts, logs each decision as `port-sync: …` in `docker compose logs vpn`, and backs off if the port is unchanged.

### When the hook fires

The image calls it from `pf_success.sh`, which runs only in the branch that acquires a fresh PIA port-forward token and binds the port:

- container start
- any restart or reconnect — a `PIA_LOC` fallback, a manual recreate, or `deunhealth` restarting an unhealthy `vpn`
- when PIA's port-forward token comes within a week of expiry, which is where a new port number can first appear (tokens live roughly two months)

It deliberately does **not** run on the 15-minute keep-alive rebind, because that rebind cannot change the port and re-running it would only append duplicate firewall rules. So the trigger set and the “the port can change” set are the same — a change is never missed. The trade-off is that a qBittorrent restart on its own does not re-sync; it doesn't need to, since qBittorrent persists `Session\Port` and the last sync already set the right value.

Check the current state any time without logging into the UI:

```bash
printf 'PIA forwards: '; cat data/pia-shared/port.dat
docker exec vpn ss -lntu | grep -E 'wg0|utp'   # what qBittorrent actually binds
```

The two numbers must match. Two consequences worth knowing:

- `TORRENTING_PORT` in `.env` now only describes the ports published on the host for LAN-side peers; it is no longer the listen port the internet sees. Leave the published mappings alone unless you want to drop them.
- Anything that hard-codes the listen port — the qBittorrent UI's *Advanced → Listening port*, or a `Session\Port` value in `qBittorrent.conf` — gets overwritten by the sync, by design.

Because the script is mounted into the `vpn` service, applying it means recreating that container *and* the three that share its namespace:

```bash
docker compose up -d vpn flaresolverr prowlarr qbittorrent
```

It only fires when the VPN reports a successful forward, so a qBittorrent restart while PIA keeps the same port needs no action — but if the UI ever shows a port that disagrees with `port.dat`, run the same script by hand (no argument reads `port.dat`):

```bash
docker exec vpn sh /port-sync.sh
```

The script only ever writes a port it can read back as the forwarded one, and it logs `port-sync: gave up …` instead of guessing. A failed sync leaves the old port in place rather than pointing qBittorrent at something wrong.

## Seerr logging

Seerr defaults to informational logging through `SEERR_LOG_LEVEL=info`. When
troubleshooting, set `SEERR_LOG_LEVEL=debug`, reproduce the issue, then restore
`info` to avoid unnecessary log volume and disk I/O.

## deunhealth (container watchdog)

[**deunhealth**](https://github.com/qdm12/deunhealth) watches for containers that become unhealthy and restarts them. It uses `network_mode: none` (no network access needed) and mounts the Docker socket read-only. Services that should be restarted on unhealthy status carry the label `deunhealth.restart.on.unhealthy=true` in `compose.yml` — currently applied to the `vpn` container. If the WireGuard health check fails (e.g. connectivity loss), deunhealth triggers a restart automatically rather than leaving the VPN container stuck and all dependent services unreachable.

## Optional: remote NAS for movies and TV (persistent CIFS mounts)

This only applies if **media libraries live on another machine** (e.g. SMB share on `192.168.0.10`) while the stack still uses host path **`/data`** inside the containers. In that case you mount the shares **on the host** under `/data` before or automatically at boot.

### 1. Credentials file

Create a root-owned credentials file (example path `~/.smbcredentials` or `/etc/nas-credentials`):

```ini
username=your_smb_user
password=your_smb_password
domain=WORKGROUP
```

Restrict permissions:

```bash
chmod 600 ~/.smbcredentials
```

Use the **same** `uid`/`gid` in mount options as `PUID`/`PGID` in `.env` so the \*arr apps and qBittorrent see matching ownership.

### 2. Mount points

Create directories on the host, for example:

```bash
sudo mkdir -p /data/movies /data/shows
```

### 3. Manual test mount

Adjust server, share names, and credentials path:

```bash
sudo mount -t cifs "//192.168.0.10/Media/Movies" /data/movies \
  -o credentials=/path/to/.smbcredentials,uid=1000,gid=1000,iocharset=utf8
```

Unmount when testing: `sudo umount /data/movies`

### 4. Persistent mounts (`fstab` + systemd automount)

To survive reboots, add lines to `/etc/fstab`. Example (replace server, shares, and credentials path):

```fstab
//192.168.0.10/Media/Movies /data/movies cifs x-systemd.automount,uid=1000,gid=1000,credentials=/home/youruser/.smbcredentials,iocharset=utf8 0 0
//192.168.0.10/Media/TV\040Shows /data/shows cifs x-systemd.automount,uid=1000,gid=1000,credentials=/home/youruser/.smbcredentials,iocharset=utf8 0 0
```

Spaces in share paths must be escaped as `\040` in `fstab`. Then:

```bash
sudo systemctl daemon-reload
sudo mount /data/movies
sudo mount /data/shows
# or:
sudo mount -a
```

`x-systemd.automount` triggers mounts on access and integrates cleanly with systemd.

If you prefer small helper scripts (e.g. health checks or forced remounts), keep them in this repo next to the stack; the important part is that **the host always presents a stable `/data/...` tree** before you rely on the apps.

### 5. If you skip NAS mounts

Keep all library paths on local disks under `/data` (or change the bind mounts in `compose.yml` to match your layout).

## Layout summary

- `./data/*` — container configs (gitignored or local only; do not commit secrets)
- `/data` on host — libraries, downloads root (as configured in each app)

On the reference host `/data` is not a disk: it is a directory carrying ten host-side CIFS automounts, from Unraid (`192.168.0.149` → `Media/{Downloads,Movies,Shows,Animes,Music,Music-Inbox}`) and a second NAS (`192.168.0.10` → `Media/{Movies,TV Shows,Music,Documents}`). The `-unraid` suffixed roots and the plain ones therefore sit on **different** filesystems, which is why an import between them copies instead of hardlinking. `/mnt/usb/downloads2` and `/mnt/usb2/downloads` are plain directories on the host's root filesystem despite the name — no USB disk is mounted there.

### Example host `/data` tree

Conventional paths under the bind-mounted host root. Point Radarr, Sonarr, Lidarr, Chaptarr, Bazarr, and qBittorrent at the folders you actually use.

```text
/data
├── audiobooks      # CIFS: book library root Chaptarr imports into; Audiobookshelf scans it
├── books           # optional ebook root, if you keep those separately from audiobooks
├── downloads
│   ├── qbittorrent
│   │   ├── completed
│   │   ├── incomplete
│   │   └── torrents
│   └── soulseek     # CIFS: Unraid Media/Downloads/soulseek — slskd downloads (Beets reads it as /soulseek-inbox)
├── movies
├── music
├── music-inbox      # CIFS: Unraid Media/Music-Inbox — SpotiFLAC drop zone (Beets reads)
├── music-unraid     # CIFS: Unraid Media/Music — organized library (Beets writes)
└── shows
```

## Related

- **[notifications/](../notifications/README.md)** — [Gotify](https://gotify.net/) for push alerts; in each *arr app use **Settings → Connect → Gotify** with your server URL (reachable from the container) and an **application** token from Gotify.

## References

- `.env.example` — non-secret template
- `compose.yml` — services, network, volumes
