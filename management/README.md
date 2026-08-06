# Management (Dockge)

Docker Compose stack for [Dockge](https://github.com/louislam/dockge), a web interface for managing Compose stacks. Dockge reads the existing stack directories in this repository, so Compose files remain the source of truth on disk and can still be managed with the Docker CLI or Git.

## Prerequisites

- Docker and Docker Compose v2
- This repository cloned at a stable absolute path

## Quick start

1. Copy and edit the environment file:

   ```bash
   cd management
   cp .env.example .env
   ```

   Set `HOMELAB_ROOT` to the absolute path of this repository on the Docker host. The same path is mounted inside Dockge because its interactive Compose console requires host and container paths to match.

2. Create the persistent data directory before starting the container:

   ```bash
   mkdir -p data/dockge
   ```

3. Validate and start the stack:

   ```bash
   docker compose config --quiet
   docker compose up -d
   ```

4. Open `http://<host-lan-ip>:5002` and create the initial administrator account.

Dockge automatically discovers directories beneath `HOMELAB_ROOT` that contain a supported Compose file. Use a stack's **Update** action to pull its configured images and recreate changed containers.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOMELAB_ROOT` | `/home/lexcode/git/homelab` | Absolute host path to this repository and Dockge's stacks directory. |
| `DOCKGE_PORT` | `5002` | Host port for the Dockge UI; container port `5001` is fixed. |
| `MANAGEMENT_SUBNET` | `172.39.8.0/24` | CIDR for `managementnetwork`. |

Persistent Dockge settings live in `./data/dockge/` and should be included in backups. Compose files and per-stack `.env` files remain in their existing repository directories.

## Updating containers safely

Before updating a stateful stack, review its upstream release notes and confirm that its data is backed up. This is especially important for PostgreSQL, MongoDB, Paperless-ngx, and networking services. An image tagged `latest` can include breaking changes; the Dockge update button does not provide an automatic rollback.

To update Dockge itself, run from this directory:

```bash
docker compose pull
docker compose up -d
```

## Reverse proxy

The proxy stack joins `managementnetwork`, and Dockge carries `traefik.*` labels routing `dockge.lexcode.dev` to `http://dockge:5001` (see [Docker-routed backends](../proxy/README.md#routing-model)). Do not expose Dockge publicly without strong authentication and an additional access-control layer such as Cloudflare Access or a VPN.

## Security

Dockge mounts `/var/run/docker.sock` with write access. This is required to create and update containers, but it effectively grants Dockge administrative control of the Docker host. Keep Dockge on a trusted LAN or behind authenticated private access, use a strong administrator password, and do not expose port `5002` directly to the internet.
