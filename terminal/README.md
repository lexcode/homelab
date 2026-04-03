# Atuin (self-hosted sync server)

Docker Compose stack for [Atuin](https://atuin.sh/): a sync server for encrypted shell history. The server listens on **port 8888**; Postgres stores metadata under `./database`, and Atuin server config under `./config`.

## Prerequisites

- Docker and Docker Compose v2

## Quick setup

1. **Environment**

   ```bash
   cp .env.example .env
   ```

   Set `ATUIN_DB_NAME`, `ATUIN_DB_USERNAME`, and a strong `ATUIN_DB_PASSWORD` in `.env`.

2. **Start**

   From this directory:

   ```bash
   docker compose up -d
   ```

3. **Point your shell client at this server**

   On each machine with the [Atuin CLI](https://docs.atuin.sh/), set the sync URL **before** registering or logging in. Either add to `~/.config/atuin/config.toml`:

   ```toml
   sync_address = "http://your-host:8888"
   ```

   …or export `ATUIN_SYNC_ADDRESS` for that shell session. Use `https://…` if you terminate TLS in front of the container.

   Then create an account or sign in (see [Setting up sync](https://docs.atuin.sh/guide/sync)):

   ```bash
   atuin register -u <username> -e <email>
   ```

   Or, if the user already exists on this server:

   ```bash
   atuin login -u <username>
   ```

## Data layout

| Path            | Purpose                          |
| --------------- | -------------------------------- |
| `./config`      | Atuin server configuration       |
| `./database`    | Postgres data (do not delete)   |

## Security note

`compose.yml` sets `ATUIN_OPEN_REGISTRATION=true`, which allows anyone who can reach the service to create accounts. For a homelab behind your LAN or a reverse proxy with auth, that may be fine. For anything internet-exposed, turn registration off after creating your user (set `ATUIN_OPEN_REGISTRATION=false` and restart) and rely on your existing accounts.

## Image pin

The Atuin image is pinned to a specific digest tag (`ghcr.io/atuinsh/atuin:c28ac1b`) for reproducibility. Bump it deliberately when you want to upgrade.
