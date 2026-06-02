# CloudBase Lab — Operations

Day-to-day operational runbook for the local Docker Compose stack. All commands
are run from the project root (`~/projects/cloudbase-lab`) unless noted.

> These are **safe, local** operations. None of them expose a service to the
> internet or print secrets. Commands that touch real passwords (e.g. backups
> with `--include-env`) are flagged.

---

## Start the stack

```bash
docker compose up -d
```

Starts (or recreates) all services in the background. Re-run it after editing
`docker-compose.yml` or `.env` to apply changes. To start a single service:

```bash
docker compose up -d vaultwarden
```

## Stop the stack

```bash
# Stop containers, keep them and their volumes
docker compose stop

# Stop and remove containers (named volumes are preserved)
docker compose down
```

> `docker compose down -v` would also delete the named data volumes
> (Nextcloud, MariaDB, Uptime Kuma, Portainer, Vaultwarden). Do **not** use the
> `-v` flag unless you intend to wipe all data.

## Check running services

```bash
docker compose ps
```

Shows each container, its health status and published ports. For a host-wide
view including non-compose containers:

```bash
docker ps
```

## View logs

```bash
# Follow logs for one service (last 80 lines, then live)
docker compose logs traefik --tail=80
docker compose logs -f vaultwarden

# All services at once
docker compose logs --tail=50
```

## Check Traefik routes

Traefik is the reverse proxy. Inspect its decisions two ways:

```bash
# Router/service discovery and TLS errors show up here
docker compose logs traefik --tail=80
```

The **dashboard** lists all active routers, services and middlewares:

- https://traefik.cloudbase.local/dashboard/

(Requires the local hostname mapping below. The dashboard is served only over
the secure entrypoint on the local hostname.)

## Check local hostnames

The `*.cloudbase.local` hostnames must resolve to `127.0.0.1` on the host. Add
them to `/etc/hosts` (one line is enough):

```
127.0.0.1  homepage.cloudbase.local nextcloud.cloudbase.local adminer.cloudbase.local uptime.cloudbase.local portainer.cloudbase.local vaultwarden.cloudbase.local traefik.cloudbase.local
```

Verify resolution and routing:

```bash
getent hosts homepage.cloudbase.local
# Follow redirects; -k accepts the local self-signed cert
curl -kIL https://homepage.cloudbase.local
```

The local certificate is self-signed, so browsers will warn — that is expected
for LAN/loopback use.

## Check Uptime Kuma

Self-hosted uptime monitoring.

- UI: http://localhost:8083 or https://uptime.cloudbase.local
- Health: `docker compose ps uptime-kuma` (should report `healthy`)

See [monitoring.md](monitoring.md) for the recommended monitor list. Monitors
are configured **in the browser** — do not script logins or store its
credentials in this repo.

## Check Portainer

Docker management web UI.

- UI: http://localhost:8084 or https://portainer.cloudbase.local
- On first start, create the admin account within a few minutes; if the setup
  window closes, restart it: `docker compose restart portainer`

Keep it local-only and protect the admin account — Portainer has read-write
access to the Docker socket.

## Check Vaultwarden

Local-only password manager.

- UI: https://vaultwarden.cloudbase.local or http://localhost:8085
  (bound to `127.0.0.1` only)
- Health: `docker compose ps vaultwarden`

See the README "Password manager (Vaultwarden)" section for creating the first
account safely and for the security model. Vaultwarden is intentionally
**excluded** from Watchtower auto-updates.

## Run backup manually

```bash
# Standard backup (does NOT include .env)
./scripts/backup.sh

# Keep backups for 14 days instead of the default 7
./scripts/backup.sh --retention-days 14

# Include .env — contains REAL passwords, store the archive securely
./scripts/backup.sh --include-env
```

The backup dumps MariaDB, archives the Nextcloud volume and copies the project
files into `backups/YYYY-MM-DD_HH-MM-SS/`. The stack must be running.

## Check backup timer

The backup runs automatically via a **user-scoped** systemd timer (no root).

```bash
# Is the timer scheduled? When does it next fire?
systemctl --user list-timers cloudbase-backup.timer

# Status and last result of the service it triggers
systemctl --user status cloudbase-backup.service

# Logs of the most recent run
journalctl --user -u cloudbase-backup.service --no-pager -n 50
```

## Enable backup timer

```bash
# Install the unit files (one time) if not already present
mkdir -p ~/.config/systemd/user
cp systemd/cloudbase-backup.service systemd/cloudbase-backup.timer ~/.config/systemd/user/
systemctl --user daemon-reload

# Enable and start the timer (daily at 03:00)
systemctl --user enable --now cloudbase-backup.timer

# Optional: let user timers run while you are logged out
sudo loginctl enable-linger "$USER"
```

## Disable backup timer

```bash
systemctl --user disable --now cloudbase-backup.timer
```

## Restore notes location

Restore is a manual, deliberate procedure. The step-by-step notes live at:

- [`scripts/restore-notes.md`](../scripts/restore-notes.md)

## Verify a backup (restore test)

Check that the latest backup is intact and restorable — read-only, never touches
production data or volumes:

```bash
./scripts/verify-backup.sh            # verify the latest backup
./scripts/verify-backup.sh backups/2026-05-30_21-58-00   # a specific one
```

The full procedure (gzip/tar integrity, safe MariaDB and Nextcloud validation,
temp-folder extraction, cleanup, and a future isolated-restore drill) is
documented in [`restore-test.md`](restore-test.md).

## Update strategy with Watchtower

Watchtower auto-updates **only** services that opt in with the label
`com.centurylinklabs.watchtower.enable=true`. Today that is **Homepage** and
**Adminer** (stateless). The check runs daily at **04:00**, just after the
03:00 backup, so updates happen against a fresh backup.

Critical/stateful services — **Nextcloud, MariaDB, Redis, Traefik, Vaultwarden,
Portainer, Uptime Kuma** — are **not** auto-updated and must be updated
manually and tested:

```bash
# Inspect what Watchtower is doing
docker compose logs -f watchtower

# Manually update a critical service (example: pin the new tag in
# docker-compose.yml first, take a backup, then:)
./scripts/backup.sh
docker compose pull nextcloud
docker compose up -d nextcloud
# For Nextcloud, run the upgrade step afterwards:
docker compose exec --user www-data nextcloud php occ upgrade
```

See the README "Automatic updates (Watchtower)" section for the full opt-in
table and rationale.

## Security notes

- **Never commit `.env`** — it holds real passwords and is git-ignored.
- **Keep ports local.** Vaultwarden is bound to `127.0.0.1`; other host ports
  are for local access only. Do not bind services to `0.0.0.0` on an untrusted
  network without a firewall.
- **Vaultwarden signups stay closed** (`VAULTWARDEN_SIGNUPS_ALLOWED=false`)
  except for the few minutes needed to register the first account.
- **The Vaultwarden `/admin` panel stays disabled** unless you set a
  self-generated Argon2 `ADMIN_TOKEN`. Never commit a real token.
- **Self-signed TLS is for local use only.** Enable Let's Encrypt only with a
  real, publicly resolvable domain before exposing anything.
- **Back up before updating** anything stateful, and test after.
- **Docker socket access:** Traefik mounts it read-only; Portainer and
  Watchtower need read-write. Keep all three local-only.
