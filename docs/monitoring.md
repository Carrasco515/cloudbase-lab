# CloudBase Lab — Monitoring plan

[Uptime Kuma](https://github.com/louislam/uptime-kuma) provides self-hosted
uptime monitoring at http://localhost:8083 (or https://uptime.cloudbase.local
via Traefik).

> **Set up monitors in the browser.** Do not script the Uptime Kuma login or
> store its credentials in this repo. On first start it asks you to create an
> admin account; everything below is added through its UI.

This document is a **plan** — a recommended set of monitors and the reasoning
behind them. Nothing here is automated.

---

## Recommended HTTPS monitors (full external path)

These check each service exactly the way you reach it in the browser, through
Traefik over HTTPS. They validate routing **and** TLS termination end to end:

| Monitor          | Type  | URL                                              |
|------------------|-------|--------------------------------------------------|
| Homepage         | HTTP(s) | `https://homepage.cloudbase.local`             |
| Nextcloud        | HTTP(s) | `https://nextcloud.cloudbase.local/status.php` |
| Adminer          | HTTP(s) | `https://adminer.cloudbase.local`              |
| Traefik Dashboard| HTTP(s) | `https://traefik.cloudbase.local/dashboard/`   |
| Portainer        | HTTP(s) | `https://portainer.cloudbase.local`            |
| Vaultwarden      | HTTP(s) | `https://vaultwarden.cloudbase.local`          |
| Uptime Kuma      | HTTP(s) | `https://uptime.cloudbase.local`               |

When creating each monitor in Uptime Kuma:

- **Ignore TLS/SSL error:** the local certificate is **self-signed**, so enable
  this option (or import the cert) — otherwise the monitor reports the cert as
  invalid even though the service is up.
- **Hostname resolution:** the monitor runs from **inside** the
  `cloudbase-uptime-kuma` container, which does **not** know the
  `*.cloudbase.local` hostnames by default (those live in the host's
  `/etc/hosts`). For the HTTPS monitors above to resolve, either:
  - add the hostnames to the container — e.g. an `extra_hosts` entry in
    `docker-compose.yml` mapping each `*.cloudbase.local` to the Traefik
    container/gateway IP — or
  - use the internal monitors below, which need no DNS or TLS handling.
- **Expected status:** `200` for most; Nextcloud's `status.php` returns `200`
  with a JSON body, and the Traefik dashboard may require the local hostname.

## Internal monitors (reliable default, no DNS/TLS caveats)

Because Uptime Kuma shares the `cloudbase_network`, it can reach the other
containers **by name** with plain HTTP — no host ports, no hostname mapping and
no self-signed-certificate handling. These are the most robust checks for a
monitor running inside the stack, and are a good complement to the HTTPS checks:

| Monitor   | Type | Target                                  |
|-----------|------|-----------------------------------------|
| Homepage  | HTTP | `http://cloudbase-homepage`             |
| Nextcloud | HTTP | `http://cloudbase-nextcloud/status.php` |
| Adminer   | HTTP | `http://cloudbase-adminer:8080`         |
| Portainer | HTTP | `http://cloudbase-portainer:9000`       |
| Uptime Kuma | HTTP | `http://cloudbase-uptime-kuma:3001`   |

> Use the **HTTPS** monitors to verify the full user-facing path (Traefik +
> TLS), and the **internal** monitors to verify the service itself is alive
> independent of the proxy. Many setups run both.

---

## MariaDB and Redis are not HTTP services

MariaDB and Redis speak their own binary wire protocols — they do **not** serve
HTTP, so an HTTP monitor will always fail against them. Do not point an HTTP
check at `cloudbase-mariadb` or `cloudbase-redis`.

Monitor them instead with one of these approaches (to be added later):

- **TCP port checks** — Uptime Kuma's *TCP Port* monitor type confirms the port
  is open and accepting connections:
  - MariaDB: host `cloudbase-mariadb`, port `3306`
  - Redis: host `cloudbase-redis`, port `6379`

  This proves the port is reachable but **not** that the service is healthy
  (e.g. authentication or replication state).

- **Container healthchecks** — both already have Docker healthchecks defined in
  `docker-compose.yml` (MariaDB: `healthcheck.sh --connect`; Redis:
  `redis-cli ping`). `docker compose ps` shows their `healthy`/`unhealthy`
  state. This is the most accurate liveness signal today.

- **Exporters (recommended for real metrics, later)** — run a Prometheus-style
  exporter alongside each service and scrape/monitor that:
  - MariaDB: `prom/mysqld-exporter`
  - Redis: `oliver006/redis_exporter`

  Exporters expose an HTTP `/metrics` endpoint that *can* be HTTP-monitored, and
  they surface real internal metrics (connections, replication lag, memory,
  hit rate) rather than just port liveness.

---

## Where monitor config is stored

Uptime Kuma keeps its configuration in the `cloudbase_uptimekuma_data` Docker
volume, so monitors survive restarts. That volume is **not** captured by the
project-files backup (which only copies repo files) — back it up separately if
your monitor setup is valuable.
