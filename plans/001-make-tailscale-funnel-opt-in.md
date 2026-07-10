# Plan 001: Make Tailscale Funnel explicitly opt-in

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report; do not improvise. When done, update the status row for this plan in
> `plans/README.md`, unless a reviewer dispatched you and said they maintain
> the index.
>
> **Drift check (run first)**:
> `git diff --stat 37de008..HEAD -- proxy/compose.yml proxy/README.md README.md systemd/proxy.service proxy/.env.example`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live files before proceeding. Treat a
> material mismatch as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: bug
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

The documentation calls Tailscale Funnel optional, but `tailscale-funnel` is a
normal Compose service. Consequently, the documented bare `docker compose up
-d` command and `proxy.service` attempt to start it even for Cloudflare-only
deployments. This unnecessarily requests `/dev/net/tun`, `NET_ADMIN`, and
`NET_RAW`, and may create a restart failure when no Tailscale auth key is
configured. After this plan, default startup runs only Cloudflare Tunnel and
Nginx Proxy Manager; operators must explicitly enable the `tailscale` profile
to run Funnel.

## Current state

- `proxy/compose.yml` defines all three ingress services. The Funnel service is
  described as optional but has no Compose profile:

  ```yaml
  # proxy/compose.yml:12
  # Optional: Tailscale Funnel — publicly expose ONE service
  tailscale-funnel:
    container_name: tailscale-funnel
    image: tailscale/tailscale:latest
  ```

- `proxy/compose.yml:33` grants the optional service host networking
  capabilities:

  ```yaml
  devices:
    - /dev/net/tun:/dev/net/tun
  cap_add:
    - NET_ADMIN
    - NET_RAW
  ```

- `proxy/README.md:32` and `README.md:208` use bare `docker compose up -d` as
  the normal proxy startup command. The normal command must continue to start
  `cloudflared` and `nginx-proxy-manager` without Funnel.
- `proxy/README.md:109` currently starts the Funnel service by explicitly
  targeting `tailscale-funnel`. Replace this with the repository's canonical
  profile-based opt-in command so the documented mode is unambiguous.
- `systemd/proxy.service:8` runs bare `docker compose up`. Do not add the
  Tailscale profile to this command: default boot must remain Cloudflare/NPM
  only.
- `proxy/.env.example:5` already labels Tailscale settings optional. Retain the
  variable names and placeholder-only values; never add a real credential.
- Repository convention: each changed stack is validated from its service
  directory with `docker compose config`. Documentation is updated whenever
  setup or startup behavior changes.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Default config | `cd proxy && docker compose --env-file .env.example config --quiet` | Exit 0 with no errors |
| Default services | `cd proxy && docker compose --env-file .env.example config --services` | Lists `cloudflared` and `nginx-proxy-manager`; does not list `tailscale-funnel` |
| Profile config | `cd proxy && docker compose --env-file .env.example --profile tailscale config --quiet` | Exit 0 with no errors |
| Profile services | `cd proxy && docker compose --env-file .env.example --profile tailscale config --services` | Lists `cloudflared`, `nginx-proxy-manager`, and `tailscale-funnel` |
| Diff scope | `git diff --name-only` | Only the in-scope files and plan-status update are listed |

These commands render configuration only. Do not run `docker compose up`, pull
images, create containers, remove containers, or alter systemd state as part
of this plan.

## Scope

**In scope** (the only source/documentation files to modify):

- `proxy/compose.yml`
- `proxy/README.md`
- `README.md`
- `proxy/.env.example`, only if a short profile/command comment is needed to
  keep the template self-explanatory
- `plans/README.md`, status update only

**Out of scope** (do not modify):

- `systemd/proxy.service` — its bare Compose command should intentionally omit
  Funnel after the profile is added
- `proxy/config/tailscale-funnel/serve.json` — Funnel routing is unchanged
- Any other Compose stack or systemd unit
- Tailscale networking mode, capabilities, image tag, state storage, serve
  configuration, ACLs, or auth-key lifecycle
- Cloudflare Tunnel and Nginx Proxy Manager behavior
- Real `.env` files, runtime files under `proxy/data/`, credentials, or host
  Docker/systemd state

## Git workflow

- Branch: `advisor/001-make-tailscale-funnel-opt-in`
- Use a single logical commit after all verification passes.
- Match the repository's conventional commit style; suggested message:
  `fix: make tailscale funnel opt-in`
- Do not push or open a pull request unless the operator explicitly requests
  it.

## Steps

### Step 1: Gate Funnel behind the `tailscale` Compose profile

In `proxy/compose.yml`, add a profile to the `tailscale-funnel` service:

```yaml
tailscale-funnel:
  profiles:
    - tailscale
  container_name: tailscale-funnel
```

Keep the profile on this service only. Do not profile `cloudflared`,
`nginx-proxy-manager`, or `proxynetwork`. Update the nearby comment so it says
the service is enabled with the `tailscale` profile; remove the inaccurate
instruction to "leave commented" because the service is not commented out.

**Verify**:

```bash
cd proxy
docker compose --env-file .env.example config --quiet
docker compose --env-file .env.example config --services
```

Expected: both commands exit 0; the service list contains `cloudflared` and
`nginx-proxy-manager` but not `tailscale-funnel`.

Then verify opt-in rendering:

```bash
docker compose --env-file .env.example --profile tailscale config --quiet
docker compose --env-file .env.example --profile tailscale config --services
```

Expected: both commands exit 0; the second list also contains
`tailscale-funnel`.

### Step 2: Update the proxy-specific startup documentation

In `proxy/README.md`:

