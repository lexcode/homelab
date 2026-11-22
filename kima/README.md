# Kima

[Kima](https://github.com/Chevron7Locked/kima-hub) is a self-hosted music
server in a single all-in-one container: web app, API, Postgres, Redis, and
the two audio analyzers (tempo/key/energy and the CLAP sound-vector "vibe"
model). It streams your library, serves podcasts and audiobooks, and matches
songs by how they sound and feel.

**This stack runs on the Unraid host, not on this repository's Docker host.**
The compose file here is the copy-paste configuration for Unraid's Docker
Compose support; nothing here is deployed to the main host except the reverse
proxy route (below). From this repository's point of view Kima is an
*external-routed backend* (see [GLOSSARY.md](../GLOSSARY.md)): no Docker
Compose stack runs on the main host, so the ingress stack routes to it with a
static entry in `proxy/config/traefik/dynamic/external.yml` instead of
container labels.

## Files

- `compose.yml` — the all-in-one `chevron7locked/kima` image, based on the
  upstream `docker-compose.prod.yml`. Defaults point at the Unraid paths from
  the deployment request (`/mnt/user/Media/Music`, `/mnt/user/appdata/kima`),
  so it runs without an `.env`.
- `.env.example` — optional overrides (image tag, paths, port, time zone,
  HTTPS cookie flag, Lidarr callback, memory guardrails).

## First deployment (on Unraid)

1. Create the compose folder and, under it, `compose.yml` (and `.env` if you
   want the overrides):

   ```bash
   mkdir -p /mnt/user/appdata/kima-compose
   # put compose.yml (and .env) in that folder
   ```

2. Start it. Either paste `compose.yml` into Unraid's *Docker → Compose* UI or:

   ```bash
   cd /mnt/user/appdata/kima-compose
   docker compose up -d
   ```

   On first start the image initializes its own Postgres cluster and Redis
   data under `/data` and generates a session secret and encryption key under
   `/data/secrets`. No post-creation steps needed — the container's startup
   script creates and chowns `/data/postgres` and `/data/redis` itself.

   Note: upstream's `vm.overcommit_memory=1` sysctl is deliberately not
   included — Docker on Unraid rejects it as not namespaced. Redis logs a
   harmless overcommit warning instead.

3. Open `https://music.lexcode.dev` (or `http://<unraid-ip>:3030` on the LAN)
   and create the first account — it becomes the administrator. Point the
   library at `/music`, which is the `Media/Music` share.

Configuration beyond that happens in the web app's Settings (server address,
library path, sources, artwork keys, GPU switches, worker counts); only the
address, secrets and callbacks that must be known before the app starts are
environment variables. See the upstream
[configuration docs](https://github.com/Chevron7Locked/kima-hub/blob/main/docs/configuration.md).

## Data on Unraid

- `/mnt/user/Media/Music` → mounted at `/music` — the library (read by Kima;
  Lidarr writes into it if you connect it).
- `/mnt/user/appdata/kima` → mounted at `/data` — Postgres data, Redis data,
  cover/transcode caches, and `/data/secrets` (the generated session secret
  and encryption key). **Back this folder up.** Without `/data/secrets`
  the stored credentials (Lidarr, Soulseek, fanart keys) cannot be decrypted,
  and without the database you lose users, playlists and play history.

The container runs its internal services under their own users (postgres,
redis) and chowns the bind-mounted `/data/*` folders on start, so OS-level
permissions under appdata are managed by the container itself.

## Routing (`https://music.lexcode.dev`)

The route is a static entry in the ingress stack, added in this PR:

- `proxy/config/traefik/dynamic/external.yml` — a `kima` router on the
  `websecure` entrypoint with the shared `*.lexcode.dev` wildcard certificate
  (DNS-01), pointing at `http://192.168.0.149:3030` (the Unraid host, where
  the published `KIMA_PORT` listens). This serves LAN traffic and any
  hostname the Cloudflare Tunnel forwards.

For **public** reachability, add `music.lexcode.dev` as a public hostname in
the Cloudflare Tunnel dashboard. Because Kima lives on Unraid, the origin can
be the Unraid host directly (`http://192.168.0.149:3030`) — the same model as
the other Unraid-hosted backends in `external.yml` — or Traefik's
Docker-private Cloudflare entrypoint (`http://traefik:8081`) if you prefer to
keep every hostname traversing Traefik; see the [public
hostnames](../proxy/README.md#public-hostnames) section for the routing
model. `SECURE_COOKIES` is already defaulted to true in this stack's compose
file so the session cookie stays HTTPS-only.

The main host reaches Kima over the LAN; nothing else in this repository
needs a change for routing.

## NVIDIA GPU (Quadro P620)

GPU use needs both halves in place:

1. Unraid's NVIDIA Driver plugin installed (host `nvidia-smi` lists the card);
   `compose.yml` ships with the passthrough **enabled**: the `gpus:`/`devices:`
   block plus the same `NVIDIA_VISIBLE_DEVICES` / `NVIDIA_DRIVER_CAPABILITIES`
   env vars an Unraid GPU template uses (the Jellyfin container on this host
   is configured the same way). It is the plugin that registers the `nvidia`
   runtime Docker needs — without it the container refuses to start. To run
   CPU-only, comment out the `gpus:` and `devices:` lines. Once started, the
   container should see the card (`docker exec kima nvidia-smi`). If an older
   plugin build rejects the `gpus: all` line itself, remove only that line —
   the device nodes plus env vars alone hand the card over, exactly as
   Jellyfin does.
2. In **Settings → Library → Performance**, turn on the two NVIDIA switches
   ("vibe embeddings" and "audio analysis"); they show on Linux x86-64 only.

GPU use is **off in the app until you flip those switches** — the passthrough
alone changes nothing. The first switch you turn on downloads the ~2 GB ONNX
GPU runtime into
`/data` (about 3.4 GB on disk). Everything also works without the card — the
analyzers fall back to the CPU. Details: upstream
[gpu.md](https://github.com/Chevron7Locked/kima-hub/blob/main/docs/gpu.md).

## Performance on this host

The Unraid box is a 2-core Celeron G1610T. The all-in-one image runs two
audio-analysis workers by default (about 1-1.5 GB each, up to 2-3 GB at
peak) plus the CLAP vibe analyzer. Recommended:

- Lower the worker counts in **Settings → Library → Performance** if the box
  is starved, and lower `KIMA_MEM_LIMIT`/`KIMA_MEMSWAP_LIMIT` in `.env` to
  match the installed RAM.
- If the vibe features aren't worth the CPU, set `DISABLE_CLAP=1` in `.env` —
  the health check then stops expecting the vibe analyzer.
- The first library sweep (identification, artist metadata, audio analysis,
  sound vectors, moods, similarity) is slow on two cores; it runs in the
  background. The GPU switches offload the two ONNX models when enabled.

## Updating

Pin a `KIMA_VERSION` (release tags are like `v1.13.0`) for reproducible
upgrades, or keep `latest` (the pre-release channel never moves it). Update
with `docker compose pull && docker compose up -d`.

Migrations run on container start and **do not roll back**: copy `/data`
(`/mnt/user/appdata/kima`) before a major update if you might want to go
back. Some major versions re-run part of the enrichment in the background
after the upgrade — music, playlists, plays and likes survive.

## Lidarr integration

Kima can download through Lidarr and it needs to call back into Kima — the
address *Lidarr* resolves, not Kima. The repo's media stack runs Lidarr on a
different host, so set `KIMA_CALLBACK_URL` to an address that host can reach
(the default `http://192.168.0.149:3030` works), then configure the
connection and profiles in **Settings → Sources → Lidarr**. See upstream
[integrations.md](https://github.com/Chevron7Locked/kima-hub/blob/main/docs/integrations.md).
