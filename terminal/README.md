# Atuin (self-hosted sync server)

Docker Compose stack for [Atuin](https://atuin.sh/): a sync server for encrypted shell history. The server listens on **port 8888**; Postgres **18** stores metadata under `./data/database`, and Atuin server config under `./data/config`. A sidecar runs [postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local) on **`@daily`** and writes compressed dumps to **`./data/db_dumps`**.

Atuin and the backup sidecar wait for PostgreSQL's native readiness check
before starting. The backup sidecar also restarts unless explicitly stopped,
so a transient startup failure does not disable later scheduled backups. A
healthy database status confirms that PostgreSQL accepts connections; it does
not verify data integrity or that a backup can be restored.

## Prerequisites

- Docker and Docker Compose v2

## Quick setup

1. **Environment**

   ```bash
   cp .env.example .env
   ```

   Set `ATUIN_DB_NAME`, `ATUIN_DB_USERNAME`, and a strong `ATUIN_DB_PASSWORD` in `.env`.

2. **Create the folder structure**

   If you're using bind mounts (like this stack does), create the directories up front so Docker doesn't create them as root.

   ```bash
   mkdir -p \
     data/config \
     data/database \
     data/db_dumps
   ```

3. **Start**

   From this directory:

   ```bash
   docker compose up -d
   ```

4. **Point your shell client at this server**

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

| Path              | Purpose                                                     |
| ----------------- | ----------------------------------------------------------- |
| `./data/config`   | Atuin server configuration                                  |
| `./data/database` | Postgres data directory (do not delete)                     |
| `./data/db_dumps` | Scheduled SQL backups (daily; retention per image defaults) |

### Postgres major upgrades

If `./data/database` was created with an **older** Postgres major version (for example 14), you cannot point Postgres 18 at that directory without a [dump/restore or upgrade path](https://www.postgresql.org/docs/current/upgrading.html). For a clean start, stop the stack, move `./data/database` aside, and start again (you lose DB history unless you restore from a dump).

### DB password and `ATUIN_DB_URI`

Use a strong password in `.env`. Avoid characters that are special in URLs (`@`, `:`, `/`, `%`, etc.) or the `ATUIN_DB_URI` passed into the Atuin container may fail to parse; if you need those characters, URL-encode them in the URI or adjust how the URI is built.

## Security note

`ATUIN_OPEN_REGISTRATION` controls account creation, and it is **closed by default**
(`compose.yml` renders `${ATUIN_OPEN_REGISTRATION:-false}`).

This stack's hostname is publicly routed through the Cloudflare Tunnel
(`atuin.lexcode.dev` → `http://<host>:8888`), so open registration would let any internet client
create accounts on the shell-history store. The intended flow is:

1. Set `ATUIN_OPEN_REGISTRATION=true` in `.env`.
2. `docker compose up -d` (the container must be **recreated** — editing `.env` alone changes nothing,
   because Compose only interpolates variables that `compose.yml` references).
3. Create your account.
4. Set it back to `false` and recreate again.

Setting the variable only in `.env` is not enough: `compose.yml` must read it, which is why the
default lives in the interpolation rather than as a literal `"true"`. Do not expose this service
without either closed registration or an authenticating proxy in front of it.

## Image pin

The Atuin image is pinned to a specific digest tag (`ghcr.io/atuinsh/atuin:c28ac1b`) for reproducibility. Bump it deliberately when you want to upgrade.
