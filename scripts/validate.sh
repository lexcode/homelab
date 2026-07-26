#!/usr/bin/env bash

set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mapfile -t stacks < <(
  cd "$repo_root" &&
    find . -mindepth 2 -maxdepth 3 -name compose.yml -printf '%h\n' |
      sort |
      sed 's#^\./##'
)

if [[ $# -eq 1 && $1 == "--list" ]]; then
  if [[ ${#stacks[@]} -gt 0 ]]; then
    printf '%s\n' "${stacks[@]}"
  fi
  exit 0
fi

if [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--list]\n' "$0" >&2
  exit 2
fi

status=0

if [[ ${#stacks[@]} -eq 0 ]]; then
  printf 'FAIL no-stacks\n'
  exit 1
fi

for stack in "${stacks[@]}"; do
  if [[ ! -f "$repo_root/$stack/.env.example" ]]; then
    printf 'FAIL %s\n' "$stack"
    status=1
    continue
  fi

  if (
    cd "$repo_root/$stack" &&
      GOTIFY_DEFAULTUSER_PASS=test-only-placeholder \
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
