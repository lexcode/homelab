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

Persistent state lives under **`./data/gotify/`** → `/app/data` in the container (SQLite database, uploaded images, optional cert material). Include this directory in backups.

## Ports

| Host (`GOTIFY_HTTP_PORT`) | Container |
| ------------------------- | --------- |
| default `8688`            | `80`      |

If you put Gotify behind [Nginx Proxy Manager](../proxy/README.md), publish only on localhost or stop publishing the host port and route through the reverse proxy on your LAN or tunnel.

## Homepage

The [Homepage](../homepage/) stack includes a **Gotify** card in `data/homepage/config/services.yaml` (Notifications group). Set `HOMEPAGE_VAR_GOTIFY_URL` and `HOMEPAGE_VAR_GOTIFY_KEY` in [`homepage/.env`](../homepage/.env.example) — the widget needs a [**client** token](https://gethomepage.dev/widgets/services/gotify/) from **Clients** in the Gotify admin UI (not the same as an *Application* token used for Sonarr).
