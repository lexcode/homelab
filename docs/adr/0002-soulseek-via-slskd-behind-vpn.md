# Soulseek via slskd, behind the existing PIA VPN

Lidarr only acquires whole releases it can match against MusicBrainz, so individual tracks — singles, compilation-only cuts, radio rips — never arrive through it. They are added to the `media/` stack through **Soulseek**, the peer-to-peer network where users share individual files, using [**slskd**](https://github.com/slskd/slskd) as the client. slskd runs as a new `slskd` service with `network_mode: service:vpn`, downloads into the Unraid downloads share at `/data/downloads-unraid/soulseek`, and those files are filed into the library by Beets (`./beets/beet.sh import-soulseek`, `--singletons`), not by Lidarr.

The service is deliberately a **firewalled** Soulseek client. PIA forwards exactly one port per account and `./scripts/port-sync.sh` already assigns it to qBittorrent, so slskd has no reachable listening port: it can search and it can download, but peers cannot connect to it, which costs queue position and makes uploading (sharing back) impossible. That was accepted over the alternatives below.

## Considered Options

- **A GUI Soulseek client in a container** ([realies/soulseek-docker](https://github.com/realies/soulseek-docker), SoulseekQt behind noVNC) — rejected: no API or automation surface of any kind, one browser-VNC session rather than a service, and on this ARM64 host it runs under Box64 emulation instead of natively. slskd publishes native `arm64` images and a REST API that external tools (Kima's "slskd (external)" mode, soularr) bind to.
- **Kima's built-in P2P mode** — rejected: it keeps the Soulseek session and downloaded files inside one application, so nothing else in the stack (Beets tagging, future automation) can use either, and a second music front end would own the only network connection.
- **Soularr, to drive slskd from Lidarr's wanted list** — rejected: it automates *album* acquisition, which is what Prowlarr + Lidarr already do, at the cost of another container and two more API keys. The gap being closed is the single track, which Lidarr has no notion of monitoring.
- **Publishing `50300` on the host with a router port-forward** — rejected: inbound Soulseek connections would arrive at the house IP, defeating the reason qBittorrent is behind the VPN in the first place. A file-sharing network is exactly the traffic this stack already insists on tunnelling.
- **A second VPN session with its own forwarded port, dedicated to slskd** — not adopted, but recorded: it is the only route to a fully reachable and still-private client. Whether a PIA account can hold two simultaneous port forwards is unverified here, so it must be tested before anyone builds on it.
- **Depending on slskd's built-in VPN integration** — unavailable: it is gluetun-specific (it polls gluetun's control server), and this stack runs `thrnz/docker-wireguard-pia`.
- **Downloading into the existing Beets inbox** (`/data/music-inbox`) — rejected: `systemd/media-beets-import.timer` imports that directory hourly with `--group-albums`, so loose Soulseek singles would be forced into album matches. A separate root (`/soulseek-downloads`) keeps the two shapes of input apart.
- **Storing slskd's application data on the music share** — rejected: upstream lists SMB/NFS app directories, BTRFS and ZFS as unsupported for the SQLite data behind searches and transfers. `./data/slskd` stays on local disk.

## Consequences

- Individual tracks now have a path into the library, and it is a reviewed one: nothing is filed without a Beets prompt, so a mislabelled upload cannot silently overwrite a good library entry.
- The stack gains a second file-sharing service inside the VPN namespace. Recreating `vpn` orphans it exactly like qBittorrent/Prowlarr/FlareSolverr, so `docker compose up -d --force-recreate vpn flaresolverr prowlarr qbittorrent slskd` is the recovery command.
- Being firewalled is permanent unless the networking changes: expect slower queues, and expect sharing to stay disabled — a shared folder nobody can reach is not a courtesy.
- Soulseek needs a real account (`SLSK_USERNAME`/`SLSK_PASSWORD`) plus a non-default web UI login (`SLSKD_USERNAME`/`SLSKD_PASSWORD`), so two credential pairs now live in `.env`.
- Options edited in the slskd UI are written to `data/slskd/slskd.yml`, which becomes the file worth backing up; the SQLite state next to it is disposable.
- Soulseek filenames are uploader-typed, so Beets' `fromfilename` plugin is doing more work on this path than on the SpotiFLAC inbox — expect to correct matches by hand.
