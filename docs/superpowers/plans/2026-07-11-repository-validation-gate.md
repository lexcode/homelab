# Repository Validation Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one quiet, read-only command that validates all ten Docker Compose stacks from committed example environments without reading local `.env` files.

**Architecture:** Three service-level `env_file` declarations become selectable through `SERVICE_ENV_FILE`, while retaining `.env` as their runtime default. A root Bash script discovers stack directories deterministically, uses `.env.example` for interpolation and service environment loading, suppresses Compose output, and reports aggregate pass/fail status.

**Tech Stack:** Bash, Docker Compose v2, YAML, Markdown

---

### Task 1: Make service environment files validation-safe

**Files:**
- Modify: `media/compose.yml:45`
- Modify: `proxy/compose.yml:7`
- Modify: `terminal/compose.yml:38`

- [ ] **Step 1: Reproduce the clean-worktree failures**

Run:

```bash
for stack in media proxy terminal; do
  (cd "$stack" && docker compose --env-file .env.example config --quiet)
done
```

Expected: each stack fails because its service-level `env_file` requires a missing local `.env`.

- [ ] **Step 2: Parameterize the three service-level environment files**

In each active `env_file` block in `media/compose.yml`, `proxy/compose.yml`, and `terminal/compose.yml`, replace:

```yaml
env_file:
  - .env
```

with:

```yaml
env_file:
  - ${SERVICE_ENV_FILE:-.env}
```

Do not change the commented-out Gluetun example in `media/compose.yml`.

- [ ] **Step 3: Verify the explicit example override passes**

Run:

```bash
for stack in media proxy terminal; do
  (cd "$stack" && SERVICE_ENV_FILE=.env.example docker compose --env-file .env.example config --quiet)
done
```

Expected: exit 0 with no output.

- [ ] **Step 4: Verify the runtime default remains `.env`**

Run:

```bash
rg -n '^\s+- \$\{SERVICE_ENV_FILE:-\.env\}$' media/compose.yml proxy/compose.yml terminal/compose.yml
```

Expected: exactly three matches, one in each file.

- [ ] **Step 5: Commit the Compose compatibility change**

```bash
git add media/compose.yml proxy/compose.yml terminal/compose.yml
git commit -m "fix: allow example-only compose validation"
```

### Task 2: Add the repository-wide validator

**Files:**
- Create: `scripts/validate.sh`

- [ ] **Step 1: Verify the validator behavior is absent**

Run:

```bash
bash scripts/validate.sh --list
```

Expected: exit 127 with `No such file or directory`.

- [ ] **Step 2: Create the minimal validator**

Create executable `scripts/validate.sh` with:

```bash
#!/usr/bin/env bash

set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mapfile -t stacks < <(
  find "$repo_root" -mindepth 2 -maxdepth 2 -name compose.yml -printf '%h\n' |
    sort |
    sed "s#^$repo_root/##"
)

if [[ ${1:-} == "--list" ]]; then
  printf '%s\n' "${stacks[@]}"
  exit 0
fi

if [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--list]\n' "$0" >&2
  exit 2
fi

status=0

for stack in "${stacks[@]}"; do
  if [[ ! -f "$repo_root/$stack/.env.example" ]]; then
    printf 'FAIL %s\n' "$stack"
    status=1
    continue
  fi

  if (
    cd "$repo_root/$stack" &&
      SERVICE_ENV_FILE=.env.example \
        docker compose --env-file .env.example config --quiet >/dev/null 2>&1
  ); then
    printf 'PASS %s\n' "$stack"
  else
    printf 'FAIL %s\n' "$stack"
    status=1
  fi
done

exit "$status"
```

Then run:

```bash
chmod +x scripts/validate.sh
```

- [ ] **Step 3: Verify deterministic discovery**

Run:

```bash
comm -3 \
  <(find . -mindepth 2 -maxdepth 2 -name compose.yml -printf '%h\n' | sed 's#^./##' | sort) \
  <(bash scripts/validate.sh --list | sort)
```

Expected: exit 0 with no output.

- [ ] **Step 4: Verify all stacks pass quietly**

Run:

```bash
bash scripts/validate.sh
```

Expected: ten `PASS <stack>` lines and exit 0, with no rendered Compose configuration.

- [ ] **Step 5: Verify syntax and non-mutating behavior**

Run:

