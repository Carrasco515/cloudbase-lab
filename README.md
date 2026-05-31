# CloudBase Lab

A local homelab based on Docker Compose.

## Services

| Service    | URL                       | Description                |
|------------|---------------------------|----------------------------|
| Homepage    | http://localhost:8080     | Landing page / dashboard   |
| Nextcloud   | http://localhost:8081     | Personal cloud             |
| Adminer     | http://localhost:8082     | Database management        |
| Uptime Kuma | http://localhost:8083     | Monitoring / status pages  |
| MariaDB     | internal (port 3306)      | Relational database        |
| Redis       | internal (port 6379)      | In-memory cache            |

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

## Next Steps

- [ ] Set up HTTPS via Traefik or Caddy as a reverse proxy
- [ ] Connect Nextcloud to external storage (NFS / SMB)
- [x] Set up automatic backups (systemd timer, daily at 03:00, with retention)
- [x] Add monitoring with Uptime Kuma
- [ ] Add Portainer for a Docker web GUI
- [ ] Integrate Vaultwarden as a local password manager
- [ ] Set up Watchtower for automatic image updates

---

## Security Notes

- Never commit `.env` to Git (it is listed in `.gitignore`)
- Set the passwords in `.env` before the first start
- Bind ports locally only (no `0.0.0.0` without a firewall)
- For production use: put a reverse proxy with TLS in front
