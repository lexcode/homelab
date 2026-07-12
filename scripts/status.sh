#!/usr/bin/env bash

set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mapfile -t all_stacks < <(
  cd "$repo_root" &&
    find . -mindepth 2 -maxdepth 2 -name compose.yml -printf '%h\n' |
      sort |
      sed 's#^\./##'
)

usage() {
  printf 'Usage: %s [--profile NAME ...] <stack|--all>\n' "$0" >&2
}

profiles=()
target=

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)
      if [[ $# -lt 2 || -z $2 ]]; then
        usage
        exit 2
      fi
      profiles+=("$2")
      shift 2
      ;;
    --profile=*)
      if [[ -z ${1#*=} ]]; then
        usage
        exit 2
      fi
      profiles+=("${1#*=}")
      shift
      ;;
    --all)
      if [[ -n $target ]]; then
        usage
        exit 2
      fi
      target=--all
      shift
      ;;
    -* )
      usage
      exit 2
      ;;
    *)
      if [[ -n $target ]]; then
        usage
        exit 2
      fi
      target=$1
      shift
      ;;
  esac
done

if [[ -z $target ]]; then
  usage
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required to parse Docker Compose status JSON.\n' >&2
  exit 2
fi

if [[ $target == --all ]]; then
  stacks=("${all_stacks[@]}")
else
  target_found=0
  for stack in "${all_stacks[@]}"; do
    if [[ $target == "$stack" ]]; then
      target_found=1
      break
    fi
  done
  if [[ $target_found -ne 1 ]]; then
    printf 'Unknown stack: %s\n' "$target" >&2
    exit 2
  fi
  stacks=("$target")
fi

profile_args=()
for profile in "${profiles[@]}"; do
  profile_args+=(--profile "$profile")
done

status=0

for stack in "${stacks[@]}"; do
  stack_dir=$repo_root/$stack

  if ! expected_output=$(cd "$stack_dir" && docker compose "${profile_args[@]}" config --services 2>/dev/null); then
    printf 'FAIL %s compose-config-error\n' "$stack"
    status=1
    continue
  fi
  mapfile -t expected_services <<<"$expected_output"

  if ! ps_json=$(cd "$stack_dir" && docker compose "${profile_args[@]}" ps --all --format json 2>/dev/null); then
    printf 'FAIL %s compose-status-error\n' "$stack"
    status=1
    continue
  fi
  if ! jq -e '
    type == "array"
    and all(.[];
      type == "object"
      and (.Service | type == "string")
      and (.State | type == "string")
      and (
        (has("Health") | not)
        or .Health == null
        or (.Health as $health
          | ($health | type == "string")
          and (["", "healthy", "starting", "unhealthy"] | index($health) != null))
      )
    )
  ' >/dev/null 2>&1 <<<"$ps_json"; then
    printf 'FAIL %s invalid-status-json\n' "$stack"
    status=1
    continue
  fi

  for service in "${expected_services[@]}"; do
    [[ -n $service ]] || continue

    if ! instance_output=$(jq -r --arg service "$service" '
        .[]
        | select(.Service == $service)
        | [(.State // "unknown" | ascii_downcase), (.Health // "" | ascii_downcase)]
        | @tsv
      ' <<<"$ps_json"); then
      printf 'FAIL %s invalid-status-json\n' "$stack"
      status=1
      break
    fi
    instances=()
    if [[ -n $instance_output ]]; then
      mapfile -t instances <<<"$instance_output"
    fi

    if [[ ${#instances[@]} -eq 0 ]]; then
      printf 'FAIL %s %s missing\n' "$stack" "$service"
      status=1
      continue
    fi

    service_state=running
    service_health=no-healthcheck
    for instance in "${instances[@]}"; do
      IFS=$'\t' read -r instance_state instance_health <<<"$instance"
      if [[ $instance_state != running ]]; then
        service_state=$instance_state
        service_health=
        break
      fi
      if [[ $instance_health == unhealthy ]]; then
        service_health=unhealthy
      elif [[ -n $instance_health && $service_health != unhealthy ]]; then
        service_health=$instance_health
      fi
    done

    if [[ $service_state != running ]]; then
      printf 'FAIL %s %s %s\n' "$stack" "$service" "$service_state"
      status=1
    elif [[ $service_health == unhealthy ]]; then
      printf 'FAIL %s %s running unhealthy\n' "$stack" "$service"
      status=1
    else
      printf 'PASS %s %s running %s\n' "$stack" "$service" "$service_health"
    fi
  done
done

exit "$status"
