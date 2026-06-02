#!/usr/bin/env bash
# ============================================================
#  CloudBase Lab — Isolated Restore Drill
#
#  Proves that the latest backup can actually be RESTORED into a
#  throwaway, fully isolated test environment — without ever
#  touching production volumes, containers, networks or backups.
#
#  This goes one step further than scripts/verify-backup.sh:
#  verify-backup.sh only checks integrity (gzip -t, tar listing);
#  this script genuinely imports the MariaDB dump into a temporary
#  MariaDB container and validates the Nextcloud / project archives.
#
#  Usage:
#    ./scripts/restore-drill.sh                 # drill the latest backup
#    ./scripts/restore-drill.sh <backup-dir>    # drill a specific backup
#
#  Safety guarantees:
#    * Only ever creates resources named *restore-test* / *restore_test*:
#        - container : cloudbase-restore-test-mariadb
#        - volume    : cloudbase_restore_test_mariadb
#        - network   : cloudbase_restore_test_network
#        - tmp dir   : /tmp/cloudbase-restore-test
#    * Never connects to the production MariaDB container.
#    * Never mounts or writes any production volume.
#    * Never deletes backups or production data.
#    * Never prints passwords, secrets or private Nextcloud filenames.
#
#  Exit code: 0 if the drill succeeds, non-zero on any failure.
# ============================================================

set -Eeuo pipefail

# ---- Fixed, clearly-named temporary resources (NEVER production) ----
readonly TMP_DIR="/tmp/cloudbase-restore-test"
readonly TMP_DB_CONTAINER="cloudbase-restore-test-mariadb"
readonly TMP_DB_VOLUME="cloudbase_restore_test_mariadb"
readonly TMP_NETWORK="cloudbase_restore_test_network"
readonly TMP_DB_IMAGE="mariadb:lts"   # match production image for compatibility

# ---- Production resources this script must NEVER touch (guard list) ----
readonly PROD_CONTAINER_DB="cloudbase-mariadb"
readonly PROD_VOLUMES=(
  cloudbase_nextcloud_data
  cloudbase_mariadb_data
  cloudbase_redis_data
  cloudbase_portainer_data
  cloudbase_uptimekuma_data
  cloudbase_vaultwarden_data
)

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

# ============================================================
#  Safety guard — refuse to operate on anything production-named
# ============================================================
assert_temp_name() {
  # $1 = resource name, $2 = human label. Aborts if it is not a
  # clearly-named temporary restore-test resource, or if it matches a
  # known production name. Defence-in-depth for the cleanup routine.
  local name="$1" label="$2" prod
  case "$name" in
    *restore-test*|*restore_test*) : ;;  # acceptable
    *) log_error "Refusing to touch $label '$name' — not a restore-test resource."; exit 1 ;;
  esac
  for prod in "$PROD_CONTAINER_DB" "${PROD_VOLUMES[@]}" cloudbase_network; do
    if [ "$name" = "$prod" ]; then
      log_error "Refusing to touch production resource '$name'."; exit 1
    fi
  done
}

