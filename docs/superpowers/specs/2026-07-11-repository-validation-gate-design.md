# Repository Validation Gate Design

## Goal

Add one read-only command that validates every Docker Compose stack from its
committed `.env.example` without reading local `.env` files or printing
resolved environment values.

## Scope

- Add `scripts/validate.sh` with deterministic stack discovery, `--list`, and
  aggregate pass/fail reporting.
- Make the service-level environment files in `media`, `proxy`, and `terminal`
  selectable for validation while preserving `.env` as the runtime default.
- Document the repository-wide gate in `README.md` and `AGENTS.md` while
  retaining per-stack validation guidance.
- Update Plan 005 to `DONE` only after all verification passes.
- Do not add CI, because Plan 005 does not require it and local Docker Compose
  availability does not prove the GitHub-hosted runner contract.

## Compose Environment Design

Three services currently declare `env_file: .env`, which prevents clean
worktrees and CI checkouts from rendering even when Compose receives
`--env-file .env.example`. Change only those service-level declarations to:

```yaml
env_file:
  - ${SERVICE_ENV_FILE:-.env}
```

Normal startup remains unchanged because the default is `.env`. The validator
sets `SERVICE_ENV_FILE=.env.example` for the Compose process and also passes
`--env-file .env.example` for interpolation. This validates both interpolation
and service environment-file parsing from committed placeholders without
creating, copying, or reading a real `.env`.

## Validator Behavior

The Bash script resolves the repository root from its own location and
discovers directories containing a root-level stack `compose.yml`. Results are
sorted for deterministic output.

`bash scripts/validate.sh --list` prints only stack directory names and exits
successfully without invoking Docker Compose. Any other argument is rejected
with a short usage message and a non-zero exit status.

The default command validates every discovered stack from within that stack's
directory using:

```bash
SERVICE_ENV_FILE=.env.example docker compose --env-file .env.example config --quiet
```

Compose output is suppressed so resolved values and detailed interpolation
errors cannot leak. The script prints one `PASS <stack>` or `FAIL <stack>` line
and returns non-zero after checking all stacks if any failed. A missing
`.env.example` is a stack failure rather than a reason to fall back to `.env`.

## Error Handling And Security

- Never invoke `up`, `down`, `pull`, `build`, `run`, or other mutating Docker
  commands.
- Never render full Compose configuration.
- Never fall back to a local `.env` during validation.
- Continue after individual failures so operators see the complete failing
  stack set, while returning a failing aggregate status.
- Keep diagnostics intentionally limited to the stack name and pass/fail
  state; operators can run a targeted command manually when investigating.

## Verification

- First prove the absent validator fails and the three service-level `.env`
  references fail in a clean worktree.
- After the Compose override changes, verify `media`, `proxy`, and `terminal`
  render with the explicit example override.
- Verify `--list` exactly matches all discovered stacks.
- Run the validator and require ten passes.
- Check Bash syntax and scan for mutating Docker commands.
- Test aggregate failure behavior against a temporary repository-shaped
  fixture without changing tracked stack files.
- Run each changed stack's `docker compose config --quiet`, then
  `git diff --check` and a scope review.
