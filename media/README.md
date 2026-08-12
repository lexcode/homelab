# Media stack (Servarr + VPN)

Docker Compose stack for qBittorrent (through a WireGuard PIA VPN), Sonarr, Radarr, Lidarr, Bazarr, Seerr, Prowlarr, FlareSolverr, SuggestArr, Maintainerr, Beets, and deunhealth. Config lives under `./data/`; libraries and downloads are expected on the host at **`/data`** (bind-mounted into the containers).

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
   - `PIA_LOC` — PIA location slug (see the VPN image docs)
   - `LOCAL_NETWORK` — your LAN CIDR (e.g. `192.168.0.0/24`) so the VPN container allows local access

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
     data/bazarr \
     data/seerr \
     data/prowlarr \
     data/suggestarr/config_files \
     data/maintainerr \
     data/beets
   ```

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
| Bazarr       | `6767`      |                                          |
| Seerr        | `5055`      |                                          |
| Prowlarr     | `9696`      | Via VPN container                        |
| FlareSolverr | `8191`      | Via VPN container                        |
| SuggestArr   | `5000`      | `network_mode: host` — binds on the host |
| Maintainerr  | `6246`      | `MAINTAINERR_PORT`                       |
| Beets        | —           | No web UI; CLI only, via `docker compose exec` |

**DNS:** Apps on `servarrnetwork` use public DNS (`1.1.1.1` / `8.8.8.8`) where noted in `compose.yml`, so lookups like Radarr’s API host work reliably. Do not add that YAML anchor to services using `network_mode: service:vpn`.

**SuggestArr** uses the host network so outbound calls to Jellyfin/Plex on the LAN use the host’s source address (avoids LAN firewalls that drop traffic from the Docker bridge range).

## Reverse proxy

The proxy stack joins `servarrnetwork`. `sonarr`, `radarr`, `lidarr`, `bazarr`, and `maintainerr` each carry `traefik.*` labels routing them at `<name>.lexcode.dev`. `prowlarr` and `qbittorrent` run with `network_mode: service:vpn`, so their routing labels live on the `vpn` container instead (each router declares its own `loadbalancer.server.port` explicitly) — see [Docker-routed backends](../proxy/README.md#routing-model) for why. Seerr and FlareSolverr are not currently routed publicly.

## Maintainerr

[**Maintainerr**](https://github.com/maintainerr/maintainerr) automates library cleanup by applying rules (e.g. "unwatched for 30 days") against Plex/Jellyfin, then removing matching media via Radarr/Sonarr. It sits on `servarrnetwork` so it can reach the other *arr apps by container name; set its media-server and *arr connections from the Maintainerr UI (`http://<host>:6246`) after startup. Set `MAINTAINERR_GITHUB_TOKEN` in `.env` if you hit GitHub API rate limits.

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

### Example host `/data` tree

Conventional paths under the bind-mounted host root. Point Radarr, Sonarr, Lidarr, Bazarr, and qBittorrent at the folders you actually use.

```text
/data
├── books
├── downloads
│   └── qbittorrent
│       ├── completed
│       ├── incomplete
│       └── torrents
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