```bash
bash -n scripts/validate.sh
if rg -n 'compose (up|down|pull|build)|docker (run|rm)' scripts/validate.sh; then
  exit 1
fi
```

Expected: both checks exit 0 and the mutation scan prints no matches.

- [ ] **Step 6: Test aggregate failure behavior in an isolated fixture**

Run:

```bash
fixture=$(mktemp -d)
mkdir -p "$fixture/scripts" "$fixture/good" "$fixture/bad" "$fixture/bin"
cp scripts/validate.sh "$fixture/scripts/validate.sh"
touch "$fixture/good/compose.yml" "$fixture/good/.env.example"
touch "$fixture/bad/compose.yml" "$fixture/bad/.env.example"
printf '%s\n' '#!/usr/bin/env bash' '[[ "$PWD" != */bad ]]' >"$fixture/bin/docker"
chmod +x "$fixture/bin/docker"
set +e
output=$(PATH="$fixture/bin:$PATH" bash "$fixture/scripts/validate.sh")
fixture_status=$?
set -e
printf '%s\n' "$output"
test "$fixture_status" -eq 1
test "$output" = "$(printf 'FAIL bad\nPASS good')"
rm -rf "$fixture"
```

Expected: output is `FAIL bad` followed by `PASS good`; both assertions pass.

- [ ] **Step 7: Commit the validator**

```bash
git add scripts/validate.sh
git commit -m "test: add compose validation gate"
```

### Task 3: Document the validation contract

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `plans/README.md`

- [ ] **Step 1: Add root validation documentation**

In `README.md`, add this section immediately after `## Requirements`:

````markdown
## Validate configuration

Validate every stack from its committed `.env.example` without starting
containers or printing rendered configuration:

```bash
bash scripts/validate.sh
```

The command reports one pass/fail line per stack and exits non-zero if any
Compose configuration is invalid. Use `bash scripts/validate.sh --list` to
inspect the discovered stack directories.
````

- [ ] **Step 2: Extend the agent validation guidance**

In `AGENTS.md`, retain the existing per-stack rule and add:

```markdown
- Before completing repository changes, run `bash scripts/validate.sh` as the
  repository-wide read-only configuration gate.
```

- [ ] **Step 3: Mark Plan 005 done**

In `plans/README.md`, change only the Plan 005 status cell from its current
value to `DONE`.

- [ ] **Step 4: Verify documentation references**

Run:

```bash
rg -n 'scripts/validate\.sh|repository-wide read-only configuration gate' README.md AGENTS.md
rg -n '^\| 005 .*\| DONE \|$' plans/README.md
```

Expected: README documents the default and `--list` commands, AGENTS names the gate, and Plan 005 is `DONE`.

- [ ] **Step 5: Commit documentation and status**

```bash
git add README.md AGENTS.md plans/README.md
git commit -m "docs: document compose validation gate"
```

### Task 4: Run final verification

**Files:**
- Verify only; no intended modifications

- [ ] **Step 1: Run the exact Plan 005 checks**

Run:

```bash
bash scripts/validate.sh
bash -n scripts/validate.sh
if rg -n 'compose (up|down|pull|build)|docker (run|rm)' scripts/validate.sh; then
  exit 1
fi
comm -3 \
  <(find . -mindepth 2 -maxdepth 2 -name compose.yml -printf '%h\n' | sed 's#^./##' | sort) \
  <(bash scripts/validate.sh --list | sort)
```

Expected: ten passes; all other commands exit 0 with no output.

- [ ] **Step 2: Revalidate each changed Compose stack from its directory**

Run:

```bash
for stack in media proxy terminal; do
  (cd "$stack" && SERVICE_ENV_FILE=.env.example docker compose --env-file .env.example config --quiet)
done
```

Expected: exit 0 with no output.

- [ ] **Step 3: Check formatting and scope**

Run:

```bash
git diff HEAD~3 --check
git diff --name-only 1639174..HEAD
git status --short
```

Expected: no whitespace errors; changed files are the design, implementation plan, three Compose files, validator, root README, AGENTS guide, and Plan 005 status; the worktree is clean after commits.

- [ ] **Step 4: Review commit history**

Run:

```bash
git log --oneline 1639174..HEAD
```

Expected: focused commits for the approved design, Compose compatibility, validator, documentation/status, and implementation plan.
