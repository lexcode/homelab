# Media stack (Servarr + VPN)

Docker Compose stack for qBittorrent (through a WireGuard PIA VPN), Sonarr, Radarr, Lidarr, Bazarr, Seerr, Prowlarr, FlareSolverr, SuggestArr, and deunhealth. Config lives under `./data/`; libraries and downloads are expected on the host at **`/data`** (bind-mounted into the containers).

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
     data/suggestarr/config_files
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
| Sonarr       | `8989`      |                                          |
| Radarr       | `7878`      |                                          |
| Lidarr       | `8686`      |                                          |
| Bazarr       | `6767`      |                                          |
| Seerr        | `5055`      |                                          |
| Prowlarr     | `9696`      | Via VPN container                        |
| FlareSolverr | `8191`      | Via VPN container                        |
| SuggestArr   | `5000`      | `network_mode: host` — binds on the host |

**DNS:** Apps on `servarrnetwork` use public DNS (`1.1.1.1` / `8.8.8.8`) where noted in `compose.yml`, so lookups like Radarr’s API host work reliably. Do not add that YAML anchor to services using `network_mode: service:vpn`.

**SuggestArr** uses the host network so outbound calls to Jellyfin/Plex on the LAN use the host’s source address (avoids LAN firewalls that drop traffic from the Docker bridge range).

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
└── shows
```

## References

- `.env.example` — non-secret template
- `compose.yml` — services, network, volumes
