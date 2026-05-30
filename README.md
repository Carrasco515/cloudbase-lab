# CloudBase Lab

Ein lokales Homelab auf Basis von Docker Compose.

## Services

| Service    | URL                       | Beschreibung               |
|------------|---------------------------|----------------------------|
| Homepage   | http://localhost:8080     | Startseite / Dashboard     |
| Nextcloud  | http://localhost:8081     | Persoenliche Cloud         |
| Adminer    | http://localhost:8082     | Datenbank-Verwaltung       |
| MariaDB    | intern (Port 3306)        | Relationale Datenbank      |
| Redis      | intern (Port 6379)        | In-Memory Cache            |

---

## Voraussetzungen

- [Docker](https://docs.docker.com/get-docker/) >= 24
- [Docker Compose](https://docs.docker.com/compose/) >= 2.20 (integriert in Docker Desktop)

---

## Ersteinrichtung

```bash
# 1. .env Datei erstellen
cp .env.example .env

# 2. Passwörter in .env anpassen (WICHTIG!)
nano .env

# 3. Stack starten
docker compose up -d

# 4. Logs verfolgen
docker compose logs -f
```

---

## Verwaltung

### Starten
```bash
docker compose up -d
```

### Stoppen (Container bleiben erhalten)
```bash
docker compose stop
```

### Stoppen und entfernen (Volumes bleiben erhalten)
```bash
docker compose down
```

### Logs anzeigen
```bash
# Alle Services
docker compose logs -f

# Einzelner Service
docker compose logs -f nextcloud
docker compose logs -f mariadb
docker compose logs -f redis
```

### Status pruefen
```bash
docker compose ps
```

### Container neustarten
```bash
docker compose restart nextcloud
```

---

## Backup

Das Projekt enthaelt ein fertiges Backup-Script unter `scripts/backup.sh`.

### Backup erstellen

```bash
# Ausfuehrbares Recht setzen (einmalig)
chmod +x scripts/backup.sh

# Standard-Backup (ohne .env)
./scripts/backup.sh

# Backup inkl. .env (enthaelt echte Passwoerter — sicher aufbewahren!)
./scripts/backup.sh --include-env
```

Das Script erstellt automatisch einen Unterordner mit Timestamp:

```
backups/
└── 2026-05-30_14-30-00/
    ├── mariadb_dump.sql.gz       ← Datenbank-Dump (komprimiert)
    ├── nextcloud_data.tar.gz     ← Nextcloud Volume-Archiv
    └── project-files/            ← Wichtige Projektdateien
```

### Was wird gesichert?

| Datei | Inhalt |
|---|---|
| `mariadb_dump.sql.gz` | Vollstaendiger MariaDB-Dump aller Datenbanken |
| `nextcloud_data.tar.gz` | Nextcloud Volume (Dateien, Konfiguration, Apps) |
| `project-files/` | docker-compose.yml, .env.example, README.md, homepage/ |

### Wiederherstellung

Siehe `scripts/restore-notes.md` fuer eine ausfuehrliche Schritt-fuer-Schritt Anleitung.

### Hinweis zu Volumes

Die wichtigen Daten liegen in zwei benannten Docker Volumes:
- `cloudbase_nextcloud_data` — Nextcloud-Dateien und Konfiguration
- `cloudbase_mariadb_data`   — Datenbankdaten (via Dump gesichert)

---

## Naechste Schritte

- [ ] HTTPS via Traefik oder Caddy als Reverse Proxy einrichten
- [ ] Nextcloud mit externem Speicher (NFS / SMB) verbinden
- [ ] Automatisches Backup per Cronjob einrichten
- [ ] Monitoring mit Uptime Kuma oder Grafana + Prometheus erganzen
- [ ] Portainer fuer eine Docker-Web-GUI hinzufuegen
- [ ] Vaultwarden als lokalen Passwort-Manager integrieren
- [ ] Watchtower fuer automatische Image-Updates einrichten

---

## Sicherheitshinweise

- `.env` niemals in Git einchecken (ist in `.gitignore` eingetragen)
- Passwörter in `.env` vor dem ersten Start anpassen
- Ports nur lokal binden (kein `0.0.0.0` ohne Firewall)
- Fuer den Produktiveinsatz: Reverse Proxy mit TLS verwenden
