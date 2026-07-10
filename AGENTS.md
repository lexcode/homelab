# Homelab Agent Guide

- This repository contains Docker Compose stacks, one per service directory.
- Follow the existing structure and read the relevant service `README.md` before editing.
- Keep compose files simple and update documentation when behavior or setup changes.
- Validate changed stacks with `docker compose config` from their directory.
- Never commit `.env`, secrets, credentials, or generated files under `*/data/`.
- Do not run destructive Docker or systemd commands unless the user explicitly asks.
