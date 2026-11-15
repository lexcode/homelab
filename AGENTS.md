
# Homelab — Agent Instructions

## Project overview

This repository is the infrastructure-as-code source of truth for a personal
homelab. It contains independent Docker Compose stacks, supporting scripts,
systemd units, configuration, and documentation.

The goal is to keep the infrastructure maintainable, secure, reproducible,
and understandable — not simply to make containers start.

## 1. Working principles

- Inspect the existing implementation before proposing or making changes.
- Prefer small, focused changes over unnecessary restructuring.
- Preserve established conventions unless there is a clear reason to change them.
- Do not introduce additional services, dependencies, tools, or abstractions
  without explaining why they are needed.
- Do not assume that a proposed improvement is automatically worth implementing.
- Explain trade-offs when multiple approaches are reasonable.
- Never invent infrastructure details, paths, IP addresses, credentials,
  hardware capabilities, or deployment state.
- Treat repository documentation and actual configuration as the primary
  sources of truth. Flag contradictions rather than silently choosing one.

## 2. Understand the repository before working

Before making changes:

1. Read the root `README.md`.
2. Read `CONTEXT.md` when it exists.
3. Read `docs/STRUCTURE.md` when the change affects repository structure.
4. Read the relevant stack's `README.md`.
5. Inspect its `compose.yml`, `.env.example`, scripts, and related configuration.
6. Check relevant documentation in `docs/agents/` and applicable ADRs.
7. Check Git status and existing user changes before editing.

Do not overwrite, discard, or reformat unrelated user changes.

## 3. Repository architecture

### Compose stacks

- Each top-level service directory represents an independent Compose stack.
- A stack owns its Compose configuration and the networks required by its
  services.
- A stack may join another stack's network using `external: true`.
- Preserve the existing network ownership and cross-stack dependencies.
- Do not combine independent stacks into one Compose project without an
  explicit architectural reason.

### Networking and ingress

- `proxy/` is the ingress stack and the entry point for externally routed
  homelab services.
- Understand the distinction between Docker-routed backends and
  external-routed backends before changing routing.
- Docker-routed backends use Docker service discovery and the relevant
  shared networks.
- External-routed backends require explicit routing configuration.
- Do not expose LAN-only services publicly unless explicitly requested.
- Do not change DNS, tunnels, proxy routes, firewall rules, or network
  subnets without understanding their impact on other stacks.

### Persistent data

- Runtime state normally lives under each stack's `data/` directory.
- Runtime data is not source code and must not be committed.
- Treat databases, application configuration, media libraries, and backups
  as persistent user data.
- Never assume a container can safely recreate its data.
- Never change volume names, bind mounts, database paths, or storage
  locations casually.
- Preserve existing data paths unless migration is explicitly part of the task.

### Host and infrastructure assumptions

- Do not assume every stack runs on the same physical host.
- Do not assume a path exists on the target machine because it exists locally.
- Do not assume Docker networks, mounts, devices, GPUs, or systemd units
  exist on a host without evidence.
- Verify host-specific requirements from documentation or user-provided
  inspection output.
- Keep host-specific values configurable through environment variables
  where appropriate.

## 4. Docker Compose conventions

- Use Docker Compose v2 and the existing `compose.yml` naming convention.
- Keep each stack independently understandable and deployable.
- Use `.env.example` to document required configuration.
- Keep real values and secrets in untracked `.env` files or an appropriate
  secret-management mechanism.
- Prefer explicit, meaningful service names, network names, volume names,
  health checks, and restart policies.
- Use image tags deliberately. Avoid silently changing versions or switching
  image maintainers.
- Preserve existing CPU architecture compatibility where relevant.
- Consider Raspberry Pi / ARM64 compatibility when changing images.
- Consider resource consumption on low-memory hosts.
- Avoid unnecessary privileged containers, host networking, and Docker
  socket access.
- When elevated privileges or host access are necessary, document why.

Before changing a stack, understand:

- Its services and dependencies.
- Published ports and internal ports.
- Networks and external networks.
- Bind mounts and named volumes.
- Environment variables and secrets.
- Health checks and restart behavior.
- Reverse-proxy labels and routing.
- Host-specific requirements.

## 5. Security and secrets

- Never commit `.env` files, API keys, passwords, tokens, private keys,
  certificates, or other credentials.
- Never put secrets in Compose comments, documentation, command examples,
  logs, or generated reports.
- Update `.env.example` when adding, removing, or renaming environment
  variables. Use safe placeholder values.
- Do not weaken authentication, TLS, network isolation, or access controls
  to make a deployment easier.
