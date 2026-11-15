#!/bin/sh
# Keep qBittorrent's listen port on the port PIA actually forwarded.
#
# Runs inside the `vpn` container via docker-wireguard-pia's PORT_SCRIPT hook, which fires once
# a port forward succeeds and passes the port as $1. That container shares qBittorrent's network
# namespace, so the WebUI answers on 127.0.0.1 and qBittorrent's `WebUI\LocalHostAuth=false`
# bypasses the password for loopback clients — this script needs no credentials.
#
# Without it, the listen port is whatever was last set in the UI while the forwarded port can
# change on reconnect or on a PIA region fallback, and inbound peers silently stop working.
#
# The work is backgrounded: the hook runs during the VPN's startup sequence and must not block
# it while qBittorrent is still coming up.

set -u

web="http://127.0.0.1:${QBIT_WEBUI_PORT:-8080}"
api="$web/api/v2"

log() { printf 'port-sync: %s\n' "$*"; }

# Port from the hook argument, or from the file the VPN container publishes for other
# consumers when invoked without one (e.g. wired to POST_RECONNECT).
port="${1:-}"
if [ -z "$port" ] && [ -r /pia-shared/port.dat ]; then
  port=$(tr -dc '0-9' < /pia-shared/port.dat)
fi

case "$port" in
  '' | *[!0-9]*)
    log "no usable forwarded port ('${port}'), nothing to do"
    exit 0
    ;;
esac
if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
  log "forwarded port ${port} is outside 1024-65535, nothing to do"
  exit 0
fi

read_port() {
  curl -fsS -m 5 -H "Referer: ${web}/" "$api/app/preferences" 2>/dev/null |
    tr ',' '\n' |
    sed -n 's/^"listen_port":\([0-9]*\)$/\1/p' |
    head -1
}

(
  attempt=1
  max_attempts=15

  while [ "$attempt" -le "$max_attempts" ]; do
    current=$(read_port)

    if [ -z "$current" ]; then
      # qBittorrent not answering yet; retry quietly
      sleep 4
      attempt=$((attempt + 1))
      continue
    fi

    if [ "$current" = "$port" ]; then
      log "listen port already ${port}"
      exit 0
    fi

    if curl -fsS -m 8 -X POST -H "Referer: ${web}/" \
      --data-urlencode "json={\"listen_port\":${port}}" \
      "$api/app/setPreferences" >/dev/null 2>&1; then
      after=$(read_port)
      if [ "$after" = "$port" ]; then
        log "listen port ${current} -> ${port} (PIA forwarded port)"
        exit 0
      fi
      log "setPreferences accepted but the API still reports ${after:-nothing} (attempt ${attempt})"
    else
      log "setPreferences call failed (attempt ${attempt})"
    fi

    sleep 4
    attempt=$((attempt + 1))
  done

  log "gave up after ${max_attempts} attempts: qBittorrent did not accept ${port} on ${web}"
) &

exit 0
