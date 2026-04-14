# Notifications (push server)

Docker Compose stack for [**Gotify**](https://github.com/gotify/server): a self-hosted REST/WebSocket API for sending push notifications to phones and desktops. The directory is named **`notifications/`** so you can add another notifier or related tooling later without mixing it with monitoring or the dashboard.

**Upstream:** [Installation](https://gotify.net/docs/install), [Configuration](https://gotify.net/docs/config).

## Quick start

1. **Environment**

   ```bash
   cp .env.example .env
   ```

   Set `GOTIFY_DEFAULTUSER_PASS` before the first `docker compose up` if you do not want the default placeholder. The password is applied only on initial database creation.

2. **Start**

   ```bash
   docker compose up -d
   ```

3. **Web UI:** `http://<host-lan-ip>:8688` (or `GOTIFY_HTTP_PORT`). Log in as **`admin`** with the password from `.env`, then change it in the UI.

4. **Clients:** install a [Gotify client](https://gotify.net/) and point it at your server URL; create **Applications** in the UI to obtain tokens for your scripts and automation.

## Data and backups

Persistent state lives under **`./data/gotify/`** and **`./data/igotify/`** (bind-mounted to the containers’ `/app/data`). Gotify holds the SQLite DB and uploads; iGotify holds assistant state. Include both in backups.

## Ports

| Service | Host (`GOTIFY_HTTP_PORT` / `IGOTIFY_HTTP_PORT`) | Container |
| ------- | ----------------------------------------------- | --------- |
| Gotify  | default `8688`                                  | `80`      |
| iGotify assistant | default `8681`                          | `8080`    |

If you put Gotify behind [Nginx Proxy Manager](../proxy/README.md), publish only on localhost or stop publishing the host port and route through the reverse proxy on your LAN or tunnel.

### iGotify assistant “UI” (Scalar API)

The assistant mounts the HTTP API under **`/api`** (see [upstream `Program.cs`](https://github.com/androidseb25/iGotify-Notification-Assistent/blob/main/Program.cs)). There is no useful page at the root URL.

- **API docs (Scalar):** `http://<host>:8681/api/scalar/v1` (adjust host port if you changed `IGOTIFY_HTTP_PORT`).
- **Version JSON:** `http://<host>:8681/api/Version`

The log line `Failed to determine the https port for redirect` is a common ASP.NET warning when only HTTP is used; it does not mean the service is down.

**Local network:** use the Docker host’s LAN IP (not only `127.0.0.1`) when opening from another machine. Ensure the host firewall allows the chosen port.

**Networking:** Docker bridge **`notificationsnetwork`** (same pattern as `homepagenetwork` / `terminalnetwork` in this repo). Services reach each other at **`http://gotify:80`** for `GOTIFY_URLS`.

**Compose layout** follows the [upstream `docker-compose.yaml`](https://github.com/androidseb25/iGotify-Notification-Assistent/blob/main/docker-compose.yaml) (healthchecks, images, `security_opt`). This repo uses **bind mounts** and **ports** `8688` / `8681` by default instead of named volumes / `8680`. If `igotify` reports **unhealthy** but the app works, the upstream healthcheck uses `/Version`; if your image only serves `/api/Version`, change the healthcheck `test` in `compose.yml` to that path.

## Homepage

The [Homepage](../homepage/) stack includes a **Gotify** card in `data/homepage/config/services.yaml` (Notifications group). Set `HOMEPAGE_VAR_GOTIFY_URL` and `HOMEPAGE_VAR_GOTIFY_KEY` in [`homepage/.env`](../homepage/.env.example) — the widget needs a [**client** token](https://gethomepage.dev/widgets/services/gotify/) from **Clients** in the Gotify admin UI (not the same as an *Application* token used for Sonarr).
