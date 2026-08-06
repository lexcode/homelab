# Replace Nginx Proxy Manager with Traefik as the ingress stack's reverse proxy

Nginx Proxy Manager (NPM) is being retired in favor of Traefik, replacing the `nginx-proxy-manager` service in-place inside the `proxy/` (ingress) stack, alongside `cloudflared` and `tailscale-funnel`. Docker-routed backends get their routes via labels on the container itself (Traefik's Docker provider, per-stack, decentralized); external-routed backends (a handful of non-Docker LAN devices — NAS, router, an Unraid box) get a small supplementary file-provider config in the ingress stack. This was chosen over a single centralized routing file because it keeps each stack self-describing, matching this repo's existing one-stack-per-directory convention, at the cost of routing config being spread across every stack instead of one admin UI.

## Considered Options

- **Centralized file-provider config for everything** (closer to NPM's single admin UI) — rejected: means editing one shared file whenever any stack's routing changes, working against the existing per-directory stack convention.
- **DNS-01 ACME challenge** (via Cloudflare API token) — rejected in favor of HTTP-01, matching NPM's current behavior with no new secret to provision. Revisit if wildcard certs are ever needed.
- **Migrating NPM's existing Let's Encrypt cert/account data into Traefik** — rejected: NPM's certbot-style layout doesn't map cleanly onto Traefik's `acme.json`; re-issuing fresh under HTTP-01 is cheap and avoids carrying over stale state.
- **Replicating NPM's `block_exploits` nginx snippet** (enabled on most of the migrated hosts) as a Traefik middleware — rejected as disproportionate effort for a homelab already sitting behind Cloudflare's edge filtering. Recorded here as a consciously accepted gap, not a silent one.

## Consequences

- Adding a new public route to a Docker-routed backend now means adding labels to that service's own compose file, not visiting an admin UI.
- Adding a route to a new external-routed backend means editing the ingress stack's file-provider config directly.
- The Traefik dashboard is enabled but bound internal-only — no public route, unlike NPM's `81` admin port which was itself proxied (`npm.lexcode.dev`, dropped in this migration).
- Cutover is a hard cutover (NPM stopped, Traefik started on 80/443 directly) — brief downtime while HTTP-01 reissues every cert, accepted as low-cost for a homelab.
- Not every external-routed backend gets a real Let's Encrypt cert: `tracearr.lexcode.dev`, `unraid.lexcode.dev`, `ui.lexcode.dev` (router), `adguard2.lexcode.dev`, and `synology.lexcode.dev` have no public DNS record at all (confirmed NXDOMAIN on deploy) — they're LAN-only, reached without going through Cloudflare Tunnel, and were never candidates for public ACME validation regardless of proxy. Their routers omit `certResolver`, falling back to Traefik's default self-signed cert instead of retrying a validation that can never succeed (and would otherwise risk tripping Let's Encrypt's per-hostname failure rate limit).
- Pin `traefik:v3.7.10`, not a floating tag — v3.3 shipped a Docker client that doesn't negotiate its API version against the daemon and hardcodes an old default (1.24), which a sufficiently new Docker Engine (here: minimum accepted API 1.40) rejects outright, silently disabling every Docker-labeled route. `DOCKER_API_VERSION` does not fix this (Traefik's client doesn't read it) — only upgrading the image does. Re-verify this class of failure before ever pinning an older Traefik tag again.
