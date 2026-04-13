# Proxy (Cloudflare Tunnel + Nginx Proxy Manager)

Docker Compose stack for [**cloudflared**](https://github.com/cloudflare/cloudflared) and [**Nginx Proxy Manager**](https://nginxproxymanager.com/) (NPM). The tunnel exposes services over HTTPS without opening inbound ports on the router. NPM listens on the host (`80`, `443`, `81` for the admin UI) and is attached to each stack’s **named Docker network** so you can proxy to containers by service name (for example `http://homepage:3000`) instead of publishing every app on the host.

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

## Homepage widget

The [Homepage](../homepage/) dashboard includes a `cloudflared` widget for this tunnel. In addition to `CLOUDFLARED_TOKEN` (the tunnel token used here), the widget requires a separate **API token** with `Account → Cloudflare Tunnel: Read` permission. See [homepage/README.md](../homepage/README.md#cloudflare-tunnel-widget) for details.

## Notes

- **cloudflared** uses outbound connections only; no inbound router port forward is required.
- **NPM** publishes `80`, `443`, and `81` on the host for local and tunnel-terminated HTTP(S).
- `restart: unless-stopped` ensures the tunnel reconnects after a reboot.
- To restrict access by country, use Cloudflare WAF Custom Rules (Security → WAF → Custom Rules). Optional for public services; not required for basic tunnel operation.

## Layout

- `compose.yml` — `cloudflared` and `nginx-proxy-manager`
- `data/nginx-proxy-manager/` — NPM data and Let’s Encrypt (not committed)
- `.env.example` — template (no secrets)
