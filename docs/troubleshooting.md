# CloudBase Lab — Troubleshooting

Common problems, what causes them and how to fix them. For day-to-day commands
see [`operations.md`](operations.md).

## Ports 80/443 already in use

Traefik fails to start with a "port is already allocated" / "address already in
use" error.

- Find the conflicting process: `sudo ss -tlnp | grep -E ':80|:443'`
- Either stop that service, or change `HTTP_PORT` / `HTTPS_PORT` in `.env`
  (e.g. `8880`/`8443`) and use `https://nextcloud.cloudbase.local:8443`.

## `*.cloudbase.local` does not resolve

The browser shows "server not found".

- The hostnames are not real DNS — they must be mapped in your hosts file
  (`/etc/hosts`). See the README section "Reverse proxy (Traefik)".
- Verify with: `getent hosts nextcloud.cloudbase.local` → should print `127.0.0.1`.

## Browser shows a certificate warning

Expected. No real domain is configured, so Traefik serves its built-in
**self-signed** certificate. Accept the warning for local use. A trusted
certificate (Let's Encrypt) requires a real, publicly resolvable domain — see
the README notes.

## Nextcloud: "Access through untrusted domain"

The hostname you used is not in Nextcloud's trusted domains (this can happen on
an install that predates the Traefik setup):

```bash
docker compose exec --user www-data nextcloud \
  php occ config:system:set trusted_domains 1 --value=nextcloud.cloudbase.local
```

## Nextcloud is slow to come up / MariaDB shows "unhealthy" at first

MariaDB's healthcheck has a 30 s `start_period`; Nextcloud waits for it via
`depends_on: condition: service_healthy`. On the very first start (database
initialisation) this can take a minute. Check progress with:

```bash
docker compose ps
docker compose logs -f mariadb
```

If MariaDB stays unhealthy, the most common cause is a changed `DB_*` password
in `.env` that no longer matches the initialised volume — the credentials are
baked into `cloudbase_mariadb_data` on first init.

## Portainer: "initial setup timed out"

Portainer disables account creation if no admin account is created within a few
minutes of container start. Restart it and register right away:

```bash
docker compose restart portainer
```

## Uptime Kuma: HTTPS monitors fail

- The `https://*.cloudbase.local` monitors need the `extra_hosts` mapping in
  `docker-compose.yml` (already configured) **and** "Ignore TLS error" enabled
  on each monitor (the cert is self-signed).
- Internal `http://cloudbase-<name>` monitors need no TLS settings at all —
  prefer them when in doubt. See [`monitoring.md`](monitoring.md).

## Watchtower crash-loops with "client version 1.25 is too old"

The published image ships an old Docker client. The compose file already pins
`DOCKER_API_VERSION=1.44` — if you removed it, put it back.

## Backup script fails with a Docker permission error

The script talks to Docker as your user. Make sure your user is in the `docker`
group (`groups $USER`), then log out/in. For the systemd timer, also check:

```bash
journalctl --user -u cloudbase-backup.service -n 50
```

## A service is up but unreachable through Traefik (404)

- The router labels are per-service in `docker-compose.yml` — check them with
  the Traefik dashboard at `https://traefik.cloudbase.local` (HTTP routers view).
- Traefik only routes containers with `traefik.enable=true` on the
  `cloudbase_network` — verify with `docker inspect <container> | grep -A5 Networks`.

## Start fresh (destructive)

Only if you accept losing data — this deletes the named volumes:

```bash
docker compose down -v   # removes containers AND volumes
```

Take a backup first (`./scripts/backup.sh`) and confirm it with
`./scripts/verify-backup.sh`.
