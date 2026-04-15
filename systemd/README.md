# systemd units

One unit per Docker Compose stack, matching the directory layout under this repo (including `dns.service` for [`dns/`](../dns/README.md) and `notifications.service` for [`notifications/`](../notifications/README.md)).

Installation, enable order, and why **`proxy.service` must start last** (external Docker networks) are documented in the root **[README.md](../README.md#boot-with-systemd-optional)**.
