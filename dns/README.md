# DNS (LAN resolvers / filtering)

Docker Compose stack for LAN DNS with ad blocking and filtering. Right now it runs [**AdGuard Home**](https://github.com/AdguardTeam/AdGuardHome); the directory is named **`dns/`** so you can add another resolver later (for example **Pi-hole**) without mixing this with HTTP reverse proxying.

**Default networking:** a **bridge** network (`172.39.5.0/24`) with **published ports** on the Docker host. Clients use the **host’s LAN IP** for DNS (and the mapped HTTP port for the UI).

**Upstream image docs:** [adguard/adguardhome on Docker Hub](https://hub.docker.com/r/adguard/adguardhome) — volumes (`work` / `conf`), full port list, updates, dev tags (`edge` / `beta`), DHCP on `host` networking, and **systemd-resolved** (`DNSStubListener`) are documented there.

## Image updates

AdGuard Home uses a reviewed release tag and immutable digest. Back up
`./data/conf` and `./data/work`, then follow the repository
[image update policy](../docs/IMAGE-UPDATES.md) and verify DNS from a LAN client.

## Why `dns/` and not `proxy/`?

[`proxy/`](../proxy/) is **Cloudflare Tunnel + Nginx Proxy Manager** (HTTPS, hostnames, upstream routing). This stack is **DNS** (UDP/TCP 53, filtering, optional DHCP). They solve different problems. Putting DNS inside `proxy/` would bundle unrelated services and make port planning harder (NPM already uses host `80`/`443`/`81`).

## Adding Pi-hole (or another DNS stack) later

You typically run **one** DNS server bound to **port 53** on a given host. Options:

- **Replace** AdGuard with Pi-hole in `compose.yml` (swap the service block and volumes), or
- Run Pi-hole on **another machine** or **another host port** (e.g. `5353`) with a second service in this file or a separate compose overlay—document ports carefully.

A second compose file such as `compose.pihole.yml` merged with `docker compose -f compose.yml -f compose.pihole.yml` also works if you want to keep definitions split.

## Prerequisites

- Docker and Docker Compose v2
- If you bind **DNS on host port 53**, nothing else on that machine may use it. **systemd-resolved** often binds `127.0.0.53:53`, which blocks the container from using host port 53. Options: use another host port via `ADGUARD_DNS_PORT`, or follow the **`resolved`** section on [Docker Hub](https://hub.docker.com/r/adguard/adguardhome) (disable `DNSStubListener`, point `DNS` at `127.0.0.1`, symlink `resolv.conf`, reload `systemd-resolved`). Non-standard DNS ports work poorly for some LAN clients; **UDP/TCP 53** is what most devices expect.

## Quick start (default `compose.yml`)

1. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Adjust `ADGUARD_SUBNET` / `ADGUARD_IP` if they clash with other stacks or your LAN (see the root [README.md](../README.md)). Change `ADGUARD_DNS_PORT` or `ADGUARD_HTTP_PORT` if ports are already in use.

2. **Start**

   ```bash
   docker compose up -d
   ```

3. **Setup wizard:** open `http://<host-lan-ip>:3005` (or whatever you set for `ADGUARD_HTTP_PORT`). Complete the guided setup; AdGuard will store settings under `./data/conf` and `./data/work`.

4. **Point clients at this server:** on your router or each device, set the DNS server to your Docker **host’s LAN IP** (when using `ADGUARD_DNS_PORT=53`). Use AdGuard’s **Setup guide** in the UI for per-OS hints.

## Router: UniFi Dream Machine Pro

LAN DNS is handed out via **DHCP** on the **Dream Machine Pro** with two resolvers for redundancy:

| Role              | Host                                                                        |
| ----------------- | --------------------------------------------------------------------------- |
| **Primary DNS**   | AdGuard Home on **Raspberry Pi 5** (this repo’s [`dns/`](.) Compose stack)  |
| **Secondary DNS** | AdGuard Home on **Unraid** (separate install, e.g. Community Apps template) |

Reserve **static LAN IPs** for both AdGuard endpoints in UniFi so they never drift. Keep **blocklists and policy** aligned between the two instances if you want consistent filtering; clients may **query both** primaries/secondaries depending on OS behavior, so both dashboards can show traffic even when the network is healthy.

## Ports and coexistence with `proxy/`

| Host port (defaults)                   | Purpose                                 |
| -------------------------------------- | --------------------------------------- |
| `ADGUARD_DNS_PORT` → container `53`    | DNS (TCP/UDP)                           |
| `ADGUARD_HTTP_PORT` → container `3000` | Web UI (initial and ongoing HTTP admin) |

[Nginx Proxy Manager](../proxy/README.md) uses host `80`, `443`, and `81`. This stack defaults the AdGuard web UI to **3005** so you can run both on one machine without a port collision.

If you later enable HTTPS for the AdGuard UI, DNS-over-HTTPS, or DNS-over-TLS inside AdGuard, add the image’s additional port mappings in `compose.yml` (see the [Docker Hub quick start](https://hub.docker.com/r/adguard/adguardhome))—do not blindly map host `80`/`443` if NPM is already there.

Optional ports from the upstream image (add only what you enable in AdGuard’s settings):

| Map (host → container)                        | Purpose                                      |
| --------------------------------------------- | -------------------------------------------- |
| `67:67/udp`, `68:68/tcp`, `68:68/udp`         | DHCP (see below)                             |
| `853:853/tcp`                                 | DNS-over-TLS                                 |
| `784:784/udp`, `853:853/udp`, `8853:8853/udp` | DNS-over-QUIC (often only one or two needed) |
| `5443:5443/tcp`, `5443:5443/udp`              | DNSCrypt                                     |

**DHCP in Docker:** AdGuard’s DHCP server expects **`--network host`** on Linux (no `-p` port mapping). This stack uses a bridge network instead; if you need built-in DHCP, run a separate `docker run`/compose override with `network_mode: host` per [Docker Hub](https://hub.docker.com/r/adguard/adguardhome) (not supported on Docker Desktop Mac/Windows).

## Layout

- `compose.yml` — bridge + published ports
- `data/work/`, `data/conf/` — AdGuard Home (not committed)
- `.env.example` — bridge template

## Environment variables (`compose.yml`)

| Variable            | Purpose                                                            |
| ------------------- | ------------------------------------------------------------------ |
| `ADGUARD_SUBNET`    | Docker bridge CIDR for `adguardnetwork` (default `172.39.5.0/24`). |
| `ADGUARD_IP`        | Static container IPv4 on that bridge (default `172.39.5.2`).       |
| `ADGUARD_DNS_PORT`  | Host port published to container DNS port `53`.                    |
| `ADGUARD_HTTP_PORT` | Host port for the web UI (container `3000`).                       |

## Migrating from `adguard/`

If you had data under `adguard/data/`, move it to `dns/data/` (`work/` and `conf/`) and start the stack from `dns/`.
