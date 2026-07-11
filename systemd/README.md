# systemd units

One unit per Docker Compose stack, matching the directory layout under this repo (including `management.service` for [`management/`](../management/README.md), `dns.service` for [`dns/`](../dns/README.md), and `notifications.service` for [`notifications/`](../notifications/README.md)). Each unit runs `docker compose up -d` as a oneshot service and remains active after Compose finishes, so successful activation means detached container startup completed. A 15-minute startup timeout allows initial image pulls and container recreation to finish without permitting an indefinitely stuck Compose process. Container health and restart behavior remain Docker/Compose responsibilities.

Installation, enable order, and why **`proxy.service` must start last** (external Docker networks) are documented in the root **[README.md](../README.md#boot-with-systemd-optional)**.
