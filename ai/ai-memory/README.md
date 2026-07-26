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

3. Generate a bearer token:

   ```bash
   openssl rand -hex 32
   ```

   In `.env`, replace `AI_MEMORY_AUTH_TOKEN` with that token and replace
   `YOUR_PI_IP` in `AI_MEMORY_ALLOWED_HOSTS` with the Pi address clients will
   use. For example:

   ```dotenv
   AI_MEMORY_AUTH_TOKEN=YOUR_GENERATED_TOKEN
   AI_MEMORY_ALLOWED_HOSTS=192.168.1.50,raspberrypi.local,localhost,127.0.0.1
   ```

   Keep the token out of Git. Clients need the same value.

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
| `AI_MEMORY_ALLOWED_HOSTS`      | —         | Comma-separated Pi addresses/names accepted by the server. |
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

## Set up an external PC or laptop

These steps configure a supported agent running on another machine to use the
Pi as its only ai-memory server.

### 1. Confirm the server address

Use the Pi's stable LAN IP, LAN DNS name, or Tailscale address. The same value
must be present in `AI_MEMORY_ALLOWED_HOSTS` on the Pi. After changing the Pi's
`.env`, apply it with:

```bash
cd ~/code/homelab/ai/ai-memory
docker compose up -d
```

From the client machine, an unauthenticated request should reach the server and
return `401 Unauthorized`:

```bash
curl -sI http://YOUR_PI_IP:49374/handoff
```

`Connection refused` or a timeout means the address, firewall, port mapping, or
network route must be fixed before configuring an agent.

### 2. Install or keep the ai-memory CLI

If `ai-memory --version` already works, keep that installation. On Arch Linux,
install the native client with:

```bash
yay -S ai-memory-bin
```

On Linux, macOS, or WSL2 with Docker available, install the upstream wrapper:

```bash
mkdir -p ~/.local/bin
curl -fsSL \
  https://raw.githubusercontent.com/akitaonrails/ai-memory/main/bin/ai-memory \
  -o ~/.local/bin/ai-memory
chmod +x ~/.local/bin/ai-memory
```

Ensure `~/.local/bin` is on `PATH`. Native Windows users should follow the
[upstream Windows guide](https://github.com/akitaonrails/ai-memory/blob/main/docs/windows.md);
WSL2 users should perform all setup inside the same WSL distribution as the
agent CLI.

### 3. Configure the remote endpoint and token

Add both variables to the client's shell configuration (`~/.bashrc`,
`~/.zshrc`, or equivalent):

```bash
export AI_MEMORY_SERVER_URL="http://YOUR_PI_IP:49374"
export AI_MEMORY_AUTH_TOKEN="YOUR_GENERATED_TOKEN"
```

Start a new shell, or reload the file you edited. Do not use `0.0.0.0` in the
client URL; it is only the server's listen address.

Verify authenticated access:

```bash
curl -sI \
  -H "Authorization: Bearer $AI_MEMORY_AUTH_TOKEN" \
  "$AI_MEMORY_SERVER_URL/handoff"

ai-memory status
```

The authenticated request should return `200 OK`, and `ai-memory status` should
report the Pi server rather than `127.0.0.1`.

### 4. Configure each coding agent

Run the matching pair on the client for every agent you use:

```bash
# Claude Code
ai-memory install-mcp --client claude-code --apply
ai-memory install-hooks --agent claude-code --apply

# Codex
ai-memory install-mcp --client codex --apply
ai-memory install-hooks --agent codex --apply
```

The installers inherit `AI_MEMORY_SERVER_URL` and `AI_MEMORY_AUTH_TOKEN`.
Re-run them after upgrading ai-memory so generated integrations stay current.
Run `ai-memory install-instructions` from an existing project when you also
want its managed routing guidance added or refreshed.

### 5. Verify from the client

Open a new agent session in a project, then inspect the Pi-hosted web UI:

```text
http://YOUR_PI_IP:49374/web
```

When the browser shows an HTTP Basic prompt, use the ai-memory token as the
password. Confirm that the expected project and new observations appear.

If this client previously ran a native ai-memory server, disable it only after
the remote setup works:

```bash
systemctl --user disable --now ai-memory.service
```

Keep any original desktop data as a rollback copy until migration is verified.
Do not run the desktop and Pi servers independently after migration; they are
separate sources of truth and do not synchronize automatically.

### Access from outside the home LAN

Do not forward port `49374` directly from the router. Plain HTTP exposes the
bearer token in transit. Prefer Tailscale/WireGuard, or put ai-memory behind a
TLS-terminating authenticated reverse proxy. Use that VPN or HTTPS address in
`AI_MEMORY_SERVER_URL` and include its hostname or IP in
`AI_MEMORY_ALLOWED_HOSTS`.

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
