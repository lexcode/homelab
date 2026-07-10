# Plan 005: Add a repository-wide configuration validation gate

> **Executor instructions**: This is the prerequisite for most other plans.
> The validator must be read-only and must never print resolved environment
> values. Update Plan 005 in the index after verification.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- AGENTS.md README.md scripts .github`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

Each service has a Compose file and example environment, but there is no single
command or CI job that validates them. Syntax, interpolation, service-profile,
and documentation-driven configuration changes can therefore fail only during
deployment. A quiet validation script provides a safe baseline for all later
plans.

## Current state

- Ten stack directories contain `compose.yml`: analytics, dns, documents,
  homepage, management, media, monitoring, notifications, proxy, terminal.
- Each has `.env.example`; only management currently lacks a real local `.env`.
- `AGENTS.md` requires `docker compose config` from changed stack directories.
- There is no `.github/workflows`, root Makefile/task runner, or validation
  script.
- All ten stacks passed quiet local rendering during the audit when the example
  environment was selected explicitly.

## Target design

Create executable `scripts/validate.sh` using POSIX-compatible Bash practices
already available on this Linux host. It must discover or enumerate the ten
stack directories, run from each directory, select `.env.example` explicitly,
use `docker compose config --quiet`, print only stack name plus pass/fail, and
return non-zero if any stack fails. It must not invoke `up`, `pull`, or full
`config` output. Add a minimal GitHub Actions workflow only if Docker Compose v2
is available in the selected runner without custom privileged setup.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Validator | `bash scripts/validate.sh` | Ten PASS results, exit 0 |
| Shell syntax | `bash -n scripts/validate.sh` | Exit 0 |
| Mutation scan | `rg -n 'compose (up|down|pull|build)|docker (run|rm)' scripts/validate.sh` | No matches |
| Coverage | `comm -3 <(find . -mindepth 2 -maxdepth 2 -name compose.yml -printf '%h\n' | sed 's#^./##' | sort) <(bash scripts/validate.sh --list | sort)` | No output |

## Scope

**In scope**: new `scripts/validate.sh`, optional one workflow under
`.github/workflows/`, `README.md`, `AGENTS.md`, and plan status.

**Out of scope**: installing dependencies, pulling images, starting stacks,
reading real `.env`, validating runtime data, systemd redesign, or formatting
unrelated files.

## Steps

1. Implement `--list` so coverage can be machine-checked without validation.
2. Implement quiet validation for every discovered stack with its own
   `.env.example`; preserve the working directory convention.
3. Add clear aggregate failure handling while avoiding resolved config output.
4. Document `bash scripts/validate.sh` in root README and AGENTS.md as the
   repository-wide gate; retain per-stack `docker compose config` guidance.
5. If adding CI, run only shell syntax and the validator. If Compose is absent
   on the runner, omit CI and document local validation rather than installing
   arbitrary tooling.
6. Run all commands plus `git diff --check`.

## Test plan

- `--list` returns exactly the ten stack directories.
- Normal run validates every stack and exits 0.
- Temporarily point a copy of the script at a deliberately invalid fixture
  under `/tmp` if failure-path testing is needed; remove the fixture afterward.
- Script contains no mutating Docker commands and prints no resolved secrets.

## Done criteria

- [ ] One root command validates all stacks quietly.
- [ ] Stack discovery and `--list` are complete and deterministic.
- [ ] Script is syntax-valid and non-mutating.
- [ ] Documentation and AGENTS.md name the command.
- [ ] Optional CI, if present, passes without privileged mutation.
- [ ] Plan 005 is `DONE`.

## STOP conditions

- Validation requires reading a real `.env` or emitting resolved config.
- A stack cannot render from `.env.example`; report the stack and error instead
  of weakening validation silently.
- CI requires Docker daemon mutation or network downloads beyond the runner's
  normal toolchain.

## Maintenance notes

Any new stack must add `compose.yml` and `.env.example` and appear in `--list`.
Later plans should add targeted assertions to this baseline where practical.
