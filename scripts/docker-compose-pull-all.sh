#!/usr/bin/env bash
# Pull latest images for every directory containing a docker compose file
# Usage: ./scripts/docker-compose-pull-all.sh

set -euo pipefail

names=(
  -name docker-compose.yml -o -name docker-compose.yaml
  -o -name compose.yml -o -name compose.yaml
  -o -name 'compose.*.yml'
)

# Parent dirs of compose files, unique sorted (requires GNU find — e.g. Arch/Linux)
mapfile -t dirs < <(
  find . -type f \( "${names[@]}" \) -not -path './.git/*' \
    -printf '%h\n' 2>/dev/null | sort -u
)

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No docker compose files found. Nothing to pull."
  exit 0
fi

if docker compose version &>/dev/null; then
  compose_pull() { (cd "$1" && docker compose pull); }
  echo "Using: docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  compose_pull() { (cd "$1" && docker-compose pull); }
  echo "Using: docker-compose"
else
  echo "Neither 'docker compose' nor 'docker-compose' found in PATH." >&2
  echo "Install Docker Compose or ensure docker plugin is available." >&2
  exit 2
fi

for d in "${dirs[@]}"; do
  echo
  echo "==> Pulling in: $d"
  compose_pull "$d" || echo "Pull failed in $d" >&2
done

echo
echo "Done."