# ============================================================
#  Cleanup (runs on EXIT / ERR / signal) — temp resources only
# ============================================================
CLEANED=false
cleanup() {
  local rc=$?
  $CLEANED && return
  CLEANED=true
  log_section "Cleanup (temporary resources only)"

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$TMP_DB_CONTAINER"; then
    assert_temp_name "$TMP_DB_CONTAINER" "container"
    docker rm -f "$TMP_DB_CONTAINER" >/dev/null 2>&1 && log_ok "removed container $TMP_DB_CONTAINER" \
      || log_warn "could not remove container $TMP_DB_CONTAINER"
  else
    log_info "no temp container to remove"
  fi

  if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -qx "$TMP_DB_VOLUME"; then
    assert_temp_name "$TMP_DB_VOLUME" "volume"
    docker volume rm "$TMP_DB_VOLUME" >/dev/null 2>&1 && log_ok "removed volume $TMP_DB_VOLUME" \
      || log_warn "could not remove volume $TMP_DB_VOLUME (still in use?)"
  else
    log_info "no temp volume to remove"
  fi

  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx "$TMP_NETWORK"; then
    assert_temp_name "$TMP_NETWORK" "network"
    docker network rm "$TMP_NETWORK" >/dev/null 2>&1 && log_ok "removed network $TMP_NETWORK" \
      || log_warn "could not remove network $TMP_NETWORK"
  else
    log_info "no temp network to remove"
  fi

  if [ -d "$TMP_DIR" ]; then
    case "$TMP_DIR" in
      /tmp/cloudbase-restore-test) rm -rf "$TMP_DIR" && log_ok "removed temp dir $TMP_DIR" ;;
      *) log_warn "refusing to remove unexpected temp dir '$TMP_DIR'" ;;
    esac
  else
    log_info "no temp dir to remove"
  fi

  echo
  if [ "$rc" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✔  Restore drill PASSED — backup is restorable.${RESET}"
  else
    echo -e "${RED}${BOLD}✖  Restore drill FAILED (exit $rc). See messages above.${RESET}" >&2
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

# ============================================================
#  STEP 0 — Prerequisites
# ============================================================
log_section "Prerequisites"

if ! command -v docker >/dev/null 2>&1; then
  log_error "docker not found in PATH."; exit 1
fi
if ! docker info >/dev/null 2>&1; then
  log_error "Docker daemon is not running."; exit 1
fi
log_ok "Docker is available"

# Refuse to run if a leftover temp resource from a previous run exists,
# unless we can safely reclaim it (it is, by name, a restore-test resource).
for c in "$TMP_DB_CONTAINER"; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    log_warn "Found leftover temp container '$c' — reclaiming it."
    assert_temp_name "$c" "container"
    docker rm -f "$c" >/dev/null 2>&1 || true
  fi
done

# ============================================================
#  STEP 1 — Locate the backup to drill
# ============================================================
log_section "Locate backup"

if [ $# -ge 1 ]; then
  BACKUP_DIR="$1"
  [ -d "$BACKUP_DIR" ] || { log_error "Backup directory not found: $BACKUP_DIR"; exit 1; }
else
  [ -d "$BACKUPS_ROOT" ] || { log_error "Backups directory not found: $BACKUPS_ROOT"; exit 1; }
  BACKUP_DIR="$(find "$BACKUPS_ROOT" -mindepth 1 -maxdepth 1 -type d \
      -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
      2>/dev/null | sort | tail -n 1)"
  [ -n "$BACKUP_DIR" ] || { log_error "No timestamped backups found in $BACKUPS_ROOT"; exit 1; }
fi
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"   # normalise to absolute path
log_ok "Backup folder: $BACKUP_DIR"

MARIADB_GZ="$BACKUP_DIR/mariadb_dump.sql.gz"
NEXTCLOUD_TGZ="$BACKUP_DIR/nextcloud_data.tar.gz"
PROJECT_FILES="$BACKUP_DIR/project-files"

# ============================================================
#  STEP 2 — Artifact presence + gzip/tar validation (read-only)
# ============================================================
log_section "Artifact presence & integrity"

[ -f "$MARIADB_GZ" ]    || { log_error "missing: mariadb_dump.sql.gz"; exit 1; }
[ -f "$NEXTCLOUD_TGZ" ] || { log_error "missing: nextcloud_data.tar.gz"; exit 1; }
[ -d "$PROJECT_FILES" ] || { log_error "missing: project-files/"; exit 1; }
log_ok "mariadb_dump.sql.gz present  ($(du -h "$MARIADB_GZ" | cut -f1))"
log_ok "nextcloud_data.tar.gz present ($(du -h "$NEXTCLOUD_TGZ" | cut -f1))"
log_ok "project-files/ present"

gzip -t "$MARIADB_GZ"    2>/dev/null && log_ok "gzip OK: mariadb_dump.sql.gz"    || { log_error "gzip CORRUPT: mariadb_dump.sql.gz"; exit 1; }
gzip -t "$NEXTCLOUD_TGZ" 2>/dev/null && log_ok "gzip OK: nextcloud_data.tar.gz" || { log_error "gzip CORRUPT: nextcloud_data.tar.gz"; exit 1; }

# tar structural validation (read-only listing, no extraction)
if tar -tzf "$NEXTCLOUD_TGZ" >/dev/null 2>&1; then
  log_ok "tar OK: nextcloud_data.tar.gz lists cleanly"
else
  log_error "tar CORRUPT: nextcloud_data.tar.gz could not be listed"; exit 1
fi

# ============================================================
#  STEP 3 — Prepare isolated temp workspace
# ============================================================
log_section "Prepare isolated workspace"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
log_ok "temp dir: $TMP_DIR"

# Dedicated throwaway network (isolation demonstration).
if ! docker network ls --format '{{.Name}}' | grep -qx "$TMP_NETWORK"; then
  docker network create "$TMP_NETWORK" >/dev/null
fi
log_ok "temp network: $TMP_NETWORK"

# ============================================================
#  STEP 4 — MariaDB restore drill (temporary container + volume)
# ============================================================
log_section "MariaDB restore drill"

# Random root password for the throwaway DB — generated, never printed,
# never read from production .env.
TMP_ROOT_PW="$(openssl rand -hex 24 2>/dev/null || head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
[ -n "$TMP_ROOT_PW" ] || { log_error "could not generate a temporary password"; exit 1; }

log_info "Starting throwaway MariaDB ($TMP_DB_IMAGE) on isolated network..."
docker run -d \
  --name "$TMP_DB_CONTAINER" \
  --network "$TMP_NETWORK" \
  -e MARIADB_ROOT_PASSWORD="$TMP_ROOT_PW" \
  -v "$TMP_DB_VOLUME":/var/lib/mysql \
  "$TMP_DB_IMAGE" >/dev/null
log_ok "temp container: $TMP_DB_CONTAINER  (temp volume: $TMP_DB_VOLUME)"

# Wait for the temp DB to accept connections (max ~90s).
log_info "Waiting for temporary MariaDB to become ready..."
READY=false
for _ in $(seq 1 45); do
  if docker exec "$TMP_DB_CONTAINER" \
       mariadb-admin ping -uroot -p"$TMP_ROOT_PW" --silent >/dev/null 2>&1; then
    READY=true; break
  fi
  sleep 2
done
$READY || { log_error "temporary MariaDB did not become ready in time"; exit 1; }
log_ok "temporary MariaDB is ready"

# Import the decompressed dump into the TEMP container.
# --force tolerates harmless system-table quirks of an --all-databases dump;
# real success is judged below by checking the restored application data.
log_info "Importing mariadb_dump.sql.gz into the temporary database..."
IMPORT_ERR="$TMP_DIR/mariadb_import.stderr"
if gzip -dc "$MARIADB_GZ" \
     | docker exec -i "$TMP_DB_CONTAINER" mariadb -uroot -p"$TMP_ROOT_PW" --force \
       2>"$IMPORT_ERR"; then
  log_ok "MariaDB dump stream applied"
else
  log_error "MariaDB import stream failed"
  log_info "stderr lines: $(wc -l <"$IMPORT_ERR" 2>/dev/null || echo '?') (not printed — may contain identifiers)"
  exit 1
fi

# Post-import validation — SAFE metadata only (schema names + table counts).
# No row data, no secrets. Application data is any non-system schema.
SYS_SCHEMAS="('mysql','information_schema','performance_schema','sys')"

USER_DB_COUNT="$(docker exec "$TMP_DB_CONTAINER" mariadb -uroot -p"$TMP_ROOT_PW" -N -B \
  -e "SELECT COUNT(DISTINCT table_schema) FROM information_schema.tables WHERE table_schema NOT IN $SYS_SCHEMAS;" 2>/dev/null || echo 0)"
TOTAL_DBS="$(docker exec "$TMP_DB_CONTAINER" mariadb -uroot -p"$TMP_ROOT_PW" -N -B \
  -e "SHOW DATABASES;" 2>/dev/null | grep -c . || echo 0)"

if ! [[ "$USER_DB_COUNT" =~ ^[0-9]+$ ]] || [ "$USER_DB_COUNT" -lt 1 ]; then
  log_error "post-import check failed: no application database/tables were restored"
  exit 1
fi
log_ok "MariaDB import verified: $TOTAL_DBS database(s) total, $USER_DB_COUNT application schema(s) with tables"

log_info "Safe per-schema table counts (names + counts only):"
docker exec "$TMP_DB_CONTAINER" mariadb -uroot -p"$TMP_ROOT_PW" -B \
  -e "SELECT table_schema AS \`schema\`, COUNT(*) AS tables FROM information_schema.tables WHERE table_schema NOT IN $SYS_SCHEMAS GROUP BY table_schema;" 2>/dev/null \
  | sed 's/^/    /' || true

# ============================================================
#  STEP 5 — Nextcloud archive restore drill (read-only listing)
# ============================================================
log_section "Nextcloud archive restore drill"

# The Nextcloud archive can be large, so we validate by a read-only tar
# listing rather than extracting it. We check only KNOWN framework paths;
# we never print private/user filenames.
NC_LIST="$TMP_DIR/nextcloud_listing.txt"
tar -tzf "$NEXTCLOUD_TGZ" 2>/dev/null | sed 's#^\./##' > "$NC_LIST"
NC_COUNT="$(grep -c . "$NC_LIST" || true)"
NC_SIZE="$(du -h "$NEXTCLOUD_TGZ" | cut -f1)"
log_ok "archive is valid: $NC_COUNT entries, approx $NC_SIZE compressed"

NC_MISSING=0
for key in index.php status.php version.php occ config/config.php; do
  if grep -qxF "$key" "$NC_LIST"; then
    log_ok "  required path present: $key"
  else
    log_warn "  required path NOT found: $key"
    NC_MISSING=$((NC_MISSING + 1))
  fi
done
if [ "$NC_MISSING" -gt 0 ]; then
  log_error "Nextcloud archive is missing $NC_MISSING required framework path(s)"
  exit 1
fi
log_ok "all required Nextcloud framework paths found"
# NC_LIST may contain private filenames; remove it now so nothing leaks.
rm -f "$NC_LIST"
log_info "discarded the file listing (private filenames not retained/printed)"

# ============================================================
#  STEP 6 — Project files restore drill (into temp only)
# ============================================================
log_section "Project files restore drill"

# Restore project files into the TEMP dir only — never over the live project.
PF_DEST="$TMP_DIR/project-files"
mkdir -p "$PF_DEST"
cp -a "$PROJECT_FILES/." "$PF_DEST/"
log_ok "project files restored into temp: $PF_DEST"

PF_MISSING=0
for f in docker-compose.yml README.md .env.example scripts/backup.sh; do
  if [ -e "$PF_DEST/$f" ]; then
    log_ok "  present: $f"
  else
    log_warn "  expected file not in backup: $f"
    PF_MISSING=$((PF_MISSING + 1))
  fi
done
if [ "$PF_MISSING" -gt 0 ]; then
  log_warn "$PF_MISSING expected project file(s) absent from this backup"
  # Older backups may not include every script; treat as a warning, not a failure,
  # but require the two essentials below.
fi
for must in docker-compose.yml README.md; do
  [ -e "$PF_DEST/$must" ] || { log_error "essential project file missing from backup: $must"; exit 1; }
done
log_ok "essential project files (docker-compose.yml, README.md) restorable"

# ============================================================
#  SUMMARY
# ============================================================
log_section "Drill summary"
echo -e "  ${BOLD}Backup drilled:${RESET}  $BACKUP_DIR"
echo -e "  ${BOLD}MariaDB:${RESET}         imported OK into temp container ($USER_DB_COUNT app schema(s))"
echo -e "  ${BOLD}Nextcloud:${RESET}       archive valid, framework paths present"
echo -e "  ${BOLD}Project files:${RESET}   restorable into temp"
echo -e "  ${DIM}Temporary resources are removed automatically by the cleanup trap.${RESET}"

# Successful exit triggers the cleanup trap (rc=0).
exit 0
