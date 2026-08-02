#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readme="$repo_root/pulsearr/README.md"
compiled_command='docker compose exec -T worker /app/scripts/container-entrypoint.sh worker'

if ! grep -Fq "$compiled_command status" "$readme"; then
  printf 'not ok - Pulsearr status verification does not use the compiled worker entrypoint\n' >&2
  exit 1
fi

if ! grep -Fq "$compiled_command sync" "$readme"; then
  printf 'not ok - Pulsearr sync verification does not use the compiled worker entrypoint\n' >&2
  exit 1
fi

if grep -Fq 'docker compose exec -T worker pnpm worker' "$readme"; then
  printf 'not ok - Pulsearr verification still invokes the source worker command\n' >&2
  exit 1
fi

printf 'Pulsearr deployment test passed\n'
