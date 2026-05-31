# Restore Notes — CloudBase Lab

This file explains how to restore an existing backup in general terms.

> **Note:** This guide describes manual steps.
> Read each step carefully before you run it.

---

## What is in the backup?

```
backups/YYYY-MM-DD_HH-MM-SS/
├── mariadb_dump.sql.gz       ← Full database dump (compressed)
├── nextcloud_data.tar.gz     ← Nextcloud volume contents (files + configuration)
└── project-files/
    ├── docker-compose.yml    ← Stack definition
    ├── .env.example          ← Password template (without real values)
    ├── README.md             ← Project documentation
    ├── homepage/
    │   └── index.html        ← Dashboard landing page
    └── scripts/
        └── restore-notes.md  ← This file
```

---

## Requirements

- Docker and Docker Compose are installed
- You are in the project folder: `cloudbase-lab/`
- You have a valid `.env` file with the database passwords

---

## Step-by-step restore

### 1. Stop the stack and remove the volumes

```bash
docker compose down -v
```

> Warning: all current data in the volumes will be lost.

---

### 2. Restart the stack (create empty volumes)

```bash
docker compose up -d
```

Wait until MariaDB is healthy:

```bash
docker compose ps
```

---

### 3. Restore the MariaDB dump

```bash
# Unpack the dump
gunzip -k backups/YYYY-MM-DD_HH-MM-SS/mariadb_dump.sql.gz

# Import the dump into the running container
docker exec -i cloudbase-mariadb \
  mariadb -u root -p"${DB_ROOT_PASSWORD}" \
  < backups/YYYY-MM-DD_HH-MM-SS/mariadb_dump.sql
```

> Replace `YYYY-MM-DD_HH-MM-SS` with the actual backup folder name.
> `${DB_ROOT_PASSWORD}` comes from your `.env` file.

---

### 4. Restore the Nextcloud volume

```bash
# Stop the running Nextcloud container
docker compose stop nextcloud

# Restore the volume contents from the backup
docker run --rm \
  -v cloudbase_nextcloud_data:/target \
  -v "$(pwd)/backups/YYYY-MM-DD_HH-MM-SS":/backup:ro \
  alpine \
  sh -c "cd /target && tar xzf /backup/nextcloud_data.tar.gz"

# Start Nextcloud again
docker compose start nextcloud
```

---

### 5. Clear the Nextcloud cache (recommended)

```bash
docker compose exec --user www-data nextcloud php occ maintenance:repair
docker compose exec --user www-data nextcloud php occ files:scan --all
```

---

### 6. Check that everything works

```bash
docker compose ps
```

All containers should show `Up` or `healthy`.

Then open http://localhost:8081 and test the login.

---

## Common problems

| Problem | Solution |
|---|---|
| Login fails | Reset the Nextcloud admin password with `occ user:resetpassword` |
| MariaDB import error | Make sure MariaDB is `healthy` before starting the import |
| Nextcloud shows errors | Run `php occ maintenance:repair` |
| Volume empty after restore | Make sure `docker compose down -v` was run beforehand |

---

## Important notes

- Backups created with `--include-env` contain real passwords — store them securely
- Never commit backups to a public Git repository
- The `backups/` directory is listed in `.gitignore`
- Create regular backups before updates or larger changes
