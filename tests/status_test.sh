#!/usr/bin/env bash

set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin"
cat >"$test_root/bin/docker" <<'EOF'
#!/usr/bin/env bash

if [[ $1 != compose ]]; then
  exit 99
fi
shift

profile=
if [[ ${1-} == --profile ]]; then
  profile=$2
  shift 2
fi

case "$1 $2" in
  "config --services")
    printf 'healthy\nplain\n'
    if [[ $profile == optional ]]; then
      printf 'optional\n'
    fi
    ;;
  "ps --all")
    case "${STATUS_SCENARIO:-healthy}" in
      healthy)
        printf '%s\n' \
          '{"Service":"healthy","State":"running","Health":"healthy"}' \
          '{"Service":"plain","State":"running","Health":""}'
        ;;
      unhealthy)
        printf '%s\n' '[{"Service":"healthy","State":"running","Health":"unhealthy"},{"Service":"plain","State":"running","Health":""}]'
        ;;
      restarting)
        printf '%s\n' '[{"Service":"healthy","State":"restarting","Health":""},{"Service":"plain","State":"running","Health":""}]'
        ;;
      exited)
        printf '%s\n' '[{"Service":"healthy","State":"exited","Health":""},{"Service":"plain","State":"running","Health":""}]'
        ;;
      missing)
        printf '%s\n' '[{"Service":"plain","State":"running","Health":""}]'
        ;;
      empty)
        ;;
      optional)
        printf '%s\n' '[{"Service":"healthy","State":"running","Health":"healthy"},{"Service":"plain","State":"running","Health":""},{"Service":"optional","State":"running","Health":""}]'
        ;;
      malformed)
        printf '%s\n' '[{"Service":"healthy","State":"running","Health":"healthy"},{"Service":"healthy","State":"running","Health":{}},{"Service":"plain","State":"running","Health":""}]'
        ;;
      unknown_health)
        printf '%s\n' '[{"Service":"healthy","State":"running","Health":"garbage"},{"Service":"plain","State":"running","Health":""}]'
        ;;
      starting)
        printf '%s\n' '[{"Service":"healthy","State":"running","Health":"starting"},{"Service":"plain","State":"running","Health":""}]'
        ;;
      multi_unhealthy)
        printf '%s\n' '[{"Service":"healthy","State":"running","Health":"healthy"},{"Service":"healthy","State":"running","Health":"unhealthy"},{"Service":"plain","State":"running","Health":""}]'
        ;;
      multi_exited)
        printf '%s\n' '[{"Service":"healthy","State":"running","Health":"healthy"},{"Service":"healthy","State":"exited","Health":""},{"Service":"plain","State":"running","Health":""}]'
        ;;
    esac
    ;;
  *)
    printf 'unexpected docker arguments: %s\n' "$*" >&2
    exit 98
    ;;
esac
EOF
chmod +x "$test_root/bin/docker"

failures=0

run_status() {
  local scenario=$1
  shift
  set +e
  output=$(PATH="$test_root/bin:$PATH" STATUS_SCENARIO="$scenario" bash "$repo_root/scripts/status.sh" "$@" 2>&1)
  exit_code=$?
  set -e
}

assert_status() {
  local expected=$1
  if [[ $exit_code -ne $expected ]]; then
    printf 'not ok - expected exit %s, got %s: %s\n' "$expected" "$exit_code" "$output"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local expected=$1
  if [[ $output != *"$expected"* ]]; then
    printf 'not ok - output missing %q: %s\n' "$expected" "$output"
    failures=$((failures + 1))
  fi
}

assert_not_contains() {
  local unexpected=$1
  if [[ $output == *"$unexpected"* ]]; then
    printf 'not ok - output unexpectedly contains %q: %s\n' "$unexpected" "$output"
    failures=$((failures + 1))
  fi
}

set -e

run_status healthy analytics
assert_status 0
assert_contains 'PASS analytics healthy running healthy'
assert_contains 'PASS analytics plain running no-healthcheck'

run_status healthy ai/ai-memory
assert_status 0
assert_contains 'PASS ai/ai-memory healthy running healthy'
assert_contains 'PASS ai/ai-memory plain running no-healthcheck'

run_status unhealthy analytics
assert_status 1
assert_contains 'FAIL analytics healthy running unhealthy'

run_status restarting analytics
assert_status 1
assert_contains 'FAIL analytics healthy restarting'

run_status exited analytics
assert_status 1
assert_contains 'FAIL analytics healthy exited'

run_status missing analytics
assert_status 1
assert_contains 'FAIL analytics healthy missing'

run_status empty analytics
assert_status 1
assert_contains 'FAIL analytics healthy missing'
assert_contains 'FAIL analytics plain missing'

run_status optional analytics
assert_status 0
assert_not_contains ' optional '

run_status optional --profile optional analytics
assert_status 0
assert_contains 'PASS analytics optional running no-healthcheck'

run_status malformed analytics
assert_status 1
assert_contains 'FAIL analytics invalid-status-json'

run_status unknown_health analytics
assert_status 1
assert_contains 'FAIL analytics invalid-status-json'
assert_not_contains 'PASS analytics'

run_status starting analytics
assert_status 0
assert_contains 'PASS analytics healthy running starting'

run_status multi_unhealthy analytics
assert_status 1
assert_contains 'FAIL analytics healthy running unhealthy'

run_status multi_exited analytics
assert_status 1
assert_contains 'FAIL analytics healthy exited'

run_status healthy --all
assert_status 0
stack_count=$(printf '%s\n' "$output" | awk '$3 == "healthy" { print $2 }' | sort -u | wc -l)
if [[ $stack_count -ne 11 ]]; then
  printf 'not ok - expected 11 stacks from --all, got %s: %s\n' "$stack_count" "$output"
  failures=$((failures + 1))
fi

run_status healthy not-a-stack
assert_status 2
assert_contains 'Unknown stack: not-a-stack'

run_status healthy ../homelab-plan011/analytics
assert_status 2
assert_contains 'Unknown stack: ../homelab-plan011/analytics'

run_status healthy
assert_status 2
assert_contains 'Usage:'

if [[ $failures -ne 0 ]]; then
  printf '%s test assertion(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'All status tests passed\n'
