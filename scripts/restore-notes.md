# Restore Notes — CloudBase Lab

Diese Datei erklaert, wie du ein bestehendes Backup grundsaetzlich wiederherstellen kannst.

> **Hinweis:** Diese Anleitung beschreibt manuelle Schritte.
> Lies jeden Schritt sorgfaeltig durch, bevor du ihn ausfuehrst.

---

## Was befindet sich im Backup?

```
backups/YYYY-MM-DD_HH-MM-SS/
├── mariadb_dump.sql.gz       ← Vollstaendiger Datenbank-Dump (komprimiert)
├── nextcloud_data.tar.gz     ← Nextcloud Volume-Inhalt (Dateien + Konfiguration)
└── project-files/
    ├── docker-compose.yml    ← Stack-Definition
    ├── .env.example          ← Passwort-Vorlage (ohne echte Werte)
    ├── README.md             ← Projektdokumentation
    ├── homepage/
    │   └── index.html        ← Dashboard-Startseite
    └── scripts/
        └── restore-notes.md  ← Diese Datei
```

---

## Voraussetzungen

- Docker und Docker Compose sind installiert
- Du befindest dich im Projektordner: `cloudbase-lab/`
- Du hast eine gueltige `.env` Datei mit den Datenbankpasswoertern

---

## Schritt-fuer-Schritt Wiederherstellung

### 1. Stack stoppen und Volumes entfernen

```bash
docker compose down -v
```

> Achtung: Alle aktuellen Daten in den Volumes gehen verloren.

---

### 2. Stack neu starten (leere Volumes anlegen)

```bash
docker compose up -d
```

Warte bis MariaDB healthy ist:

```bash
docker compose ps
```

---

### 3. MariaDB Dump wiederherstellen

```bash
# Dump entpacken
gunzip -k backups/YYYY-MM-DD_HH-MM-SS/mariadb_dump.sql.gz

# Dump in den laufenden Container importieren
docker exec -i cloudbase-mariadb \
  mariadb -u root -p"${DB_ROOT_PASSWORD}" \
  < backups/YYYY-MM-DD_HH-MM-SS/mariadb_dump.sql
```

> Ersetze `YYYY-MM-DD_HH-MM-SS` mit dem tatsaechlichen Backup-Ordnernamen.
> `${DB_ROOT_PASSWORD}` stammt aus deiner `.env` Datei.

---

### 4. Nextcloud Volume wiederherstellen

```bash
# Laufenden Nextcloud Container stoppen
docker compose stop nextcloud

# Volume-Inhalt aus dem Backup einspielen
docker run --rm \
  -v cloudbase_nextcloud_data:/target \
  -v "$(pwd)/backups/YYYY-MM-DD_HH-MM-SS":/backup:ro \
  alpine \
  sh -c "cd /target && tar xzf /backup/nextcloud_data.tar.gz"

# Nextcloud wieder starten
docker compose start nextcloud
```

---

### 5. Nextcloud Cache leeren (empfohlen)

```bash
docker compose exec --user www-data nextcloud php occ maintenance:repair
docker compose exec --user www-data nextcloud php occ files:scan --all
```

---

### 6. Pruefe ob alles funktioniert

```bash
docker compose ps
```

Alle Container sollten `Up` oder `healthy` zeigen.

Oeffne dann http://localhost:8081 und teste den Login.

---

## Haeufige Probleme

| Problem | Loesung |
|---|---|
| Login schlaegt fehl | Nextcloud Admin-Passwort mit `occ user:resetpassword` zuruecksetzen |
| MariaDB Import Fehler | Sicherstellen, dass MariaDB `healthy` ist bevor der Import startet |
| Nextcloud zeigt Fehler | `php occ maintenance:repair` ausfuehren |
| Volume leer nach Restore | Sicherstellen, dass `docker compose down -v` vorher ausgefuehrt wurde |

---

## Wichtige Hinweise

- Backups mit `--include-env` enthalten echte Passwoerter — sicher aufbewahren
- Backups nie in ein oeffentliches Git-Repository einchecken
- Das Verzeichnis `backups/` ist in `.gitignore` eingetragen
- Regelmaessige Backups vor Updates oder groesseren Aenderungen erstellen
