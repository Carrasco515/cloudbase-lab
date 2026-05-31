#!/usr/bin/env bash
# ============================================================
#  CloudBase Lab — Backup Script
#
#  Usage:
#    ./scripts/backup.sh                 # Standard backup (without .env)
#    ./scripts/backup.sh --include-env   # Backup including .env (passwords!)
#
#  Creates a backup in: backups/YYYY-MM-DD_HH-MM-SS/
# ============================================================

set -euo pipefail

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_DIR="$PROJECT_DIR/backups/$TIMESTAMP"
ENV_FILE="$PROJECT_DIR/.env"
INCLUDE_ENV=false

# ---- Arguments ----
for arg in "$@"; do
  case $arg in
    --include-env) INCLUDE_ENV=true ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $0 [--include-env]"; exit 1 ;;
  esac
done

# ---- Colors (disabled if no TTY) ----
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# ---- Helper functions ----
log_info()    { echo -e "${CYAN}[INFO]${RESET}   $*"; }
log_ok()      { echo -e "${GREEN}[ OK ]${RESET}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}   $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}┌─ $* ${DIM}$(printf '─%.0s' {1..40})${RESET}"; }
log_done()    { echo -e "${GREEN}${BOLD}✔  $*${RESET}"; }

# ============================================================
#  STEP 1 — Check prerequisites
# ============================================================
log_section "Check prerequisites"

# Is Docker running?
if ! docker info > /dev/null 2>&1; then
  log_error "Docker is not running. Please start Docker and try again."
  exit 1
fi
log_ok "Docker is running"

# Are the containers active?
for container in cloudbase-mariadb cloudbase-nextcloud; do
  STATUS="$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo 'false')"
  if [ "$STATUS" != "true" ]; then
    log_error "Container '$container' is not active."
    log_error "Please run 'docker compose up -d' first."
    exit 1
  fi
  log_ok "Container $container is active"
done

# Does .env exist?
if [ ! -f "$ENV_FILE" ]; then
  log_error ".env file not found: $ENV_FILE"
  log_error "Please run 'cp .env.example .env' and enter your passwords."
  exit 1
fi

# Load .env
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a
log_ok ".env loaded"

# ============================================================
#  STEP 2 — Create backup directory
# ============================================================
log_section "Create backup directory"

mkdir -p "$BACKUP_DIR"
log_ok "Directory created: backups/$TIMESTAMP"

# ============================================================
#  STEP 3 — MariaDB dump
# ============================================================
log_section "MariaDB dump"

log_info "Creating full database dump..."

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
log_ok "Database dump saved: mariadb_dump.sql.gz  ($DUMP_SIZE)"

# ============================================================
#  STEP 4 — Nextcloud volume backup
# ============================================================
log_section "Nextcloud volume backup"

log_info "Reading Docker volume: cloudbase_nextcloud_data ..."
log_info "(This can take a few minutes for large amounts of data)"

docker run --rm \
  -v cloudbase_nextcloud_data:/source:ro \
  -v "$BACKUP_DIR":/backup \
  alpine \
  sh -c "cd /source && tar czf /backup/nextcloud_data.tar.gz . 2>/dev/null"

NC_SIZE="$(du -sh "$BACKUP_DIR/nextcloud_data.tar.gz" | cut -f1)"
log_ok "Nextcloud data saved: nextcloud_data.tar.gz  ($NC_SIZE)"

# ============================================================
#  STEP 5 — Back up project files
# ============================================================
log_section "Back up project files"

FILES_DIR="$BACKUP_DIR/project-files"
mkdir -p "$FILES_DIR/homepage"
mkdir -p "$FILES_DIR/scripts"

cp "$PROJECT_DIR/docker-compose.yml"   "$FILES_DIR/"
cp "$PROJECT_DIR/.env.example"         "$FILES_DIR/"
cp "$PROJECT_DIR/README.md"            "$FILES_DIR/"
cp "$PROJECT_DIR/homepage/index.html"  "$FILES_DIR/homepage/"

# scripts/restore-notes.md if present
if [ -f "$PROJECT_DIR/scripts/restore-notes.md" ]; then
  cp "$PROJECT_DIR/scripts/restore-notes.md" "$FILES_DIR/scripts/"
fi

log_ok "Copied: docker-compose.yml, .env.example, README.md, homepage/index.html"

# ---- .env optional ----
if [ "$INCLUDE_ENV" = true ]; then
  echo ""
  log_warn "╔══════════════════════════════════════════════════════╗"
  log_warn "║  WARNING: .env with real passwords will be backed up ║"
  log_warn "║  → Do NOT commit or upload this backup to Git!      ║"
  log_warn "╚══════════════════════════════════════════════════════╝"
  echo ""
  cp "$ENV_FILE" "$FILES_DIR/.env"
  log_ok ".env backed up (contains passwords — store securely!)"
else
  log_info ".env was NOT backed up (default behavior)."
  log_info "Tip: use --include-env to back it up as well."
fi

# ============================================================
#  SUMMARY
# ============================================================
log_section "Backup complete"

TOTAL_SIZE="$(du -sh "$BACKUP_DIR" | cut -f1)"

echo ""
echo -e "${BOLD}  Location:${RESET}  $BACKUP_DIR"
echo -e "${BOLD}  Total:${RESET}     $TOTAL_SIZE"
echo ""
echo -e "  ${DIM}Included files:${RESET}"

find "$BACKUP_DIR" -type f | while read -r f; do
  rel="${f#$BACKUP_DIR/}"
  size="$(du -sh "$f" 2>/dev/null | cut -f1)"
  echo -e "  ${GREEN}✔${RESET}  $rel  ${DIM}($size)${RESET}"
done

echo ""
log_done "Backup created successfully."
echo ""
echo -e "  ${DIM}Restore: see scripts/restore-notes.md${RESET}"
echo ""
