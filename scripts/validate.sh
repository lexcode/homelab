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
