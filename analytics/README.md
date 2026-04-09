# Analytics (Your Spotify)

Docker Compose stack for [**Your Spotify**](https://github.com/Yooooomi/your_spotify) — a self-hosted Spotify listening statistics tracker. Stores your play history in MongoDB and exposes a web dashboard.

## Prerequisites

- Docker and Docker Compose v2
- A [Spotify developer app](https://developer.spotify.com/dashboard) with credentials and a registered redirect URI
- HTTPS access to the API endpoint (Spotify rejects plain HTTP redirect URIs on non-localhost addresses) — use a Cloudflare Tunnel or reverse proxy

## Quick start

1. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Edit `.env` and set at minimum:
   - `YOUR_SPOTIFY_API_ENDPOINT` — public HTTPS URL of the server (e.g. `https://api.spotify.yourdomain.com`)
   - `YOUR_SPOTIFY_CLIENT_ENDPOINT` — public HTTPS URL of the client UI (e.g. `https://spotify.yourdomain.com`)
   - `SPOTIFY_PUBLIC` / `SPOTIFY_SECRET` — from your Spotify developer dashboard

2. **Spotify developer app**

   In the [Spotify developer dashboard](https://developer.spotify.com/dashboard), add this exact redirect URI:

   ```
   https://api.spotify.yourdomain.com/oauth/spotify/callback
   ```

   The app appends `/oauth/spotify/callback` automatically — do not include it in `YOUR_SPOTIFY_API_ENDPOINT`.

3. **Start**

   ```bash
   docker compose up -d
   ```

4. Open `YOUR_SPOTIFY_CLIENT_ENDPOINT` in your browser and log in with Spotify.

## Ports (defaults)

| Service             | Port (host) | Notes                        |
| ------------------- | ----------- | ---------------------------- |
| your_spotify_server | `8080`      | API + OAuth callback handler |
| your_spotify_client | `3000`      | Web UI                       |

## Environment variables

| Variable                       | Purpose                                                                  |
| ------------------------------ | ------------------------------------------------------------------------ |
| `ANALYTICS_SUBNET`             | Docker bridge CIDR for `analyticsnetwork` (default `172.39.2.0/24`).     |
| `YOUR_SPOTIFY_SERVER_IP`       | Static IPv4 for the server container.                                    |
| `YOUR_SPOTIFY_CLIENT_IP`       | Static IPv4 for the client container.                                    |
| `YOUR_SPOTIFY_MONGO_IP`        | Static IPv4 for the MongoDB container.                                   |
| `YOUR_SPOTIFY_API_PORT`        | Host port for the API server (default `8080`).                           |
| `YOUR_SPOTIFY_CLIENT_PORT`     | Host port for the web UI (default `3000`).                               |
| `YOUR_SPOTIFY_API_ENDPOINT`    | Public HTTPS URL of the API server. Must match the Spotify redirect URI. |
| `YOUR_SPOTIFY_CLIENT_ENDPOINT` | Public HTTPS URL of the web client.                                      |
| `SPOTIFY_PUBLIC`               | Spotify app client ID.                                                   |
| `SPOTIFY_SECRET`               | Spotify app client secret.                                               |
| `TZ`                           | Timezone (e.g. `Europe/Dublin`).                                         |
| `YOUR_SPOTIFY_LOG_LEVEL`       | Server log level (default `info`).                                       |

## Architecture

- **`your_spotify_server`** — Node.js API that handles OAuth, ingests play history from Spotify, and serves data to the client. Data stored in MongoDB.
- **`your_spotify_client`** — React SPA served as a static bundle. `API_ENDPOINT` is baked into the JS bundle at container start — changing it requires a full container recreation (`docker compose up -d --force-recreate`), not just a restart.
- **`your_spotify_mongo`** — MongoDB instance. Data persisted in `./data/mongo`.

## DNS note

The server container makes outbound HTTPS calls to `accounts.spotify.com` for OAuth token exchange. Docker's embedded DNS resolver can fail for external hostnames on custom bridge networks (`EAI_AGAIN`). The recommended fix is to configure DNS at the Docker daemon level in `/etc/docker/daemon.json`:

```json
{
  "dns": ["1.1.1.1", "8.8.8.8"]
}
```

Then restart Docker:

```bash
sudo systemctl restart docker
```

## Cloudflare Tunnel setup

This stack is designed to run behind a Cloudflare Tunnel. Configure two public hostnames in the tunnel:

| Public hostname              | Service                          |
| ---------------------------- | -------------------------------- |
| `spotify.yourdomain.com`     | `http://localhost:3000` (client) |
| `api.spotify.yourdomain.com` | `http://localhost:8080` (server) |

If Cloudflare Web Analytics is enabled on your domain, the app's strict CSP will block the injected beacon script on the client page. Disable analytics injection for the client subdomain via a Cloudflare Configuration Rule or by removing the hostname from Web Analytics.

## ARM / Raspberry Pi note

The stack uses `mongo:4.4` which is required for ARM devices (Raspberry Pi). On x86_64, you can upgrade to `mongo:6` in `compose.yml`.

## Layout

- `compose.yml` — services and network
- `.env.example` — template (no secrets)
- `./data/mongo/` — MongoDB data (gitignored)
