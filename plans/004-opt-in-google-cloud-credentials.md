# Plan 004: Make Google cloud credentials an explicit Paperless GPT opt-in

> **Executor instructions**: Never read, print, copy, or rotate a credential
> file. Follow the plan and update Plan 004 in the index.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- documents/compose.yml documents/README.md documents/.env.example`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: security
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

The default Paperless GPT configuration uses Ollama, but the container always
receives the host user's Google application-default credential path. This
violates least privilege and may also create a directory at a file mount point
when credentials are absent. Google Document AI credentials should exist only
in an explicit opt-in configuration.

## Current state

- `documents/compose.yml:119` selects Ollama and line 136 selects LLM OCR.
- Google Document AI settings are commented examples at lines 145-150.
- `documents/compose.yml:186` unconditionally mounts
  `${HOME}/.config/gcloud/application_default_credentials.json` at
  `/app/credentials.json` without `:ro`.

## Target design

Use a small Compose override file named `documents/compose.google-docai.yml`.
It should add the credential mount only to `paperless-gpt`, mark it read-only,
and require a dedicated host path variable such as
`GOOGLE_APPLICATION_CREDENTIALS_HOST` rather than assuming `${HOME}`. The base
stack must contain no cloud credential mount.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Base config | `cd documents && docker compose --env-file .env.example config --quiet` | Exit 0 |
| Base credential scan | `cd documents && docker compose --env-file .env.example config --format json | jq -e '[.services["paperless-gpt"].volumes[]? | select(.target == "/app/credentials.json")] | length == 0'` | Exit 0 |
| Opt-in config | `cd documents && GOOGLE_APPLICATION_CREDENTIALS_HOST=/tmp/test-credentials.json docker compose --env-file .env.example -f compose.yml -f compose.google-docai.yml config --quiet` | Exit 0 |
| Opt-in mount | Same profiled render piped to `jq -e '[.services["paperless-gpt"].volumes[]? | select(.target == "/app/credentials.json" and .read_only == true)] | length == 1'` | Exit 0 |

## Scope

**In scope**: base Compose, new `documents/compose.google-docai.yml`, example
environment, documents README, root docs if needed, plan status.

**Out of scope**: real credential files, Google project/provider setup, changing
the default Ollama provider, API keys, runtime data, or starting containers.

## Steps

1. Remove the unconditional mount from `documents/compose.yml`.
2. Create the override with only the `paperless-gpt` service addition and a
   required host-path variable; mount it read-only.
3. Add an empty/commented example variable and document the exact two-file
   Compose command for Google Document AI users.
4. Explain that users who previously ran the container with credentials should
   assess and rotate them according to their cloud policy; never claim exposure
   occurred and never reproduce credential contents.
5. Run all four commands and `git diff --check`.

## Test plan

- Base render contains no `/app/credentials.json` mount.
- Opt-in two-file render contains exactly one read-only mount at that target.
- Missing opt-in host-path configuration fails clearly rather than falling back
  to a host home-directory credential.
- Both renders leave the Ollama provider configuration unchanged.

## Done criteria

- [ ] Base Paperless GPT has no cloud credential mount.
- [ ] Opt-in override adds exactly one read-only credential mount.
- [ ] Both configurations render successfully with non-secret test paths.
- [ ] Ollama remains the default documented configuration.
- [ ] Plan 004 is `DONE`.

## STOP conditions

- Compose merge behavior cannot add the mount without replacing unrelated
  service configuration.
- Upstream requires a different in-container credential target.
- Any step would require accessing actual cloud credentials.

## Maintenance notes

Future cloud-provider integrations should use separate opt-in overrides or
profiles and dedicated least-privilege credentials.
