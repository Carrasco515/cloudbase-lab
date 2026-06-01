# CloudBase Lab

[![CI](https://github.com/Carrasco515/cloudbase-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/Carrasco515/cloudbase-lab/actions/workflows/ci.yml)

A local homelab based on Docker Compose.

## Services

| Service     | URL                       | Description                    |
|-------------|---------------------------|--------------------------------|
| Traefik     | http://localhost (80/443) | Reverse proxy / TLS / dashboard |
| Homepage    | http://localhost:8080     | Landing page / dashboard       |
| Nextcloud   | http://localhost:8081     | Personal cloud                 |
| Adminer     | http://localhost:8082     | Database management            |
| Uptime Kuma | http://localhost:8083     | Monitoring / status pages      |
| Portainer   | http://localhost:8084     | Docker management web UI       |
| Watchtower  | internal (background)     | Image updates (opt-in by label)|
| MariaDB     | internal (port 3306)      | Relational database            |
| Redis       | internal (port 6379)      | In-memory cache                |

Each service is also reachable over HTTPS through Traefik at a local hostname
(`*.cloudbase.local`) — see [Reverse proxy (Traefik)](#reverse-proxy-traefik).
The direct `:808x` ports stay available for convenience.

---

## Requirements

- [Docker](https://docs.docker.com/get-docker/) >= 24
- [Docker Compose](https://docs.docker.com/compose/) >= 2.20 (bundled with Docker Desktop)

---

## Initial Setup

```bash
# 1. Create the .env file
cp .env.example .env

# 2. Set passwords in .env (IMPORTANT!)
nano .env

# 3. Start the stack
docker compose up -d

# 4. Follow the logs
docker compose logs -f
```

---

## Management

### Start
```bash
docker compose up -d
```

### Stop (containers are kept)
```bash
docker compose stop
```

### Stop and remove (volumes are preserved)
```bash
docker compose down
```

### View logs
```bash
# All services
docker compose logs -f

# A single service
docker compose logs -f nextcloud
docker compose logs -f mariadb
docker compose logs -f redis
```

### Check status
```bash
docker compose ps
```

### Restart a container
```bash
docker compose restart nextcloud
```

---

## Reverse proxy (Traefik)

[Traefik](https://traefik.io/traefik/) sits in front of the stack on ports
**80** and **443**. It discovers services automatically through Docker labels
and routes each one to a local hostname over HTTPS. Plain HTTP is redirected to
HTTPS.

| Hostname                    | Service     |
|-----------------------------|-------------|
| `homepage.cloudbase.local`  | Homepage    |
| `nextcloud.cloudbase.local` | Nextcloud   |
| `adminer.cloudbase.local`   | Adminer     |
| `uptime.cloudbase.local`    | Uptime Kuma |
| `portainer.cloudbase.local` | Portainer   |
| `traefik.cloudbase.local`   | Traefik dashboard |

### 1. Map the hostnames to localhost

The `*.cloudbase.local` names only need to resolve to `127.0.0.1`. Add them to
your hosts file (`/etc/hosts` on Linux/macOS, `C:\Windows\System32\drivers\etc\hosts`
on Windows):

```
127.0.0.1  homepage.cloudbase.local nextcloud.cloudbase.local adminer.cloudbase.local uptime.cloudbase.local portainer.cloudbase.local traefik.cloudbase.local
```

### 2. Open a service

Visit e.g. https://nextcloud.cloudbase.local. Because no real domain is
configured yet, Traefik serves its **built-in self-signed certificate**, so the
browser shows a "not secure / untrusted certificate" warning — that is expected
for local development. Accept it to continue. The direct ports (e.g.
http://localhost:8081) keep working without any certificate warning.

### Notes

- **Nothing is exposed to the internet.** Ports 80/443 bind to the local host
  only, and the hostnames resolve to `127.0.0.1`.
- **Let's Encrypt is intentionally not enabled.** A trusted certificate requires
  a real, publicly resolvable domain. Once you have one, set `CLOUDBASE_DOMAIN`
  to it and add a certificate resolver to the Traefik `command:` in
  `docker-compose.yml` (an ACME/TLS-challenge block), then point the routers at
  it. Until then the self-signed cert is the right choice.
- Nextcloud is configured with `TRUSTED_PROXIES` (the pinned `CLOUDBASE_SUBNET`)
  so it honours `X-Forwarded-Proto` and generates correct `https://` URLs behind
  the proxy. For an **existing** install, also add the hostname to the trusted
  domains once:
  ```bash
  docker compose exec --user www-data nextcloud \
    php occ config:system:set trusted_domains 1 --value=nextcloud.cloudbase.local
  ```
- Traefik needs read-only access to the Docker socket for service discovery
  (`/var/run/docker.sock:ro`). This is standard for the Docker provider; keep it
  local-only.

---

## Backup

The project includes a ready-to-use backup script at `scripts/backup.sh`.

### Create a backup

```bash
# Make it executable (one time)
chmod +x scripts/backup.sh

# Standard backup (without .env)
./scripts/backup.sh

# Backup including .env (contains real passwords — store securely!)
./scripts/backup.sh --include-env
```

### Retention

Old backups are pruned automatically after each run. The default is to keep
**7 days**; older timestamped folders are deleted (other files in `backups/`
are left untouched).

```bash
# Keep backups for 14 days instead of 7
./scripts/backup.sh --retention-days 14

# Disable pruning for this run
./scripts/backup.sh --no-prune

# The default can also be set via environment variable
RETENTION_DAYS=30 ./scripts/backup.sh
```

The script automatically creates a timestamped subfolder:

```
backups/
└── 2026-05-30_14-30-00/
    ├── mariadb_dump.sql.gz       ← Database dump (compressed)
    ├── nextcloud_data.tar.gz     ← Nextcloud volume archive
    └── project-files/            ← Important project files
```

### What gets backed up?

| File | Contents |
|---|---|
| `mariadb_dump.sql.gz` | Full MariaDB dump of all databases |
| `nextcloud_data.tar.gz` | Nextcloud volume (files, configuration, apps) |
| `project-files/` | docker-compose.yml, .env.example, README.md, homepage/ |

### Restore

See `scripts/restore-notes.md` for a detailed step-by-step guide.

### Note on volumes

The important data lives in two named Docker volumes:
- `cloudbase_nextcloud_data` — Nextcloud files and configuration
- `cloudbase_mariadb_data`   — Database data (backed up via dump)

### Automated backups (systemd timer)

The `systemd/` folder contains a user-level service and timer that run the
backup **every day at 03:00**. They use `%h` (your home directory) and assume
the repo lives at `~/projects/cloudbase-lab` — adjust the paths in
`cloudbase-backup.service` if it is somewhere else.

```bash
# 1. Install the units (user scope — no root needed)
mkdir -p ~/.config/systemd/user
cp systemd/cloudbase-backup.{service,timer} ~/.config/systemd/user/

# 2. Reload and enable the timer
systemctl --user daemon-reload
systemctl --user enable --now cloudbase-backup.timer

# 3. Make sure backups also run while you are logged out
loginctl enable-linger "$USER"
```

Useful checks:

```bash
systemctl --user list-timers cloudbase-backup.timer   # next run / last run
systemctl --user start cloudbase-backup.service       # run once now
journalctl --user -u cloudbase-backup.service -n 50    # view the last log
```

> The service runs as your user, so backups are owned by you and Docker is
> reached through your account (you must be in the `docker` group). Retention
> applies on every run, so the `backups/` folder stays bounded.

---

## Monitoring

[Uptime Kuma](https://github.com/louislam/uptime-kuma) provides self-hosted
uptime monitoring at http://localhost:8083. On first start it asks you to create
an admin account, then you add monitors yourself.

Because Uptime Kuma runs on the same `cloudbase_network`, it can reach the other
services **by container name** — no host ports needed. Suggested monitors:

| Monitor          | Type | Target                          |
|------------------|------|---------------------------------|
| Homepage         | HTTP | `http://cloudbase-homepage`     |
| Nextcloud        | HTTP | `http://cloudbase-nextcloud/status.php` |
| Adminer          | HTTP | `http://cloudbase-adminer:8080` |
| MariaDB          | TCP  | `cloudbase-mariadb:3306`        |
| Redis            | TCP  | `cloudbase-redis:6379`          |

The monitor configuration is stored in the `cloudbase_uptimekuma_data` volume,
so it survives restarts (and is **not** captured by the project-files backup —
it lives in the Docker volume).

---

## Docker management (Portainer)

[Portainer](https://www.portainer.io/) provides a web UI for managing the Docker
host at http://localhost:8084 (or https://portainer.cloudbase.local via Traefik).
You can inspect containers, view logs, check volumes and networks, and start or
stop services from the browser.

On **first start** Portainer asks you to create an admin account. Do this within
a few minutes of starting the stack — for security, Portainer disables initial
setup if the account is not created shortly after the container comes up. If that
happens, just restart it:

```bash
docker compose restart portainer
```

Then connect it to the **local** Docker environment (the socket is already
mounted), and you will see all `cloudbase-*` containers.

> Portainer needs **read-write** access to the Docker socket
> (`/var/run/docker.sock`) because it manages the host — that is more than
> Traefik's read-only access. Keep it bound to the local host only and protect
> the admin account.

---

## Automatic updates (Watchtower)

[Watchtower](https://containrrr.dev/watchtower/) updates containers when a newer
image is published for the **same tag**. It runs as a background daemon — no port
and no web UI.

### Opt-in strategy (label based)

Watchtower runs with `WATCHTOWER_LABEL_ENABLE=true`, so it **only touches
containers that explicitly opt in** with the label
`com.centurylinklabs.watchtower.enable=true`. Nothing is auto-updated unless you
say so.

Currently enabled (non-critical, stateless services):

| Service   | Auto-update | Reason |
|-----------|-------------|--------|
| Homepage  | ✅ yes      | Stateless nginx, safe to recreate |
| Adminer   | ✅ yes      | Stateless DB UI, safe to recreate |
| Nextcloud | ❌ no       | Stateful app — update manually and run `occ upgrade` |
| MariaDB   | ❌ no       | Database — never auto-restart under load |
| Redis     | ❌ no       | Cache backing Nextcloud sessions/locks |
| Traefik   | ❌ no       | Edge router for the whole stack |
| Portainer / Uptime Kuma | ❌ no | Hold state in volumes — update deliberately |

Because images are pinned to tags (`nextcloud:29`, `mariadb:lts`, …), even an
enabled container only receives patch/minor updates *within* its tag; Watchtower
never jumps to a new major version on its own. After a successful update the old
image is removed (`WATCHTOWER_CLEANUP`).

### Schedule

By default the check runs **every day at 04:00**, just after the 03:00 backup
timer, so updates happen against a fresh backup. The schedule is a 6-field cron
expression (with seconds) and is interpreted in **local time** (the `TZ` set in
`.env`, not UTC). Both are configurable in `.env`:

```bash
# In .env — run at 04:00 daily (default), in local time
WATCHTOWER_SCHEDULE=0 0 4 * * *
# Local timezone the schedule is interpreted in
TZ=Europe/Zurich
```

### Useful commands

```bash
# See what Watchtower is doing
docker compose logs -f watchtower

# Trigger an update check immediately (one-off, then exit).
# --run-once also ignores the label filter, so it checks every container.
docker compose run --rm watchtower --run-once
```

### Enabling updates for another container

To let Watchtower auto-update a service, add this label to it in
`docker-compose.yml` (this is what Homepage and Adminer already have):

```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"
```

Leave the label off (or set it to `false`) to keep a container pinned to its
current image — that is the default for everything else.

> Watchtower needs **read-write** access to the Docker socket (it pulls images
> and recreates containers). Keep it bound to the local host only.

> **Note:** the published `containrrr/watchtower` image ships an old Docker
> client (API 1.25) that modern daemons reject (`client version 1.25 is too
> old`). The compose file pins `DOCKER_API_VERSION=1.44` so the client
> negotiates a supported version instead of crash-looping.

---

## Next Steps

- [x] Set up a Traefik reverse proxy with HTTPS and local hostnames
- [ ] Enable Let's Encrypt once a real public domain is available
- [ ] Connect Nextcloud to external storage (NFS / SMB)
- [x] Set up automatic backups (systemd timer, daily at 03:00, with retention)
- [x] Add monitoring with Uptime Kuma
- [x] Add Portainer for a Docker web GUI
- [ ] Integrate Vaultwarden as a local password manager
- [x] Set up Watchtower for automatic image updates

---

## Continuous Integration (CI)

Every push and pull request to `main` triggers a GitHub Actions workflow
(`.github/workflows/ci.yml`) that validates the project. It runs read-only
checks only — **it never starts the stack, never deploys, and never prints
secrets**:

| Check | What it does |
|---|---|
| Required files | Verifies `docker-compose.yml` and `.env.example` exist |
| Compose config | Runs `docker compose config --quiet` to validate the syntax (using `.env.example` placeholders, so no real secrets are involved) |
| Backup syntax | Runs `bash -n scripts/backup.sh` to catch shell syntax errors |
| Shell lint | Runs `shellcheck` on the scripts (if available on the runner) |

This is **CI only** — there is intentionally no CD (deployment) step yet.

---

## Security Notes

- Never commit `.env` to Git (it is listed in `.gitignore`)
- Set the passwords in `.env` before the first start
- Bind ports locally only (no `0.0.0.0` without a firewall)
- For production use: put a reverse proxy with TLS in front
