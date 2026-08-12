# systemd units

One unit per Docker Compose stack, matching the directory layout under this repo (including `management.service` for [`management/`](../management/README.md), `dns.service` for [`dns/`](../dns/README.md), and `notifications.service` for [`notifications/`](../notifications/README.md)). Each unit runs `docker compose up -d` as a oneshot service and remains active after Compose finishes, so successful activation means detached container startup completed. A 15-minute startup timeout allows initial image pulls and container recreation to finish without permitting an indefinitely stuck Compose process. Container health and restart behavior remain Docker/Compose responsibilities.

`pulsearr.service` starts after `media.service` and `notifications.service`
because its Compose stack imports the Docker networks created by those stacks.

Unit state deliberately does not mirror container state. An active unit means
Compose orchestration succeeded; it does not mean every container is still
running or healthy. Use `bash scripts/status.sh <stack>` from the repository
root, or `bash scripts/status.sh --all`, as the health authority. Optional
Compose services are checked only when their profile is explicit, for example
`bash scripts/status.sh --profile tailscale proxy`.

The units do not use `ExecStartPost` for health assessment. Current services
have different warm-up behavior, so an immediate check or arbitrary sleep
would create brittle unit failures. Docker restart policies continue to own
container recovery, while the status command provides an on-demand, read-only
view.

Installation, enable order, and why **`proxy.service` must start last** (external Docker networks) are documented in the root **[README.md](../README.md#boot-with-systemd-optional)**.
