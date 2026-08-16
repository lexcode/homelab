#!/usr/bin/env bash
# Pull latest images for every directory containing a docker compose file
#
# Usage:
#   ./scripts/docker-compose-pull-all.sh
#   ./scripts/docker-compose-pull-all.sh --sequential   # Pi / low-RAM hosts
#
# Set HOMELAB_COMPOSE_PULL_SEQUENTIAL=1 for the same as --sequential.

set -euo pipefail

sequential=false
[[ "${HOMELAB_COMPOSE_PULL_SEQUENTIAL:-}" == "1" ]] && sequential=true
for _arg in "$@"; do
  [[ "$_arg" == --sequential || "$_arg" == -s ]] && sequential=true
done

names=(
  -name docker-compose.yml -o -name docker-compose.yaml
  -o -name compose.yml -o -name compose.yaml
  -o -name 'compose.*.yml'
)

# Parent dirs of compose files, unique sorted (requires GNU find — e.g. Arch/Linux, Raspberry Pi OS)
mapfile -t dirs < <(
  find . -type f \( "${names[@]}" \) -not -path './.git/*' \
    -printf '%h\n' 2>/dev/null | sort -u
)

if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No docker compose files found. Nothing to pull."
  exit 0
fi

if docker compose version &>/dev/null; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "Neither 'docker compose' nor 'docker-compose' found in PATH." >&2
  echo "Install Docker Compose or ensure docker plugin is available." >&2
  exit 2
fi

if [[ "$sequential" == true ]]; then
  echo "Using: ${COMPOSE[*]} (one service at a time — easier on low-RAM / SD-card hosts)"
else
  echo "Using: ${COMPOSE[*]}"
fi

compose_pull_in_dir() {
  (
    cd "$1" || exit 1
    if [[ "$sequential" == true ]]; then
      local services s any=false
      services=$("${COMPOSE[@]}" config --services) || exit 1
      mapfile -t svc <<< "$services"
      for s in "${svc[@]}"; do
        [[ -z "$s" ]] && continue
        any=true
        "${COMPOSE[@]}" pull "$s"
      done
      if [[ "$any" == false ]]; then
        "${COMPOSE[@]}" pull
      fi
    else
      "${COMPOSE[@]}" pull
    fi
  )
}

for d in "${dirs[@]}"; do
  echo
  echo "==> Pulling in: $d"
  compose_pull_in_dir "$d" || echo "Pull failed in $d" >&2
done

echo
echo "Done."