1. Keep the Quick start command as bare `docker compose up -d`, and explicitly
   state that it starts Cloudflare Tunnel and Nginx Proxy Manager only.
2. State that Funnel is excluded by default through the `tailscale` Compose
   profile.
3. In the Tailscale setup section, replace the opt-in startup command with:

   ```bash
   cd proxy
   docker compose --profile tailscale up -d
   docker logs -f tailscale-funnel
   ```

4. Explain that this profile command starts/updates the complete proxy stack
   with Funnel enabled. If documenting a Funnel-only targeted command as an
   alternative, verify its behavior first; do not make it the primary path.
5. State that the existing `proxy.service` does not enable Funnel. Operators
   who intentionally want Funnel at boot need a separately reviewed systemd
   customization; designing that customization is out of scope here.

Do not alter routing examples, Tailscale ACL examples, or the warning about
Cloudflare video proxying.

**Verify**:

```bash
rg -n "docker compose( --profile tailscale)? up -d|profile|proxy.service" proxy/README.md
```

Expected: the normal quick start remains bare; the Funnel section contains the
profile command; the text clearly states the systemd default excludes Funnel.

### Step 3: Align the root quick start

In the root `README.md` Proxy section, keep the normal command as:

```bash
docker compose up -d
```

Add one concise note immediately after the quick-start block stating that this
starts Cloudflare Tunnel and Nginx Proxy Manager only, and that Funnel is
enabled with `docker compose --profile tailscale up -d` after configuring its
optional variables. Link to the proxy README's Tailscale Funnel section rather
than duplicating the full setup.

Also ensure the systemd section does not imply that Funnel starts from
`proxy.service`; add a concise qualification if necessary.

**Verify**:

```bash
rg -n "Tailscale Funnel|--profile tailscale|proxy.service" README.md
```

Expected: the root README distinguishes default proxy startup from explicit
Funnel startup and does not promise Funnel at system boot.

### Step 4: Run final static verification

From `proxy/`, rerun both default and profiled configuration checks. Inspect
the resulting service-name lists only; do not print fully rendered Compose
configuration because it may interpolate values from a developer's real
environment when commands are later adapted.

**Verify**:

```bash
cd proxy
test "$(docker compose --env-file .env.example config --services | sort)" = "$(printf '%s\n' cloudflared nginx-proxy-manager | sort)"
test "$(docker compose --env-file .env.example --profile tailscale config --services | sort)" = "$(printf '%s\n' cloudflared nginx-proxy-manager tailscale-funnel | sort)"
docker compose --env-file .env.example config --quiet
docker compose --env-file .env.example --profile tailscale config --quiet
```

Expected: all four commands exit 0 with no output from the two `test`
assertions.

Finally run from the repository root:

```bash
git diff --check
git diff --name-only
```

Expected: `git diff --check` exits 0. The changed-file list contains only
`proxy/compose.yml`, `proxy/README.md`, `README.md`, optional
`proxy/.env.example`, and the `plans/README.md` status update. If the working
tree already had unrelated user changes, leave them untouched and identify
them separately rather than reverting them.

## Test plan

There is no conventional test suite in this repository. Treat Compose
rendering and exact service selection as the regression tests:

- Default case: no profile selects only `cloudflared` and
  `nginx-proxy-manager`.
- Opt-in case: `--profile tailscale` additionally selects
  `tailscale-funnel`.
- Both configurations pass `docker compose config --quiet` using
  `proxy/.env.example`.
- Documentation contains both the default and opt-in commands and describes
  the systemd behavior accurately.
- No containers are started during verification.

## Done criteria

- [ ] `tailscale-funnel` has exactly one profile named `tailscale`.
- [ ] Default `config --services` excludes `tailscale-funnel`.
- [ ] Profiled `config --services` includes all three proxy services.
- [ ] Default and profiled `config --quiet` commands exit 0.
- [ ] `proxy/README.md` documents the canonical profile command.
- [ ] Root `README.md` distinguishes default and opt-in startup.
- [ ] Documentation states that the existing `proxy.service` excludes Funnel.
- [ ] No Docker containers, images, networks, volumes, or systemd units were
  changed during implementation.
- [ ] `git diff --check` exits 0.
- [ ] No source/documentation files outside the in-scope list were modified.
- [ ] The Plan 001 row in `plans/README.md` is updated to `DONE`.

## STOP conditions

Stop and report back without improvising if:

- The current service names or proxy Compose structure materially differ from
  the excerpts in this plan.
- The installed Docker Compose version rejects service-level `profiles`.
- Bare `config --services` still includes `tailscale-funnel` after the profile
  is added.
- Profiled config requires changing Funnel networking, capabilities, auth, or
  serve configuration to render successfully.
- Existing operator requirements demand that `proxy.service` continue to
  start Funnel automatically. That requires a separate decision about systemd
  opt-in design.
- The implementation appears to require editing a real `.env`, anything under
  `proxy/data/`, another stack, or an out-of-scope systemd unit.
- An in-scope file has user changes that conflict with this plan.
- A verification command fails twice after one reasonable correction.

## Maintenance notes

- Future Funnel changes must preserve the `tailscale` profile unless the
  maintainer intentionally changes the default exposure policy.
- Reviewers should verify service selection with both profile states, not only
  YAML syntax.
- If automatic Funnel startup at boot is desired later, design it explicitly
  through a systemd environment/override or separate unit, and test it against
  the proxy external-network ordering. Do not silently add `--profile
  tailscale` to the shared default unit.
- Image pinning, privilege reduction, auth-key handling, userspace networking,
  and proxy systemd lifecycle improvements remain separate audit findings.
