# Plan 003: Require an explicit Gotify administrator password

> **Executor instructions**: Follow all steps and update Plan 003 in the index.
> Do not inspect or print the real `notifications/.env`.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- notifications/compose.yml notifications/.env.example notifications/README.md README.md`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: security
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Gotify currently falls back to a predictable administrator password and binds
its UI to all host interfaces. Because the password is applied on first
database creation, one accidental initial startup permanently creates the weak
credential until manually changed. Compose should fail before startup when the
password is missing or left at the documented placeholder.

## Current state

- `notifications/compose.yml:25` uses
  `${GOTIFY_DEFAULTUSER_PASS:-changeme}`.
- `notifications/.env.example:6` contains the placeholder `changeme`.
- `notifications/README.md:15` merely recommends changing the placeholder.
- The service publishes `${GOTIFY_HTTP_PORT:-8688}:80` at line 22.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Valid example | `cd notifications && GOTIFY_DEFAULTUSER_PASS=test-only-placeholder docker compose --env-file .env.example config --quiet` | Exit 0 |
| Missing value | `cd notifications && env -u GOTIFY_DEFAULTUSER_PASS docker compose --env-file /dev/null config --quiet` | Non-zero with required-variable message |
| No weak fallback | `rg -n 'changeme|GOTIFY_DEFAULTUSER_PASS:-' notifications/compose.yml notifications/.env.example notifications/README.md` | No active weak default; docs may mention migration warning only |

## Scope

**In scope**: `notifications/compose.yml`, `notifications/.env.example`,
`notifications/README.md`, root `README.md` if its quick-start comment needs
alignment, and plan status.

**Out of scope**: reading/changing real credentials, resetting existing Gotify
databases, binding ports, registration policy, iGotify profiles, or containers.

## Git workflow

- Branch: `advisor/003-require-gotify-admin-password`
- Suggested commit: `fix: require gotify admin password`

## Steps

### Step 1: Make interpolation fail closed

Replace the fallback with required interpolation, using a clear message, for
example `${GOTIFY_DEFAULTUSER_PASS:?Set GOTIFY_DEFAULTUSER_PASS in notifications/.env}`.

**Verify**: the valid example renders and the `/dev/null` environment test
fails specifically because the password is required.

### Step 2: Remove the usable placeholder

Set the example value empty and add a comment requiring a strong unique value.
Do not put a sample password in the repository.

### Step 3: Document first-run and existing-install behavior

State that startup refuses missing configuration and that changing the variable
does not automatically change an administrator password already stored in
Gotify's database. Existing users must rotate it through the supported UI or
upstream procedure; do not prescribe destructive data removal.

**Verify**: `rg -n "GOTIFY_DEFAULTUSER_PASS|first|existing" notifications/README.md README.md` shows the required setup and persistence warning.

## Test plan

- Required value present: config exits 0.
- Required value absent: config exits non-zero.
- No tracked file contains a usable default administrator password.

## Done criteria

- [ ] Missing password prevents Compose rendering.
- [ ] Example contains no usable password.
- [ ] Existing-install rotation caveat is documented.
- [ ] No secret or real `.env` was read or changed.
- [ ] Plan 003 is `DONE`.

## STOP conditions

- Compose required interpolation is unsupported on the installed version.
- Validation would expose a real environment value.
- The fix requires modifying existing Gotify runtime data.

## Maintenance notes

Keep this required-variable check in any future validation script. Port
restriction remains Plan 007 and must not be folded into this change.
