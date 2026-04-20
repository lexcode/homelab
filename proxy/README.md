# Proxy (Cloudflare Tunnel + Nginx Proxy Manager + optional Tailscale Funnel)

Docker Compose stack for [**cloudflared**](https://github.com/cloudflare/cloudflared), [**Nginx Proxy Manager**](https://nginxproxymanager.com/) (NPM), and an optional [**Tailscale Funnel**](https://tailscale.com/kb/1223/funnel) sidecar. The tunnels expose services over HTTPS without opening inbound ports on the router. NPM listens on the host (`80`, `443`, `81` for the admin UI) and is attached to each stack’s **named Docker network** so you can proxy to containers by service name (for example `http://homepage:3000`) instead of publishing every app on the host.

Two ingress paths feed into NPM:

- **Cloudflare Tunnel** for most hostnames (admin UIs, dashboards, low-bandwidth apps).
- **Tailscale Funnel** for a single public hostname that should **bypass Cloudflare’s network** — typically a media server, since Cloudflare’s [Self-Serve Subscription Agreement §2.8](https://www.cloudflare.com/terms/) prohibits using the Cloudflare proxy to serve video.

**Networks:** NPM joins `servarrnetwork`, `analyticsnetwork`, `monitoringnetwork`, `documentsnetwork`, `terminalnetwork`, and `homepagenetwork` as `external: true` networks. Those networks must already exist—start the corresponding stacks once before bringing up the proxy stack, or use the [`systemd/`](../systemd/) units (see the root [README.md](../README.md#boot-with-systemd-optional)) so `proxy.service` starts after the other stacks.

## Prerequisites

- A Cloudflare account with a domain
- A tunnel created in the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com) → Networks → Tunnels
- Other homelab stacks that define the external networks above (at least once) before the proxy stack, if you rely on NPM’s cross-network routing

## Quick start

1. **Create a tunnel** in the Cloudflare dashboard and copy the tunnel token.

2. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Set `CLOUDFLARED_TOKEN` to the token from the tunnel dashboard.

3. **Start other stacks first** (or use systemd ordering) so external Docker networks exist.

4. **Start**

   ```bash
   docker compose up -d
   ```

5. **NPM admin:** open `http://<host-ip>:81` and complete the first-run wizard.

## Public hostnames

In the Cloudflare tunnel dashboard, each public hostname’s **origin** is whatever address **the `cloudflared` process** can reach.

Because **cloudflared runs in Docker** in this stack (same Compose file as NPM, both on `proxynetwork`), **`http://127.0.0.1:80` is wrong** — inside that container, `127.0.0.1` is the tunnel container itself, not the host and not NPM.

**Tunnel → NPM (recommended here):** set the origin to **`http://nginx-proxy-manager:80`**. Port **80** is correct: that is NPM’s HTTP listener inside its container. Then define each hostname and upstream in NPM (e.g. client `http://your_spotify_client:3000`, API `http://your_spotify_server:8080` — **8080** is the API container port, not the host `YOUR_SPOTIFY_API_PORT`).

If you ever run **cloudflared on the host** instead, then `http://127.0.0.1:80` can reach NPM via the published host port `80`.

**Tunnel → published host port (bypass NPM):** from inside the tunnel container, **`localhost` is not the host** — use your Docker bridge gateway IP, `host.docker.internal` (where Docker provides it), or the host’s LAN IP, plus the published port.

**Example — tunnel → NPM** (origins for this repo’s containerized tunnel):

| Public hostname              | Tunnel origin (→ NPM HTTP)      |
| ---------------------------- | ------------------------------- |
| `spotify.yourdomain.com`     | `http://nginx-proxy-manager:80` |
| `api-spotify.yourdomain.com` | `http://nginx-proxy-manager:80` |
| `homepage.yourdomain.com`    | `http://nginx-proxy-manager:80` |

**Example — tunnel → host ports directly** (no NPM hop; use the **published** host ports from [analytics/.env](../analytics/.env.example)). These `localhost` URLs only work if **cloudflared runs on the host**. If it runs in this Compose stack, replace `localhost` with a host-reachable address (bridge gateway, LAN IP, or `host.docker.internal` where available):

| Public hostname              | Internal service        |
| ---------------------------- | ----------------------- |
| `spotify.yourdomain.com`     | `http://localhost:3000` |
| `api-spotify.yourdomain.com` | `http://localhost:8282` |
| `homepage.yourdomain.com`    | `http://localhost:3003` |

`YOUR_SPOTIFY_API_PORT` defaults to `8080` in Compose if unset; this repo’s `.env.example` sets **8282** on the host (maps to container `8080`).

Add more hostnames as you expose additional services.

## Tailscale Funnel (optional)

[**Tailscale Funnel**](https://tailscale.com/kb/1223/funnel) publishes a single service to the public internet through Tailscale’s edge. No router port forward, no home IP exposed, no Cloudflare in the traffic path — which is what you want for streaming (Jellyfin, Plex, Navidrome, etc.) because the Cloudflare free/Pro/Business terms forbid proxying video through their CDN.

In this stack it runs alongside `cloudflared` and forwards incoming Funnel traffic to NPM on `proxynetwork`, so NPM keeps handling all host/path routing the same way it does for the Cloudflare Tunnel.

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

3. **Serve config** — `config/tailscale-funnel/serve.json` in this folder is the Funnel config. The template forwards `:443` to NPM and `${TS_CERT_DOMAIN}` is substituted automatically with the container’s tailnet FQDN at runtime. Leave it as-is to go through NPM, or edit the `Proxy` URL to hit a service directly (for example `http://host.docker.internal:8096` for a Jellyfin running on the Docker host, or a LAN URL if the media server lives on another machine such as Unraid).

4. **Bring it up**

   ```bash
   cd proxy
   docker compose up -d tailscale-funnel
   docker logs -f tailscale-funnel
   ```

   You’ll see a line like `Available on the internet: https://jellyfin.tail-xxxx.ts.net/`. That is your public URL.

5. **Add a Proxy Host in NPM** for the Funnel hostname so NPM routes it to the right backend:

   | NPM field         | Value                                      |
   | ----------------- | ------------------------------------------ |
   | Domain Names      | `jellyfin.tail-xxxx.ts.net` (+ custom CNAME if used) |
   | Scheme            | `http`                                     |
   | Forward Hostname  | LAN IP or docker service name of Jellyfin  |
   | Forward Port      | `8096` (Jellyfin default)                  |
   | Block Common Exploits | on                                     |
   | Websockets Support    | on (required for Jellyfin casting)     |
   | SSL               | none — Tailscale terminates TLS at the edge |

6. **Custom domain (optional)** — if you want `jellyfin.yourdomain.com` instead of the `.ts.net` URL, add a CNAME in Cloudflare DNS (**grey cloud / DNS-only**) pointing to `<TS_HOSTNAME>.<tailnet>.ts.net`, then register that custom domain in the Tailscale admin → DNS tab. See [Tailscale Serve custom domains](https://tailscale.com/kb/1312/serve#custom-domains).

### Client setup (what to tell the people you share with)

1. Install the **Jellyfin app** on their phone or TV (Play Store / App Store / Android TV / Google TV / Fire TV / Apple TV).
2. On first launch → *Connect to Server* → paste the Funnel URL (or custom domain).
3. Log in. Casting from phone → Chromecast/Google TV/Apple TV works because the URL is publicly reachable HTTPS — the TV doesn’t need Tailscale installed.

### Why kernel networking (`TS_USERSPACE=false`)

Userspace mode works without `/dev/net/tun` and `NET_ADMIN` but trades throughput. Funnel already proxies through Tailscale’s edge, so the kernel-networking container on a Raspberry Pi 5 / Linux host keeps streaming smooth. If you are on a platform where `/dev/net/tun` is awkward (Docker Desktop Mac/Windows, rootless Docker without TUN), flip to `TS_USERSPACE=true` in `compose.yml` and drop the `devices`/`cap_add` keys.

### State, auth, and resets

- State persists under `data/tailscale-funnel/`. After the first successful login you can remove or rotate `TS_AUTHKEY` in `.env` and the container will keep running (`TS_AUTH_ONCE=true`).
- To fully re-register (for example after deleting the device from the tailnet), stop the container, delete `data/tailscale-funnel/`, put a fresh auth key in `.env`, and bring it back up.

### Notes and limits

- Funnel is **HTTPS only** on ports `443`, `8443`, or `10000`. The serve config here uses `443`.
- Tailscale applies **fair-use** bandwidth policies on Funnel. 1 movie/day scale is comfortable; if you ever stream more and hit throttling, fall back to a grey-cloud DNS A record + DDNS container updating the A record (router must support port forwarding 80/443, and you must not be behind CGNAT).
- Tailscale Funnel is **independent of `cloudflared`** — you can enable or disable either path without touching the other.

## Homepage widget

The [Homepage](../homepage/) dashboard includes a `cloudflared` widget for this tunnel. In addition to `CLOUDFLARED_TOKEN` (the tunnel token used here), the widget requires a separate **API token** with `Account → Cloudflare Tunnel: Read` permission. See [homepage/README.md](../homepage/README.md#cloudflare-tunnel-widget) for details.

## Notes

- **cloudflared** uses outbound connections only; no inbound router port forward is required.
- **NPM** publishes `80`, `443`, and `81` on the host for local and tunnel-terminated HTTP(S).
- **DNS / AdGuard Home** (LAN resolver / ad blocking) is a separate stack: [`dns/`](../dns/README.md). The **bridge** setup publishes the web UI on **`ADGUARD_HTTP_PORT`** (default **3005**) so it does not fight NPM for **80**/**443** on the same host.
- `restart: unless-stopped` ensures the tunnel reconnects after a reboot.
- To restrict access by country, use Cloudflare WAF Custom Rules (Security → WAF → Custom Rules). Optional for public services; not required for basic tunnel operation.

## Layout

- `compose.yml` — `cloudflared`, `nginx-proxy-manager`, optional `tailscale-funnel`
- `config/tailscale-funnel/serve.json` — Tailscale Funnel serve config template (committed)
- `data/nginx-proxy-manager/` — NPM data and Let’s Encrypt (not committed)
- `data/tailscale-funnel/` — Tailscale state dir (not committed)
- `.env.example` — template (no secrets)
