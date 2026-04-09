# Homepage

Docker Compose stack for [**Homepage**](https://gethomepage.dev) — a self-hosted dashboard with service widgets, Docker integration, and resource monitoring.

## Prerequisites

- Docker and Docker Compose v2
- A Cloudflare Tunnel or reverse proxy if you want external HTTPS access

## Quick start

1. **Environment file**

   ```bash
   cp .env.example .env
   ```

   Edit `.env` and set at minimum:

   - `PUID` / `PGID` — host user/group (commonly `1000` / `1000`)
   - `HOMEPAGE_ALLOWED_HOSTS` — hostname(s) used to access the dashboard (e.g. `homepage.yourdomain.com` or `localhost:3003`)
   - Service URLs and API keys for any widgets you want to enable

2. **Start**

   ```bash
   docker compose up -d
   ```

3. Open `http://localhost:3003` (or your configured hostname).

## Ports

| Service  | Port (host) | Notes  |
|----------|-------------|--------|
| homepage | `3003`      | Web UI |

`dockerproxy` binds only to `127.0.0.1:2375` and is not exposed externally.

## Services

- **`homepage`** — the dashboard itself. Config lives in `./data/homepage/config/`, images in `./data/homepage/images/`.
- **`dockerproxy`** — [Tecnativa Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy) — exposes a read-only Docker API to Homepage without granting full socket access. `POST=0` ensures no write operations are possible.

## Configuration files

All config lives under `./data/homepage/config/` and is hot-reloaded — no container restart needed after edits.

| File             | Purpose                                    |
|------------------|--------------------------------------------|
| `settings.yaml`  | Global settings: layout, background, theme |
| `services.yaml`  | Service cards and widgets                  |
| `widgets.yaml`   | Info widgets (CPU, memory, disk, weather)  |
| `bookmarks.yaml` | Bookmark links                             |
| `docker.yaml`    | Docker integration (points to dockerproxy) |

## Background image

Images placed in `./data/homepage/images/` are available at `/images/filename.ext` in `settings.yaml`:

```yaml
background:
  image: /images/your-image.jpg
  blur: sm
```

The images directory maps to `/app/public/images` inside the container.

## Service variables

All sensitive values are passed via `HOMEPAGE_VAR_*` environment variables and referenced in `services.yaml` as `{{HOMEPAGE_VAR_*}}`. This keeps secrets out of the config files, which are committed to git.

## Docker integration

`docker.yaml` points Homepage at the dockerproxy sidecar:

```yaml
docker:
  host: dockerproxy
  port: 2375
```

Services in `services.yaml` can then use `server: docker` and `container: <name>` to show container status.

## Layout

- `compose.yml` — services
- `.env.example` — template (no secrets)
- `./data/homepage/config/` — YAML config files (committed)
- `./data/homepage/images/` — background and custom images (committed)
