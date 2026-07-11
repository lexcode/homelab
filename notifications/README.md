# Notifications (push server)

Docker Compose stack combining [**Gotify**](https://github.com/gotify/server) (self-hosted push server), [**iGotify Notification Assistant**](https://github.com/androidseb25/iGotify-Notification-Assistent) (optional, for iOS lock-screen push via SecNtfy/APNs), and [**changedetection.io**](https://github.com/dgtlmoon/changedetection.io) (web-page change monitoring with Gotify alert support). The directory is named **`notifications/`** so you can add other notifiers later without mixing them with monitoring or the dashboard.

**Upstream:** [Gotify install](https://gotify.net/docs/install), [Gotify config](https://gotify.net/docs/config), [iGotify wiki](https://github.com/androidseb25/iGotify-Notification-Assistent/wiki).

## Quick start

1. **Environment**

   ```bash
   cp .env.example .env
   ```

   Set `GOTIFY_DEFAULTUSER_PASS` to a strong, unique value before the first `docker compose up`. Compose refuses to render the stack when this value is missing or empty.

   Gotify applies this variable only when it creates the administrator account on first run. For an existing installation, changing `.env` does not update the password already stored in Gotify's database; rotate that password through the Gotify UI or the supported upstream procedure.

2. **Create the folder structure**

   ```bash
   mkdir -p \
     data/gotify \
     data/igotify \
     data/changedetection
   ```

3. **Start**

   ```bash
   docker compose up -d
   ```

4. **Web UI:** `http://<host-lan-ip>:8688` (or `GOTIFY_HTTP_PORT`). Log in as **`admin`** with the password from `.env`, then change it in the UI.

5. **Clients:** install a [Gotify client](https://gotify.net/) and point it at your server URL; create **Applications** in the UI to obtain tokens for your scripts and automation.

## Data and backups

Persistent state lives under **`./data/gotify/`**, **`./data/igotify/`**, and **`./data/changedetection/`** (bind-mounted into their respective containers). Gotify holds the SQLite DB and uploads; iGotify holds assistant state; changedetection holds its datastore. Include all three in backups.

## Ports

| Service              | Host port                                       | Container |
| -------------------- | ----------------------------------------------- | --------- |
| Gotify               | `GOTIFY_HTTP_PORT` default `8688`               | `80`      |
| iGotify assistant    | `IGOTIFY_HTTP_PORT` default `8681`              | `8080`    |
| changedetection.io   | `5001` (hardcoded)                              | `5000`    |

If you put Gotify behind [Nginx Proxy Manager](../proxy/README.md), publish only on localhost or stop publishing the host port and route through the reverse proxy on your LAN or tunnel.

### iGotify assistant “UI” (Scalar API)

The assistant mounts the HTTP API under **`/api`** (see [upstream `Program.cs`](https://github.com/androidseb25/iGotify-Notification-Assistent/blob/main/Program.cs)). There is no useful page at the root URL.

- **API docs (Scalar):** `http://<host>:8681/api/scalar/v1` (adjust host port if you changed `IGOTIFY_HTTP_PORT`).
- **Version JSON:** `http://<host>:8681/api/Version`

The log line `Failed to determine the https port for redirect` is a common ASP.NET warning when only HTTP is used; it does not mean the service is down.

**Local network:** use the Docker host’s LAN IP (not only `127.0.0.1`) when opening from another machine. Ensure the host firewall allows the chosen port.

**Networking:** Docker bridge **`notificationsnetwork`** (same pattern as `homepagenetwork` / `terminalnetwork` in this repo). Services reach each other at **`http://gotify:80`** for `GOTIFY_URLS`.

**Compose layout** follows the [upstream `docker-compose.yaml`](https://github.com/androidseb25/iGotify-Notification-Assistent/blob/main/docker-compose.yaml) (healthchecks, images, `security_opt`). This repo uses **bind mounts** and **ports** `8688` / `8681` by default instead of named volumes / `8680`. The healthcheck targets **`/api/Version`** to match the assistant’s `UsePathBase("/api")`; older upstream examples used `/Version` only.

### iGotify environment variables

| Variable               | Purpose                                                                                                                                            |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GOTIFY_URLS`          | Comma-separated Gotify server URL(s) the assistant listens on. For local use set to `http://gotify:80` (Docker service name); leave empty to disable. |
| `GOTIFY_CLIENT_TOKENS` | Comma-separated Gotify **client** tokens (created in Gotify UI → **Clients**). One token per URL if multiple servers.                              |
| `SECNTFY_TOKENS`       | Comma-separated SecNtfy device tokens (from the iGotify iOS app). Bridges Gotify messages → APNs for iOS lock-screen push.                        |
| `ENABLE_CONSOLE_LOG`   | Log messages to stdout (`true` / `false`, default `true`).                                                                                         |
| `ENABLE_SCALAR_UI`     | Serve the Scalar API explorer at `/api/scalar/v1` (`true` / `false`, default `true`).                                                              |

## changedetection.io

[**changedetection.io**](https://github.com/dgtlmoon/changedetection.io) monitors web pages for content changes and sends alerts (including via Gotify). Open `http://<host-lan-ip>:5001` after starting the stack. State (watch list, history, screenshots) is stored in `./data/changedetection/`. The host port is hardcoded to `5001` — there is no env var to override it; edit `compose.yml` if you need a different port.

**No authentication is enabled by default.** If the service is reachable beyond your LAN, enable the built-in password under **Settings → Access & API**.

## Homepage

The [Homepage](../homepage/) stack includes a **Gotify** card in `data/homepage/config/services.yaml` (Notifications group). Set `HOMEPAGE_VAR_GOTIFY_URL` and `HOMEPAGE_VAR_GOTIFY_KEY` in [`homepage/.env`](../homepage/.env.example) — the widget needs a [**client** token](https://gethomepage.dev/widgets/services/gotify/) from **Clients** in the Gotify admin UI (not the same as an *Application* token used for Sonarr).
