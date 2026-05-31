# CloudBase Lab

A local homelab based on Docker Compose.

## Services

| Service    | URL                       | Description                |
|------------|---------------------------|----------------------------|
| Homepage   | http://localhost:8080     | Landing page / dashboard   |
| Nextcloud  | http://localhost:8081     | Personal cloud             |
| Adminer    | http://localhost:8082     | Database management        |
| MariaDB    | internal (port 3306)      | Relational database        |
| Redis      | internal (port 6379)      | In-memory cache            |

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

---

## Next Steps

- [ ] Set up HTTPS via Traefik or Caddy as a reverse proxy
- [ ] Connect Nextcloud to external storage (NFS / SMB)
- [ ] Set up automatic backups via cron job
- [ ] Add monitoring with Uptime Kuma or Grafana + Prometheus
- [ ] Add Portainer for a Docker web GUI
- [ ] Integrate Vaultwarden as a local password manager
- [ ] Set up Watchtower for automatic image updates

---

## Security Notes

- Never commit `.env` to Git (it is listed in `.gitignore`)
- Set the passwords in `.env` before the first start
- Bind ports locally only (no `0.0.0.0` without a firewall)
- For production use: put a reverse proxy with TLS in front
