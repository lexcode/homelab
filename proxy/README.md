# Proxy (Cloudflare Tunnel + Traefik + optional Tailscale Funnel)

Docker Compose stack for [**cloudflared**](https://github.com/cloudflare/cloudflared), [**Traefik**](https://doc.traefik.io/traefik/), and an optional [**Tailscale Funnel**](https://tailscale.com/kb/1223/funnel) sidecar. The tunnels expose services over HTTPS without opening inbound ports on the router. Traefik listens on the host (`80`, `443`) and is attached to each stack's **named Docker network** so it can proxy to containers by service name.

Two ingress paths feed into Traefik:

- **Cloudflare Tunnel** for most hostnames (admin UIs, dashboards, low-bandwidth apps).
- **Tailscale Funnel** for a single public hostname that should **bypass Cloudflare's network** — typically a media server, since Cloudflare's [Self-Serve Subscription Agreement §2.8](https://www.cloudflare.com/terms/) prohibits using the Cloudflare proxy to serve video.

**Networks:** Traefik joins `servarrnetwork`, `analyticsnetwork`, `monitoringnetwork`, `documentsnetwork`, `terminalnetwork`, `homepagenetwork`, `managementnetwork`, `adguardnetwork`, and `notificationsnetwork` as `external: true` networks. Those networks must already exist — start the corresponding stacks once before bringing up the proxy stack, or use the [`systemd/`](../systemd/) units (see the root [README.md](../README.md#boot-with-systemd-optional)) so `proxy.service` starts after the other stacks.

## Routing model

Traefik discovers routes two ways, matching where the backend actually lives:

- **Docker-routed backends** — a container defined in one of this repo's own stacks. Add `traefik.*` labels directly to that service in its own `compose.yml` (see any of `homepage/`, `media/`, `monitoring/`, `dns/`, `notifications/`, `management/` for examples). Traefik's Docker provider runs with `exposedByDefault=false`, so nothing is routed unless explicitly labeled — no stack accidentally becomes public.

  Minimum label set for a new Docker-routed backend:

  ```yaml
  labels:
    - traefik.enable=true
    - traefik.http.routers.<name>.rule=Host(`<name>.yourdomain.com`)
    - traefik.http.routers.<name>.entrypoints=websecure
    - traefik.http.routers.<name>.tls.certresolver=letsencrypt
    - traefik.http.services.<name>.loadbalancer.server.port=<container-internal-port>
  ```

  If the backend runs with `network_mode: service:vpn` (or any other shared-namespace sidecar pattern) it has no network attachment of its own — put the labels on the container that actually owns the network attachment instead (see `vpn` in `media/compose.yml`, which carries the router labels for both `prowlarr` and `qbittorrent`, each declaring its own `loadbalancer.server.port` explicitly).

- **External-routed backends** — a device or host with no Docker Compose stack in this repo (a NAS, a router, another machine on the LAN). Add a static entry to [`config/traefik/dynamic/external.yml`](./config/traefik/dynamic/external.yml) instead — Traefik's file provider watches that directory and reloads on change, no restart needed.

## TLS: DNS-01, not HTTP-01

Every router shares **one `*.yourdomain.com` wildcard certificate**, obtained via DNS-01 through Cloudflare's API (`CF_DNS_API_TOKEN`) rather than per-host HTTP-01. This isn't a style choice — most homelab subdomains resolve to a private LAN IP (DNS-only, not proxied through Cloudflare) or don't have a public DNS record at all, so they're not reachable from Let's Encrypt's HTTP-01 validation servers and per-host HTTP-01 simply cannot work for them. DNS-01 only needs the API token to prove control of the DNS zone — it doesn't care whether the specific hostname is publicly routable, so one wildcard covers every host uniformly regardless of how (or whether) it resolves publicly.

The wildcard's `domains` (main + SAN) only needs declaring **once** — see the `jellyfin-cloudflare` router in `config/traefik/dynamic/external.yml`. Every other router just references `tls.certresolver: letsencrypt` (or the equivalent label) and Traefik matches it against the already-obtained wildcard by SNI automatically. Don't redeclare `domains` elsewhere — it's unnecessary and would just trigger a redundant ACME request.

Tailscale Funnel's route (`jellyfin-tailscale`) is the one exception: it has no `tls:` block at all, since Tailscale terminates TLS at its own edge before traffic ever reaches Traefik, and `*.ts.net` isn't part of your domain's zone anyway — the wildcard couldn't cover it even if requested.

## Prerequisites

- A Cloudflare account with a domain
- A tunnel created in the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com) → Networks → Tunnels
- A Cloudflare API token scoped to `Zone:DNS:Edit` on your zone (Cloudflare dashboard → My Profile → API Tokens → Create Token → "Edit zone DNS" template) — Traefik uses this for DNS-01 certificate validation. See [TLS: DNS-01, not HTTP-01](#tls-dns-01-not-http-01) for why.
- Other homelab stacks that define the external networks above (at least once) before the proxy stack, if you rely on Traefik's cross-network routing

## Quick start

1. **Create a tunnel** in the Cloudflare dashboard and copy the tunnel token.

2. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Set `CLOUDFLARED_TOKEN` to the token from the tunnel dashboard, `ACME_EMAIL` to an address for Let's Encrypt expiry notices, and `CF_DNS_API_TOKEN` to the DNS-edit token from Prerequisites above.

3. **Start other stacks first** (or use systemd ordering) so external Docker networks exist.

4. **Start**

   ```bash
   docker compose up -d
   ```

   This starts Cloudflare Tunnel and Traefik only. Tailscale Funnel is excluded by default through the `tailscale` Compose profile.

5. **Traefik dashboard:** bound to `127.0.0.1:8091` only — never routed through Cloudflare Tunnel or Tailscale Funnel. (Port `8080` is already used by qbittorrent's WebUI in the `media/` stack.) Reach it with `ssh -L 8091:localhost:8091 <host>` then open `http://localhost:8091/dashboard/`.

## Public hostnames

In the Cloudflare tunnel dashboard, each public hostname's **origin** is whatever address **the `cloudflared` process** can reach.

Because **cloudflared runs in Docker** in this stack (same Compose file as Traefik, both on `proxynetwork`), **`http://127.0.0.1:80` is wrong** — inside that container, `127.0.0.1` is the tunnel container itself, not the host and not Traefik.

**Tunnel → Traefik (recommended here):** set the origin to **`http://traefik:80`**. Port **80** is correct: that is Traefik's HTTP listener inside its container, which redirects to `websecure` (443) internally. Every public hostname uses this same origin — Traefik does the host-based routing from there using each backend's `Host()` rule (see [Routing model](#routing-model) above), rather than a per-hostname origin.

If you ever run **cloudflared on the host** instead, then `http://127.0.0.1:80` can reach Traefik via the published host port `80`.

## Tailscale Funnel (optional)

[**Tailscale Funnel**](https://tailscale.com/kb/1223/funnel) publishes a single service to the public internet through Tailscale's edge. No router port forward, no home IP exposed, no Cloudflare in the traffic path — which is what you want for streaming (Jellyfin, Plex, Navidrome, etc.) because the Cloudflare free/Pro/Business terms forbid proxying video through their CDN.

In this stack it runs alongside `cloudflared` and forwards incoming Funnel traffic to Traefik on `proxynetwork`, so Traefik keeps handling all host-based routing the same way it does for the Cloudflare Tunnel.

### Prerequisites

- A [Tailscale](https://tailscale.com) account (free personal tier works)
- In the admin console → **DNS** tab → **MagicDNS** and **HTTPS Certificates** enabled
- In **Access Controls**, Funnel permitted in the ACL, for example:

  ```json
  {
    "nodeAttrs": [
      { "target": ["*"], "attr": ["funnel"] }
    ]
  }
  ```

### Setup

1. **Create an auth key** at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) (Reusable = yes, Ephemeral = no, optional tag `tag:funnel`). Copy the `tskey-auth-…` value.

2. **Environment file** — add these to `proxy/.env`:

   ```bash
   TS_AUTHKEY=tskey-auth-xxxxxxxxxxxxxxxxxx
   TS_HOSTNAME=jellyfin
   ```

   `TS_HOSTNAME` becomes the MagicDNS name `https://<TS_HOSTNAME>.<tailnet>.ts.net`.

3. **Serve config** — `config/tailscale-funnel/serve.json` in this folder is the Funnel config. The template forwards `:443` to `http://traefik:8082` and `${TS_CERT_DOMAIN}` is substituted automatically with the container's tailnet FQDN at runtime. Traefik has a dedicated `tailscale` entrypoint (port `8082`, not published to the host — only reachable over `proxynetwork`) for this traffic, separate from `web`/`websecure`: Tailscale already terminates TLS at its own edge and forwards decrypted HTTP, so this traffic must skip both the `web` entrypoint's HTTP→HTTPS redirect and Traefik's own ACME resolver (a `.ts.net` hostname has no public DNS Let's Encrypt could validate against anyway). Leave the serve config as-is to go through Traefik, or edit the `Proxy` URL to hit a service directly.

4. **Bring it up**

   ```bash
   cd proxy
   docker compose --profile tailscale up -d
   docker logs -f tailscale-funnel
   ```

   This starts or updates the complete proxy stack with Funnel enabled. You'll
   see a line like `Available on the internet: https://jellyfin.tail-xxxx.ts.net/`.
   That is your public URL.

   The repository's `proxy.service` uses the default Compose startup and does
   not enable Funnel. Enabling Funnel at boot requires a separately reviewed
   systemd customization.

5. **Add the Funnel hostname as a router** — since the Funnel target (Jellyfin, in this repo's case) is an external-routed backend, add its Funnel hostname as another router pointing at the same service in [`config/traefik/dynamic/external.yml`](./config/traefik/dynamic/external.yml) (see the `jellyfin-tailscale` router for the working example — same `service:` block as the Cloudflare-facing router, just a different `Host()` rule and no forced SSL needed since Tailscale terminates TLS at its own edge).

6. **Custom domain (optional)** — if you want `jellyfin.yourdomain.com` instead of the `.ts.net` URL, add a CNAME in Cloudflare DNS (**grey cloud / DNS-only**) pointing to `<TS_HOSTNAME>.<tailnet>.ts.net`, then register that custom domain in the Tailscale admin → DNS tab. See [Tailscale Serve custom domains](https://tailscale.com/kb/1312/serve#custom-domains).

### Client setup (what to tell the people you share with)

1. Install the **Jellyfin app** on their phone or TV (Play Store / App Store / Android TV / Google TV / Fire TV / Apple TV).
2. On first launch → *Connect to Server* → paste the Funnel URL (or custom domain).
3. Log in. Casting from phone → Chromecast/Google TV/Apple TV works because the URL is publicly reachable HTTPS — the TV doesn't need Tailscale installed.

### Why kernel networking (`TS_USERSPACE=false`)

Userspace mode works without `/dev/net/tun` and `NET_ADMIN` but trades throughput. Funnel already proxies through Tailscale's edge, so the kernel-networking container on a Raspberry Pi 5 / Linux host keeps streaming smooth. If you are on a platform where `/dev/net/tun` is awkward (Docker Desktop Mac/Windows, rootless Docker without TUN), flip to `TS_USERSPACE=true` in `compose.yml` and drop the `devices`/`cap_add` keys.

### State, auth, and resets

- State persists under `data/tailscale-funnel/`. After the first successful login you can remove or rotate `TS_AUTHKEY` in `.env` and the container will keep running (`TS_AUTH_ONCE=true`).
- To fully re-register (for example after deleting the device from the tailnet), stop the container, delete `data/tailscale-funnel/`, put a fresh auth key in `.env`, and bring it back up.

### Notes and limits

- Funnel is **HTTPS only** on ports `443`, `8443`, or `10000`. The serve config here uses `443`.
- Tailscale applies **fair-use** bandwidth policies on Funnel. 1 movie/day scale is comfortable; if you ever stream more and hit throttling, fall back to a grey-cloud DNS A record + DDNS container updating the A record (router must support port forwarding 80/443, and you must not be behind CGNAT).
- Tailscale Funnel is **independent of `cloudflared`** — you can enable or disable either path without touching the other.

## Migrating from Nginx Proxy Manager

This stack replaced NPM in place. If you're bringing an existing NPM-fronted homelab across:

1. Recreate each of NPM's proxy hosts as either a Docker-label route (if the backend is a container in this repo) or an entry in `config/traefik/dynamic/external.yml` (if it isn't) — see [Routing model](#routing-model).
2. Update the Cloudflare Tunnel's public hostname origins in the Zero Trust dashboard from `http://nginx-proxy-manager:80` to `http://traefik:80` (one edit covers every hostname, since Traefik does the per-hostname routing itself).
3. Update `config/tailscale-funnel/serve.json`'s `Proxy` value the same way, if you run Tailscale Funnel.
4. Stop `nginx-proxy-manager` before starting `traefik` — both bind `80`/`443` and can't run together. Expect a brief gap while Traefik's DNS-01 challenge issues the wildcard certificate (NPM's certs aren't migrated; Traefik starts from a fresh ACME account).
5. NPM's `block_exploits` (its built-in "block common exploits" nginx snippet) has no Traefik equivalent here and was not replicated — see [ADR-0001](../docs/adr/0001-replace-npm-with-traefik.md) for why.
6. NPM's data directory (`data/nginx-proxy-manager/`) is left on disk, untouched, as a rollback path — delete it manually once you're confident you don't need it.

## Homepage widget

The [Homepage](../homepage/) dashboard includes a `cloudflared` widget for this tunnel. In addition to `CLOUDFLARED_TOKEN` (the tunnel token used here), the widget requires a separate **API token** with `Account → Cloudflare Tunnel: Read` permission. See [homepage/README.md](../homepage/README.md#cloudflare-tunnel-widget) for details.

## Notes

- **cloudflared** uses outbound connections only; no inbound router port forward is required.
- **Traefik** publishes `80` and `443` on the host for local and tunnel-terminated HTTP(S), and `8091` on `127.0.0.1` only for its dashboard (`8080` is taken by qbittorrent's WebUI).
- **DNS / AdGuard Home** (LAN resolver / ad blocking) is a separate stack: [`dns/`](../dns/README.md). The **bridge** setup publishes the web UI on **`ADGUARD_HTTP_PORT`** (default **3005**) so it does not fight Traefik for **80**/**443** on the same host.
- `restart: unless-stopped` ensures the tunnel reconnects after a reboot.
- To restrict access by country, use Cloudflare WAF Custom Rules (Security → WAF → Custom Rules). Optional for public services; not required for basic tunnel operation.

## Layout

- `compose.yml` — `cloudflared`, `traefik`, optional `tailscale-funnel`
- `config/traefik/dynamic/external.yml` — static routes for external-routed backends (committed, no secrets)
- `config/tailscale-funnel/serve.json` — Tailscale Funnel serve config template (committed)
- `data/traefik/letsencrypt/` — Traefik's ACME account and certificates (not committed)
- `data/tailscale-funnel/` — Tailscale state dir (not committed)
- `data/nginx-proxy-manager/` — former NPM data and Let's Encrypt certs, left in place as rollback insurance (not committed)
- `.env.example` — template (no secrets)
