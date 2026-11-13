# n8n-sandbox

Isolated code-execution sandbox for **n8n Assistant** in the [`n8n/`](../n8n/README.md) stack. n8n Assistant runs AI-generated code; this stack is the environment that code runs in.

This is **not** a second n8n instance. It contains no editor and no database — those stay in `n8n/`, which owns `n8n-sandbox-network` and reaches `sandbox-api` by service name.

Upstream reference: [Set up n8n Assistant](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-n8n-assistant/#setup-2-self-host-the-sandbox-manually-advanced) → "Setup 2: Self-host the sandbox manually". The Compose services are adapted from n8n's canonical [`get-n8n-compose.yml`](https://github.com/n8n-io/n8n/blob/master/docker/get-n8n-compose.yml).

## Services

| Service | Role |
| --- | --- |
| `sandbox-certs` | One-shot job. Generates the mutual-TLS material the API and runner use, then exits. |
| `sandbox-api` | Control plane. n8n talks to it over plain HTTP on `n8n-sandbox-network`; the mTLS hop is between this container and the runner. |
| `sandbox-runner-1` | **Privileged** Docker-in-Docker worker that creates and runs the actual sandboxes. |
| `searxng` | Optional web-search backend for n8n Assistant (JSON API enabled by `searxng-settings.yml`). |

Deliberately omitted from the upstream file: the `runners` service (external Code-node task runner — not needed by n8n Assistant) and `n8n` itself.

## Prerequisites

- Docker and Docker Compose v2, 64-bit ARM or x86-64 host. All four images publish `linux/arm64`, verified for `N8N_SANDBOX_VERSION=1.15.0`.
- The [`n8n/`](../n8n/README.md) stack.
- **Memory headroom of roughly 1–1.5 GB on top of the existing n8n footprint.** Upstream asks for 4 GB and 2 vCPUs for the whole bundled stack; this trimmed version is lighter but still the heaviest thing in this repo. On the Pi 5 the containers are capped (`SANDBOX_API_MEM_LIMIT`, `SANDBOX_RUNNER_MEM_LIMIT`, `SEARXNG_MEM_LIMIT`) so a runaway sandbox cannot OOM-kill production.

## First deployment

1. Create the private environment file. Do not commit it:

   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

   Generate each secret with `openssl rand -hex 32`.

2. Set `N8N_SANDBOX_SERVICE_API_KEY` in **`n8n/.env`** to a value from **`SANDBOX_API_KEYS`** in this stack's `.env`. They must match byte for byte — that is how n8n authenticates to the sandbox. Then set `N8N_INSTANCE_AI_SANDBOX_ENABLED=true` there.

3. Validate and start. Start order matters: **`n8n/` owns `n8n-sandbox-network`** (so it stays startable on its own), and this stack joins it as `external: true`. Bring n8n up first so the network exists.

   ```bash
   cd ../n8n && docker compose up -d && cd ../n8n-sandbox
   docker compose --env-file .env.example config --quiet
   docker compose up -d
   ```

   `sandbox-certs` must exit 0 before `sandbox-api` starts; `sandbox-runner-1` waits for the API to be healthy.

4. Verify:

   ```bash
   docker compose ps                        # sandbox-api should reach "healthy"
   docker compose logs sandbox-api | grep -i runner   # runner registered itself
   docker compose exec sandbox-api wget -qO- http://localhost:8080/healthz
   ```

   Expected: `{"status":"ok"}`

5. Restart n8n so it picks up the sandbox settings, then add a model key and confirm n8n Assistant responds:

   ```bash
   cd ../n8n && docker compose up -d
   ```

## Troubleshooting

**`network n8n-sandbox-network declared as external, but could not be found`** — `n8n/` has not been started yet. Run `docker compose up -d` in `n8n/` first.

**`sandbox-api` never becomes healthy** — check `docker compose logs sandbox-certs` first. If certificate generation failed, `sandbox-api` cannot start. Delete `data/tls`, then `docker compose up -d` again to regenerate.

**`failed to load api config: SANDBOX_API_RUNNER_REGISTRATION_TOKEN must be set`** — the API and runner read **different variable names** for the same two shared secrets, and the upstream `.env` template only documents the runner-side pair. Both must be present in `.env`:

```
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=…   # read by sandbox-api
SANDBOX_RUNNER_REGISTRATION_TOKEN=…       # read by sandbox-runner-1   (same value)
SANDBOX_API_RUNNER_API_KEY=…              # read by sandbox-api
SANDBOX_RUNNER_API_KEYS=…                 # read by sandbox-runner-1   (same value)
```

**n8n logs `Sandbox: enabled=false provider=n8n-sandbox (DB override; env was enabled=true)`** — n8n stores the sandbox toggle in its own database, under the `settings` key `instanceAi.settings`, and a stored value **overrides** `N8N_INSTANCE_AI_SANDBOX_ENABLED`. Fix it in n8n at **Settings → Agents → Shared sandbox** (supported path), or update that JSON row with n8n stopped:

```json
{"sandboxEnabled": true, "n8nSandboxServiceUrl": "http://sandbox-api:8080"}
```

Either way a restart is needed, and `N8N_SANDBOX_SERVICE_API_KEY` still supplies the API key from the environment. The log line `Sandbox: enabled=true provider=n8n-sandbox` is the confirmation.

**n8n Assistant runs but code execution fails** — the runner is memory-capped (`SANDBOX_RUNNER_MEM_LIMIT`, default `1536m`). Check `docker compose logs sandbox-runner-1` for inner-Docker or pull failures, and confirm the sandbox image pulled successfully inside the runner: `docker compose exec sandbox-runner-1 docker images`.

**Web search returns 403** — newer SearXNG images enable a bot limiter that can reject JSON API clients. If that happens, add a `server:` section with `limiter: false` to `searxng-settings.yml` and recreate the container, or switch to Brave Search via `INSTANCE_AI_BRAVE_SEARCH_API_KEY`.

## URLs

Both endpoints are normal `websecure` Traefik routers with the `letsencrypt` certificate resolver, discovered from `traefik.*` labels. Both are one-label subdomains covered by the existing `*.lexcode.dev` DNS-01 wildcard, so no extra DNS record or certificate is needed.

| URL | Service | Auth | Purpose |
| --- | --- | --- | --- |
| **`https://n8n-searxng.lexcode.dev`** | `searxng:8080` | none | Search UI, and the JSON search API (`?format=json`) n8n Assistant uses for web search |
| **`https://n8n-sandbox-api.lexcode.dev`** | `sandbox-api:8080` | `X-Api-Key` header | Probe/test the sandbox control plane from a LAN machine |

`sandbox-runner-1` deliberately has **no hostname and no Traefik labels**: it is a privileged Docker-in-Docker worker, and upstream's compose file says *"Never publish 8080/9090 to the host on an internet-facing server."*

There is no `n8n-sandbox.lexcode.dev`; the two names above replace it.

### What n8n itself uses

n8n does **not** use the API hostname. `N8N_SANDBOX_SERVICE_URL` stays `http://sandbox-api:8080`, resolved over `n8n-sandbox-network`, so the Assistant keeps working even if Traefik is down or its certificate breaks. The hostname exists for humans and scripts only. Do not "tidy" the internal URL into the public one.

### Querying the API from the LAN

The control plane authenticates with an **`X-Api-Key`** header. `Authorization: Bearer` does **not** work (401), and the API root `/` is always 401 even with a valid key, so neither is a useful health check. Real routes include `/healthz`, `/sandboxes`, and `/admin/tenants`.

```bash
KEY=$(grep '^N8N_SANDBOX_SERVICE_API_KEY=' ../n8n/.env | cut -d= -f2)

curl https://n8n-sandbox-api.lexcode.dev/healthz                              # open -> {"status":"ok"}
curl -H "X-Api-Key: $KEY" https://n8n-sandbox-api.lexcode.dev/sandboxes       # 200 -> [] when idle
curl https://n8n-sandbox-api.lexcode.dev/sandboxes                            # 401 without the key
```

Because this endpoint fronts a **code-execution** control plane, treat `SANDBOX_API_KEYS` / `N8N_SANDBOX_SERVICE_API_KEY` as high-value secrets. To rotate: change both values in `n8n-sandbox/.env` and `n8n/.env` to the same new key, then recreate `sandbox-api` and `n8n`.

### Exposure

LAN-only: like `n8n.lexcode.dev`, neither hostname has a Traefik `cloudflare` entrypoint router. Do not add either one in Cloudflare Zero Trust → Tunnels → Public Hostnames.

Traefik needs to join this stack's network to route these, so the [`proxy/`](../proxy/README.md) stack lists `n8n-sandbox-network` as `external: true`.

## Memory and storage notes

`sandbox-runner-1` keeps its **inner** Docker daemon in `./data/runner-docker`, so the ~1 GB sandbox image is pulled once rather than on every recreate. That directory grows with use; reclaim it with:

```bash
docker compose down
sudo rm -rf data/runner-docker
docker compose up -d
```

The next sandbox run re-pulls the image. To pre-pull it (recommended after a version bump, so the first AI code execution is not a multi-minute wait):

```bash
# the runner pulls this into its *inner* Docker daemon
cd n8n-sandbox
sudo rm -rf data/runner-docker && docker compose up -d
# or, against a running runner (needs sudo: data/runner-docker is root-owned)
docker exec n8n-sandbox-runner-1 docker pull \
  ghcr.io/n8n-io/n8n-sandbox-service-sandbox:$(grep ^N8N_SANDBOX_VERSION .env | cut -d= -f2)
```

## Security notes

- `sandbox-runner-1` is `privileged: true` **by design** — Docker-in-Docker is what isolates AI-generated code. Do not "fix" this with `cap_drop`/`no-new-privileges`, and do not add a `cloudflare` Traefik router or publish its ports.
- Neither `sandbox-api` nor `sandbox-runner-1` publishes host ports. n8n reaches the API by service name only.
- Only `n8n-sandbox-network` carries this traffic. It is a dedicated `/24` (`N8N_SANDBOX_SUBNET`, default `172.39.9.0/24`) unshared with any other stack.
- TLS certificates are issued for the names `sandbox-api` and `sandbox-runner-1`. Renaming those services invalidates them: delete `data/tls` and re-run `sandbox-certs`.

## Operations

```bash
# Read-only container health/status from the repository root
bash scripts/status.sh n8n-sandbox

# Follow logs
docker compose logs -f sandbox-api sandbox-runner-1

# Update images deliberately (keep N8N_SANDBOX_VERSION pinned in .env)
docker compose pull
docker compose up -d
```

Upgrading: the API, runner, and sandbox images ship as one release and are only supported together. Bump `N8N_SANDBOX_VERSION` in one step and recreate the whole stack.

## Boot with systemd (optional)

```bash
sudo cp ../systemd/n8n-sandbox.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable n8n-sandbox.service
```

Keep `n8n-sandbox.service` ordered **after** `n8n.service` — this stack joins n8n's network as external, so n8n must create it first.

## Layout

- `compose.yml` — sandbox-certs, sandbox-api, sandbox-runner-1, and SearXNG
- `.env.example` — sandbox version, shared secrets, subnets, memory ceilings
- `searxng-settings.yml` — enables SearXNG's JSON API
- `data/tls/` — generated mTLS material (not committed)
- `data/runner-docker/` — inner Docker daemon storage for the runner (not committed)
