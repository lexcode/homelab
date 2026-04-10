# Proxy (Cloudflare Tunnel)

Docker Compose stack for [**cloudflared**](https://github.com/cloudflare/cloudflared) — runs a Cloudflare Tunnel that exposes internal services externally over HTTPS without opening any inbound ports on the router.

## Prerequisites

- A Cloudflare account with a domain
- A tunnel created in the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com) → Networks → Tunnels

## Quick start

1. **Create a tunnel** in the Cloudflare dashboard and copy the tunnel token.

2. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Set `CLOUDFLARED_TOKEN` to the token from the tunnel dashboard.

3. **Start**

   ```bash
   docker compose up -d
   ```

## Public hostnames

Configure public hostnames in the Cloudflare tunnel dashboard, pointing each subdomain to the internal service:

| Public hostname              | Internal service        |
| ---------------------------- | ----------------------- |
| `spotify.yourdomain.com`     | `http://localhost:3000` |
| `api-spotify.yourdomain.com` | `http://localhost:8080` |
| `homepage.yourdomain.com`    | `http://localhost:3003` |

Add more hostnames as you expose additional services.

## Homepage widget

The [Homepage](../homepage/) dashboard includes a `cloudflared` widget for this tunnel. In addition to `CLOUDFLARED_TOKEN` (the tunnel token used here), the widget requires a separate **API token** with `Account → Cloudflare Tunnel: Read` permission. See [homepage/README.md](../homepage/README.md#cloudflare-tunnel-widget) for details.

## Notes

- No ports are published — all traffic flows outbound through the Cloudflare network.
- `restart: unless-stopped` ensures the tunnel reconnects after a reboot.
- To restrict access by country, use Cloudflare WAF Custom Rules (Security → WAF → Custom Rules).

## Layout

- `compose.yml` — cloudflared service
- `.env.example` — template (no secrets)
