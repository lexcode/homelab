#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readme="$repo_root/pulsearr/README.md"
compose_file="$repo_root/pulsearr/compose.yml"
env_example="$repo_root/pulsearr/.env.example"
compiled_command='docker compose exec -T worker /app/scripts/container-entrypoint.sh worker'

if ! grep -Fq 'command: ["worker", "schedule"]' "$compose_file"; then
  printf 'not ok - Pulsearr worker does not start the internal scheduler\n' >&2
  exit 1
fi

if ! grep -Fq 'DATABASE_URL=postgresql://${PULSEARR_DB_USER}:${PULSEARR_DB_PASSWORD}@db:5432/${PULSEARR_DB_NAME}' "$env_example"; then
  printf 'not ok - Pulsearr DATABASE_URL does not use the configured database identity\n' >&2
  exit 1
fi

if ! grep -Fq 'openssl rand -hex 32' "$env_example"; then
  printf 'not ok - Pulsearr database password guidance is not URL-safe\n' >&2
  exit 1
fi

if ! grep -Fq '(cd ../media && docker compose up -d)' "$readme" ||
  ! grep -Fq '(cd ../notifications && docker compose up -d)' "$readme"; then
  printf 'not ok - Pulsearr setup does not start dependency stacks from their directories\n' >&2
  exit 1
fi

if grep -Fq 'docker compose -f ../media/compose.yml up -d' "$readme" ||
  grep -Fq 'docker compose -f ../notifications/compose.yml up -d' "$readme"; then
  printf 'not ok - Pulsearr setup loads dependency Compose files from the wrong directory\n' >&2
  exit 1
fi

if ! grep -Fq "$compiled_command status" "$readme"; then
  printf 'not ok - Pulsearr status verification does not use the compiled worker entrypoint\n' >&2
  exit 1
fi

if ! grep -Fq "$compiled_command sync" "$readme"; then
  printf 'not ok - Pulsearr sync verification does not use the compiled worker entrypoint\n' >&2
  exit 1
fi

sync_count=$(grep -Fc "$compiled_command sync" "$readme")
if [ "$sync_count" -lt 2 ]; then
  printf 'not ok - Pulsearr verification does not repeat the sync idempotency check\n' >&2
  exit 1
fi

if ! grep -Fq "$compiled_command refresh-library" "$readme"; then
  printf 'not ok - Pulsearr verification does not document Jellyfin refresh\n' >&2
  exit 1
fi

if ! grep -Fq "$compiled_command weekly" "$readme"; then
  printf 'not ok - Pulsearr verification does not document weekly summaries\n' >&2
  exit 1
fi

if grep -Fq 'docker compose exec -T worker pnpm worker' "$readme"; then
  printf 'not ok - Pulsearr verification still invokes the source worker command\n' >&2
  exit 1
fi

printf 'Pulsearr deployment test passed\n'
