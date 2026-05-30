#!/usr/bin/env bash
# ============================================================
#  CloudBase Lab — Backup Script
#
#  Usage:
#    ./scripts/backup.sh                 # Standard-Backup (ohne .env)
#    ./scripts/backup.sh --include-env   # Backup inkl. .env (Passwörter!)
#
#  Erstellt ein Backup in: backups/YYYY-MM-DD_HH-MM-SS/
# ============================================================

set -euo pipefail

# ---- Pfade ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_DIR="$PROJECT_DIR/backups/$TIMESTAMP"
ENV_FILE="$PROJECT_DIR/.env"
INCLUDE_ENV=false

# ---- Argumente ----
for arg in "$@"; do
  case $arg in
    --include-env) INCLUDE_ENV=true ;;
    *) echo "Unbekanntes Argument: $arg"; echo "Verwendung: $0 [--include-env]"; exit 1 ;;
  esac
done

# ---- Farben (werden deaktiviert falls kein TTY) ----
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# ---- Hilfsfunktionen ----
log_info()    { echo -e "${CYAN}[INFO]${RESET}   $*"; }
log_ok()      { echo -e "${GREEN}[ OK ]${RESET}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}   $*"; }
log_error()   { echo -e "${RED}[FEHLER]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}┌─ $* ${DIM}$(printf '─%.0s' {1..40})${RESET}"; }
log_done()    { echo -e "${GREEN}${BOLD}✔  $*${RESET}"; }

# ============================================================
#  SCHRITT 1 — Voraussetzungen prüfen
# ============================================================
log_section "Voraussetzungen prüfen"

# Docker läuft?
if ! docker info > /dev/null 2>&1; then
  log_error "Docker läuft nicht. Bitte Docker starten und erneut versuchen."
  exit 1
fi
log_ok "Docker läuft"

# Container aktiv?
for container in cloudbase-mariadb cloudbase-nextcloud; do
  STATUS="$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo 'false')"
  if [ "$STATUS" != "true" ]; then
    log_error "Container '$container' ist nicht aktiv."
    log_error "Bitte zuerst 'docker compose up -d' ausführen."
    exit 1
  fi
  log_ok "Container $container ist aktiv"
done

# .env vorhanden?
if [ ! -f "$ENV_FILE" ]; then
  log_error ".env Datei nicht gefunden: $ENV_FILE"
  log_error "Bitte 'cp .env.example .env' ausführen und Passwörter eintragen."
  exit 1
fi

# .env laden
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a
log_ok ".env geladen"

# ============================================================
#  SCHRITT 2 — Backup-Verzeichnis anlegen
# ============================================================
log_section "Backup-Verzeichnis anlegen"

mkdir -p "$BACKUP_DIR"
log_ok "Verzeichnis erstellt: backups/$TIMESTAMP"

# ============================================================
#  SCHRITT 3 — MariaDB Dump
# ============================================================
log_section "MariaDB Dump"

log_info "Erstelle vollständigen Datenbank-Dump..."

docker exec cloudbase-mariadb \
  mariadb-dump \
    -u root \
    -p"${DB_ROOT_PASSWORD}" \
    --single-transaction \
    --quick \
    --add-drop-database \
    --all-databases \
  > "$BACKUP_DIR/mariadb_dump.sql" 2>/dev/null

gzip "$BACKUP_DIR/mariadb_dump.sql"

DUMP_SIZE="$(du -sh "$BACKUP_DIR/mariadb_dump.sql.gz" | cut -f1)"
log_ok "Datenbank-Dump gespeichert: mariadb_dump.sql.gz  ($DUMP_SIZE)"

# ============================================================
#  SCHRITT 4 — Nextcloud Volume Backup
# ============================================================
log_section "Nextcloud Volume Backup"

log_info "Lese Docker Volume: cloudbase_nextcloud_data ..."
log_info "(Dies kann bei großen Datenmengen einige Minuten dauern)"

docker run --rm \
  -v cloudbase_nextcloud_data:/source:ro \
  -v "$BACKUP_DIR":/backup \
  alpine \
  sh -c "cd /source && tar czf /backup/nextcloud_data.tar.gz . 2>/dev/null"

NC_SIZE="$(du -sh "$BACKUP_DIR/nextcloud_data.tar.gz" | cut -f1)"
log_ok "Nextcloud-Daten gespeichert: nextcloud_data.tar.gz  ($NC_SIZE)"

# ============================================================
#  SCHRITT 5 — Projektdateien sichern
# ============================================================
log_section "Projektdateien sichern"

FILES_DIR="$BACKUP_DIR/project-files"
mkdir -p "$FILES_DIR/homepage"
mkdir -p "$FILES_DIR/scripts"

cp "$PROJECT_DIR/docker-compose.yml"   "$FILES_DIR/"
cp "$PROJECT_DIR/.env.example"         "$FILES_DIR/"
cp "$PROJECT_DIR/README.md"            "$FILES_DIR/"
cp "$PROJECT_DIR/homepage/index.html"  "$FILES_DIR/homepage/"

# scripts/restore-notes.md falls vorhanden
if [ -f "$PROJECT_DIR/scripts/restore-notes.md" ]; then
  cp "$PROJECT_DIR/scripts/restore-notes.md" "$FILES_DIR/scripts/"
fi

log_ok "Kopiert: docker-compose.yml, .env.example, README.md, homepage/index.html"

# ---- .env optional ----
if [ "$INCLUDE_ENV" = true ]; then
  echo ""
  log_warn "╔══════════════════════════════════════════════════════╗"
  log_warn "║  ACHTUNG: .env mit echten Passwörtern wird gesichert ║"
  log_warn "║  → Backup NICHT in Git einchecken oder hochladen!   ║"
  log_warn "╚══════════════════════════════════════════════════════╝"
  echo ""
  cp "$ENV_FILE" "$FILES_DIR/.env"
  log_ok ".env gesichert (enthält Passwörter — sicher aufbewahren!)"
else
  log_info ".env wurde NICHT gesichert (Standardverhalten)."
  log_info "Tipp: Mit --include-env wird sie ebenfalls gesichert."
fi

# ============================================================
#  ZUSAMMENFASSUNG
# ============================================================
log_section "Backup abgeschlossen"

TOTAL_SIZE="$(du -sh "$BACKUP_DIR" | cut -f1)"

echo ""
echo -e "${BOLD}  Speicherort:${RESET}  $BACKUP_DIR"
echo -e "${BOLD}  Gesamt:${RESET}       $TOTAL_SIZE"
echo ""
echo -e "  ${DIM}Enthaltene Dateien:${RESET}"

find "$BACKUP_DIR" -type f | while read -r f; do
  rel="${f#$BACKUP_DIR/}"
  size="$(du -sh "$f" 2>/dev/null | cut -f1)"
  echo -e "  ${GREEN}✔${RESET}  $rel  ${DIM}($size)${RESET}"
done

echo ""
log_done "Backup erfolgreich erstellt."
echo ""
echo -e "  ${DIM}Wiederherstellung: siehe scripts/restore-notes.md${RESET}"
echo ""
