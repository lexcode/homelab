# ai-memory

Self-hosted [ai-memory](https://github.com/akitaonrails/ai-memory) server for sharing persistent coding-agent context between machines and supported clients. The stack runs in zero-LLM mode by default, stores all state under `./data/`, and exposes the server to the LAN with bearer-token authentication.

The published Docker image supports `linux/arm64`, including a 64-bit Raspberry Pi 5.

## Quick start

1. Confirm the Pi is running a 64-bit OS:

   ```bash
   uname -m
   ```

   The result should be `aarch64`.

2. Create the environment file and persistent-data directory:

   ```bash
   cd ~/code/homelab/ai/ai-memory
   cp .env.example .env
   mkdir -p data
   ```

3. Generate a bearer token and replace the placeholder in `.env`:

   ```bash
   openssl rand -hex 32
   ```

   Keep the token out of Git. Clients need the same value in `AI_MEMORY_AUTH_TOKEN`.

4. Start the stack:

   ```bash
   docker compose up -d
   docker compose logs -f --tail=100
   ```

The server listens at `http://<pi-lan-ip>:49374` by default. Do not expose port `49374` directly to the public internet; use the LAN, Tailscale, WireGuard, or an authenticated reverse proxy.

## Configuration

| Variable                       | Default   | Purpose                                                   |
| ------------------------------ | --------- | --------------------------------------------------------- |
| `AI_MEMORY_BIND_ADDRESS`       | `0.0.0.0` | Host interface on which Docker publishes the server port. |
| `AI_MEMORY_PORT`               | `49374`   | Published host port.                                      |
| `AI_MEMORY_AUTH_TOKEN`         | —         | Shared bearer token for remote clients.                   |
| `AI_MEMORY_LLM_PROVIDER`       | `none`    | Optional LLM provider; `none` avoids provider calls.      |
| `AI_MEMORY_EMBEDDING_PROVIDER` | `none`    | Optional embedding provider.                              |
| `AI_MEMORY_LOG_LEVEL`          | `info`    | Rust log filter passed to the container as `RUST_LOG`.    |

Persistent state is bind-mounted from `./data/` to `/data` in the container. Include the complete directory in backups; it can contain the Markdown wiki, SQLite data, observations, handoffs, audit data, and indexes.

The service intentionally has no container healthcheck because the published image is not guaranteed to contain an HTTP probe utility. Repository status reports it as `no-healthcheck`.

## Migrate an existing native installation

First identify the native data directory:

```bash
systemctl --user cat ai-memory
```

For a standard AUR user installation it is normally `~/.local/share/ai-memory`.

Stop the native server before copying so its SQLite data is consistent:

```bash
systemctl --user stop ai-memory
```

If this Docker stack has already been used, stop it and preserve its current data:

```bash
cd ~/code/homelab/ai/ai-memory
docker compose down
mv data "data.before-migration-$(date +%Y%m%d-%H%M%S)"
mkdir -p data
```

From the desktop, transfer the complete native data directory:

```bash
rsync -aHAX --info=progress2 \
  ~/.local/share/ai-memory/ \
  lexcode@YOUR_PI_IP:~/code/homelab/ai/ai-memory/data/
```

Then start the server on the Pi:

```bash
cd ~/code/homelab/ai/ai-memory
sudo chown -R "$(id -u):$(id -g)" data
docker compose up -d
docker compose logs -f --tail=100
```

Do not copy only the Markdown wiki. The application database also stores context needed for a complete migration.

## Point desktop clients at the Pi

Keep the native package installed for its CLI and integration installers, but disable its local server after confirming the Pi copy works:

```bash
export AI_MEMORY_SERVER_URL="http://YOUR_PI_IP:49374"
export AI_MEMORY_AUTH_TOKEN="YOUR_GENERATED_TOKEN"

ai-memory status
```

Regenerate each integration so it uses that endpoint and token:

```bash
ai-memory install-mcp --client claude-code --apply
ai-memory install-hooks --agent claude-code --apply

ai-memory install-mcp --client codex --apply
ai-memory install-hooks --agent codex --apply
```

After verifying existing projects in `/web`, disable the native desktop server:

```bash
systemctl --user disable --now ai-memory.service
```

Keep the original desktop data as a rollback copy until the migration is verified. Do not run the desktop and Pi servers independently after migration; they are separate sources of truth and do not synchronize automatically.

## Validate and inspect

From this stack directory:

```bash
docker compose --env-file .env.example config --quiet
```

From the repository root:

```bash
bash scripts/validate.sh
bash scripts/status.sh ai/ai-memory
```

To confirm LAN reachability:

```bash
curl -i http://YOUR_PI_IP:49374/web
```

The web page may request authentication or return an unauthorized response without the token; either response confirms that the service is reachable.
