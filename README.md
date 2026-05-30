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

## Backup-Idee

Die wichtigen Daten liegen in zwei benannten Docker Volumes:
- `cloudbase_nextcloud_data` — Nextcloud-Dateien und Konfiguration
- `cloudbase_mariadb_data`   — Datenbankdaten

### Einfaches Volume-Backup

```bash
# Nextcloud-Daten sichern
docker run --rm \
  -v cloudbase_nextcloud_data:/data:ro \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/nextcloud_$(date +%Y%m%d).tar.gz /data

# MariaDB-Daten sichern
docker run --rm \
  -v cloudbase_mariadb_data:/data:ro \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/mariadb_$(date +%Y%m%d).tar.gz /data
```

### Datenbank-Dump (empfohlen)

```bash
docker exec cloudbase-mariadb \
  mysqldump -u root -p"${DB_ROOT_PASSWORD}" --all-databases \
  > backups/db_dump_$(date +%Y%m%d).sql
```

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
