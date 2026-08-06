# Homelab Agent Guide

- This repository contains Docker Compose stacks, one per service directory.
- Follow the existing structure and read the relevant service `README.md` before editing.
- Keep compose files simple and update documentation when behavior or setup changes.
- Validate changed stacks with `docker compose config` from their directory.
- Before completing repository changes, run `bash scripts/validate.sh` as the repository-wide read-only configuration gate.
- Never commit `.env`, secrets, credentials, or generated files under `*/data/`.
- Do not run destructive Docker or systemd commands unless the user explicitly asks.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`lexcode/homelab`), managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout — `CONTEXT.md` and `docs/adr/` at the repo root, created lazily as decisions/terms get resolved. See `docs/agents/domain.md`.
