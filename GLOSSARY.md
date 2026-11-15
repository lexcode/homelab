# Homelab

A single-host homelab of independent Docker Compose stacks, one per top-level directory, sharing a small number of purpose-named Docker networks and fronted by one ingress stack.

## Language

**Stack**:
A single Docker Compose project living in its own top-level directory (e.g. `media/`, `proxy/`, `dns/`). Each stack owns the Docker network(s) its own services need, and may join other stacks' networks as `external: true` to reach them.
_Avoid_: service (a stack contains many services), app.

**Ingress stack**:
The `proxy/` stack — the single entry point for all external traffic into the homelab. Bundles the reverse proxy (Traefik) with the tunnels that carry traffic to it (Cloudflare Tunnel, Tailscale Funnel).
_Avoid_: proxy stack (ambiguous with "reverse proxy" itself), edge stack.

**Docker-routed backend**:
A backend reachable by the ingress stack's reverse proxy through Docker's own service discovery — i.e. a container defined in one of this repo's stacks, on a network the ingress stack has joined. Routed by labels on the container itself.
_Avoid_: internal backend, local backend.

**External-routed backend**:
A backend with no Docker Compose stack in this repo — a separate physical machine or device on the LAN (NAS, router, a non-compose host). Not discoverable via Docker, so it's routed by a static entry instead of container labels.
_Avoid_: external target, static backend.