- Do not expose administrative interfaces or databases publicly by default.
- Treat Docker socket access, privileged containers, host mounts, and
  code-execution services as sensitive capabilities.
- Follow the existing security-audit skill when the task involves a security
  review or audit. Do not perform a full audit just because the skill exists.

## 6. Scripts and automation

- Prefer scripts that are idempotent, predictable, and safe to rerun.
- Use `set -euo pipefail` in Bash scripts where appropriate.
- Validate arguments and fail with useful error messages.
- Avoid destructive defaults.
- Make scripts explicit about which host, stack, and environment they target.
- Do not silently fall back to a different host, path, or configuration.
- Document prerequisites and expected effects.
- Keep read-only inspection commands separate from commands that change
  infrastructure.

## 7. Validation

For Compose changes:

1. Run the affected stack's Compose validation.
2. Run the repository-wide validation gate:

   ```bash
   bash scripts/validate.sh
   ```

3. Review the rendered configuration when necessary, taking care not to
   expose secrets.
4. Check for changes to networks, volumes, ports, mounts, dependencies,
   health checks, and security settings.

For shell changes:

- Run ShellCheck when available.
- Check syntax with `bash -n`.
- Test safe argument and error-handling paths where practical.

For repository changes:

- Run relevant tests.
- Run `git diff --check`.
- Review the complete diff.
- Report any checks that could not be performed and why.

Configuration validation does not prove that a service will run correctly
on its target host. Host mounts, device access, DNS, networking, permissions,
and application health may require separate verification.

## 8. Deployment and destructive operations

Default to preparing and validating changes, not deploying them.

Never execute infrastructure-changing commands unless the user explicitly
requests the deployment or operation.

This includes, but is not limited to:

- `docker compose up`, `down`, `restart`, or `pull`
- `docker system prune`
- Removing containers, images, networks, or volumes
- Database migrations or resets
- Deleting or moving persistent data
- Changing systemd services
- Modifying firewall, DNS, routing, or tunnel configuration
- Rebooting or shutting down hosts

Before a potentially destructive operation:

1. Explain what will change.
2. Identify affected stacks, hosts, and persistent data.
3. Verify the backup and recovery approach.
4. Explain the rollback plan.
5. Obtain explicit approval.

Never use `docker compose down -v` or delete persistent data as a
troubleshooting shortcut.

## 9. Documentation

Keep documentation aligned with implementation.

When changing a stack, update its README if setup, configuration,
ports, networking, storage, security, backup, recovery, or operational
behavior changes.

Update other documentation when relevant:

- `README.md` — repository overview and operational entry points.
- `docs/STRUCTURE.md` — directory and stack layout.
- `CONTEXT.md` — established domain terminology.
- `docs/adr/` — architectural decisions and their rationale.
- `docs/agents/` — agent-specific working guidance.

Do not create documentation files simply to describe trivial changes.
Do not duplicate information unnecessarily.

## 10. Skills and specialist workflows

Use skills for workflows that are conditional, specialised, or reusable.

Before starting a relevant task:

- Check the available skills in the repository.
- Load only the skill relevant to the current task.
- Follow its instructions and referenced resources.
- Do not apply unrelated specialist workflows.

Examples:

- Security reviews → `security-audit`.
- Media stack work or troubleshooting (Radarr, Sonarr, Lidarr, Prowlarr,
  Bazarr, Seerr, qBittorrent/VPN, Beets) → `arr-media-stack`.
- Docker Compose changes → use an available Compose-specific skill,
  if one exists.
- Proxmox migration → use a Proxmox-specific skill, if one exists.
- Backup and recovery work → use a backup/recovery skill, if one exists.

If a workflow is repeated and substantial, consider creating a dedicated
skill instead of expanding this file.

Do not create a skill for a one-off task or duplicate the same instructions
in multiple places.

## 11. Git and change management

- Inspect `git status` before editing.
- Preserve user changes and untracked files.
- Do not reset, clean, rebase, or force-push unless explicitly requested.
- Do not commit changes unless explicitly requested.
- Keep changes focused and reviewable.
- Never include runtime data, generated secrets, or local environment files
  in commits.

Before completing a task, provide:

1. A concise summary of what changed.
2. The files affected.
3. Validation performed and its result.
4. Any assumptions or unresolved questions.
5. Deployment or migration steps still requiring approval.

## 12. Communication

- Be direct and technically precise.
- Explain risks before recommending infrastructure changes.
- Distinguish verified facts from assumptions.
- Prefer practical solutions over unnecessary complexity.
- Ask only for information that is genuinely needed.
- If the requested approach is unsafe or unnecessarily complex, explain
  why and recommend a better alternative.
