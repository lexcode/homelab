# Plan 010: Establish reproducible container image updates

> **Executor instructions**: This is a migration plan, not a blanket search and
> replace. Do not guess versions or pull images without operator approval.
>
> **Drift check**:
> `git diff --stat 37de008..HEAD -- */compose.yml */README.md README.md docs`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/005-add-repository-validation-gate.md`
- **Category**: migration
- **Planned at**: commit `37de008`, 2026-07-10

## Why this matters

More than twenty services use floating `latest` or implicit tags, including
stateful and Docker-privileged services. Identical repository state can deploy
different artifacts over time, making rollback and incident attribution
unreliable. The fix must pair version pinning with an intentional update
workflow so images do not simply become stale.

## Current state

- Representative floating images: `proxy/compose.yml:43`,
  `monitoring/compose.yml:10`, `documents/compose.yml:15`,
  `media/compose.yml:96`, and `notifications/compose.yml:14`.
- Atuin demonstrates deliberate pinning at `terminal/compose.yml:5` and its
  README explains the policy at `terminal/README.md:80`.
- Database majors are already explicit (`postgres:18`, `mongo:4.4`, Redis 7)
  and must not be upgraded in this plan.

## Target design

Create `docs/IMAGE-UPDATES.md` with an inventory and tiered policy:

- Tier 1: Docker-socket, privileged, ingress, database, and stateful services;
  pin immutable digest plus readable version/tag where supported.
- Tier 2: ordinary applications; pin a tested release tag, optionally digest.
- Document update discovery, changelog review, backup prerequisite, per-stack
  config validation, smoke checks, rollback reference, and update cadence.

Then migrate images stack-by-stack using versions verified from official
upstream sources. Record the selected version/digest and date in the inventory.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Floating inventory | `rg -n '^\s*image:\s*[^#]*(latest\s*$|:[[:space:]]*(#|$))' */compose.yml` | No unapproved floating runtime images after migration |
| Validation | `bash scripts/validate.sh` | Exit 0 after each stack batch |
| Digest syntax | `rg -n '^\s*image:.*@sha256:[0-9a-f]{64}' */compose.yml` | Tier-1 pins visible |

## Scope

**In scope**: image lines in Compose files, stack README upgrade notes,
`docs/IMAGE-UPDATES.md`, root README link, plan status.

**Out of scope**: database major upgrades, automatic updater deployment,
runtime pulls/recreates without approval, application configuration changes,
or weakening backups/security.

## Steps

1. Inventory every image and classify privilege/state/blast radius.
2. Verify current stable releases and architecture support from official
   upstream sources. If network access is unavailable, STOP and provide the
   inventory rather than inventing pins.
3. Write the policy and smoke-check matrix before changing image references.
4. Pin one stack at a time, starting with proxy/management/monitoring, then
   stateful apps, then media applications. Do not change database majors.
5. Run repository validation after each stack; document required runtime smoke
   checks for the operator because this plan must not start containers itself.
6. Ensure no unexplained floating tags remain.

## Test plan

- Static inventory has no accidental `latest`/implicit tags.
- Every selected image supports the repository's Raspberry Pi/ARM deployment
  where required.
- All Compose files render.
- Documentation gives rollback and controlled update steps.

## Done criteria

- [ ] Every image is inventoried and classified.
- [ ] Tier-1 images are immutable pins; other images use deliberate releases.
- [ ] No database major changed.
- [ ] Update and rollback policy is documented.
- [ ] All stacks validate; Plan 010 is `DONE`.

## STOP conditions

- Official version/digest or ARM support cannot be verified.
- A selected release requires config/data migration beyond an image reference.
- Network access or image pulls require authorization not granted by operator.

## Maintenance notes

Pins are only safe when maintained. Every future update should record the old
reference, review upstream changes, validate config, and preserve rollback.
