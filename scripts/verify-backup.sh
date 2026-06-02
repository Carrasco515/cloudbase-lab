#!/usr/bin/env bash
# ============================================================
#  CloudBase Lab — Backup Verification (read-only)
#
#  Performs SAFE, non-destructive integrity checks on a backup
#  created by scripts/backup.sh. It never extracts over real
#  files, never touches Docker volumes, never deletes anything
#  and never prints secrets.
#
#  Usage:
#    ./scripts/verify-backup.sh                 # verify the latest backup
#    ./scripts/verify-backup.sh <backup-dir>    # verify a specific backup
#
#  Exit code: 0 if all checks pass, non-zero otherwise.
# ============================================================

set -euo pipefail

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUPS_ROOT="$PROJECT_DIR/backups"

# ---- Colors (disabled if no TTY) ----
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

log_info()    { echo -e "${CYAN}[INFO]${RESET}   $*"; }
log_ok()      { echo -e "${GREEN}[ OK ]${RESET}   $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}   $*"; }
log_error()   { echo -e "${RED}[FAIL]${RESET}   $*" >&2; }
log_section() { echo -e "\n${BOLD}┌─ $* ${DIM}$(printf '─%.0s' {1..40})${RESET}"; }

FAILURES=0
fail() { log_error "$1"; FAILURES=$((FAILURES + 1)); }

# ============================================================
#  STEP 1 — Locate the backup to verify
# ============================================================
log_section "Locate backup"

if [ $# -ge 1 ]; then
  BACKUP_DIR="$1"
  [ -d "$BACKUP_DIR" ] || { log_error "Backup directory not found: $BACKUP_DIR"; exit 1; }
else
  if [ ! -d "$BACKUPS_ROOT" ]; then
    log_error "Backups directory not found: $BACKUPS_ROOT"
    exit 1
  fi
  # Pick the newest timestamped backup folder (YYYY-MM-DD_HH-MM-SS).
  BACKUP_DIR="$(find "$BACKUPS_ROOT" -mindepth 1 -maxdepth 1 -type d \
      -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
      2>/dev/null | sort | tail -n 1)"
  if [ -z "$BACKUP_DIR" ]; then
    log_error "No timestamped backups found in $BACKUPS_ROOT"
    exit 1
  fi
fi

log_ok "Verifying: $BACKUP_DIR"

# ============================================================
#  STEP 2 — Required files present
# ============================================================
log_section "Required files"

MARIADB_GZ="$BACKUP_DIR/mariadb_dump.sql.gz"
NEXTCLOUD_TGZ="$BACKUP_DIR/nextcloud_data.tar.gz"
PROJECT_FILES="$BACKUP_DIR/project-files"

for f in "$MARIADB_GZ" "$NEXTCLOUD_TGZ"; do
  if [ -f "$f" ]; then
    SIZE="$(du -h "$f" | cut -f1)"
    log_ok "present: $(basename "$f")  (${SIZE})"
  else
    fail "missing: $(basename "$f")"
  fi
done

if [ -d "$PROJECT_FILES" ]; then
  log_ok "present: project-files/"
  for pf in docker-compose.yml .env.example README.md homepage/index.html; do
    if [ -f "$PROJECT_FILES/$pf" ]; then
      log_ok "  project-files/$pf"
    else
      fail "  project-files/$pf is missing"
    fi
  done
else
  fail "missing: project-files/ directory"
fi

# ============================================================
#  STEP 3 — gzip integrity (read-only, no extraction)
# ============================================================
log_section "gzip integrity (gzip -t)"

for f in "$MARIADB_GZ" "$NEXTCLOUD_TGZ"; do
  if [ -f "$f" ]; then
    if gzip -t "$f" 2>/dev/null; then
      log_ok "gzip OK: $(basename "$f")"
    else
      fail "gzip CORRUPT: $(basename "$f")"
    fi
  fi
done

# ============================================================
#  STEP 4 — Archive listing (read-only, no extraction)
# ============================================================
log_section "Archive contents (read-only listing)"

# MariaDB dump: confirm it is non-empty SQL with a completion marker.
# We only inspect harmless metadata — never print data rows.
if [ -f "$MARIADB_GZ" ]; then
  if gzip -dc "$MARIADB_GZ" 2>/dev/null | grep -q 'Dump completed'; then
    log_ok "MariaDB dump has a 'Dump completed' marker (not truncated)"
  else
    log_warn "MariaDB dump has no 'Dump completed' marker — verify the dump finished"
  fi
  TABLES="$(gzip -dc "$MARIADB_GZ" 2>/dev/null | grep -c 'CREATE TABLE' || true)"
  log_info "MariaDB dump: ${TABLES} CREATE TABLE statement(s)"
fi

# Nextcloud archive: list entries (count only) and check a few key paths.
if [ -f "$NEXTCLOUD_TGZ" ]; then
  if NC_LIST="$(tar -tzf "$NEXTCLOUD_TGZ" 2>/dev/null)"; then
    NC_COUNT="$(printf '%s\n' "$NC_LIST" | grep -c . || true)"
    log_ok "Nextcloud archive lists cleanly: ${NC_COUNT} entr(y/ies)"
    NORM="$(printf '%s\n' "$NC_LIST" | sed 's#^\./##')"
    # Use a here-string (not a pipe) so grep -q exiting early on a match cannot
    # SIGPIPE the producer and trip pipefail into a false "not found". -F = the
    # dot in the names is a literal, not a regex wildcard.
    for key in index.php status.php config/config.php; do
      if grep -qxF "$key" <<<"$NORM"; then
        log_ok "  contains $key"
      else
        log_warn "  expected $key not found in archive"
      fi
    done
  else
    fail "Nextcloud archive could not be listed (corrupt tar?)"
  fi
fi

# ============================================================
#  SUMMARY
# ============================================================
log_section "Summary"

if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}✔  All backup verification checks passed.${RESET}"
  echo -e "  ${DIM}Backup: $BACKUP_DIR${RESET}"
  echo -e "  ${DIM}This is a read-only integrity check, not a full restore."
  echo -e "  For a real restore drill see docs/restore-test.md.${RESET}"
  exit 0
else
  echo -e "${RED}${BOLD}✖  ${FAILURES} check(s) failed for $BACKUP_DIR${RESET}" >&2
  exit 1
fi
