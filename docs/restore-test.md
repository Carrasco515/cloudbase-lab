# CloudBase Lab — Backup restore testing

A backup you have never tried to restore is only a *hope*, not a backup. This
document describes how to **verify** the backups produced by
[`scripts/backup.sh`](../scripts/backup.sh) without putting any live data at
risk.

> ⚠️ **Safety first.** Everything here is **read-only** or operates in a
> throwaway temporary folder. Never extract a backup over the real project
> directory, and never restore into the live Docker volumes
> (`cloudbase_nextcloud_data`, `cloudbase_mariadb_data`, …). Never delete
> backups.

---

## Purpose of restore testing

- Confirm the archives are **not corrupt** (gzip/tar integrity).
- Confirm the expected **artifacts exist** (DB dump, Nextcloud data, project
  files).
- Confirm the DB dump is **complete** (finished, not truncated) and the
  Nextcloud archive contains the application.
- Build confidence that a real restore *would* succeed — before you ever need
  it in an emergency.

The fastest way to run all of this is the helper script:

```bash
./scripts/verify-backup.sh            # verify the latest backup
./scripts/verify-backup.sh backups/2026-05-30_21-58-00   # a specific one
```

It exits non-zero if anything fails and never writes outside `/tmp` (it does
not write at all) or prints secrets. The manual steps below are what the script
automates, in case you want to do them by hand.

---

## 1. Find the latest backup

```bash
cd ~/projects/cloudbase-lab
ls -1d backups/20*_* | sort | tail -n 1
```

Backups are timestamped folders `backups/YYYY-MM-DD_HH-MM-SS/` containing:

| Artifact | What it is |
|---|---|
| `mariadb_dump.sql.gz` | gzip-compressed `--all-databases` SQL dump |
| `nextcloud_data.tar.gz` | tar.gz of the `cloudbase_nextcloud_data` volume (`/var/www/html`) |
| `project-files/` | copies of `docker-compose.yml`, `.env.example`, `README.md`, `homepage/index.html`, `scripts/restore-notes.md` |

## 2. Verify gzip files (integrity, no extraction)

`gzip -t` decompresses in memory and checks the CRC — it writes nothing:

```bash
B=backups/2026-05-30_21-58-00
gzip -t "$B/mariadb_dump.sql.gz"   && echo "mariadb gzip OK"
gzip -t "$B/nextcloud_data.tar.gz" && echo "nextcloud gzip OK"
```

## 3. Verify tar archives (list, no extraction)

`tar -tzf` lists the archive contents without extracting:

```bash
# Count entries (do not print private filenames)
tar -tzf "$B/nextcloud_data.tar.gz" | wc -l

# Confirm the application is present (safe paths only)
tar -tzf "$B/nextcloud_data.tar.gz" | sed 's#^\./##' \
  | grep -E '^(index\.php|status\.php|config/config\.php)$'
```

## 4. Extract to a temporary folder (never the project dir)

Only ever extract into a throwaway location such as
`/tmp/cloudbase-restore-test`. Extract just the **project files** for a sanity
check — there is no need to unpack the 250 MB+ Nextcloud archive to validate it.

```bash
T=/tmp/cloudbase-restore-test
mkdir -p "$T"
# Project-files are already plain files in the backup — copy, don't extract over anything
cp -r "$B/project-files" "$T/project-files"
ls -R "$T/project-files"
```

> If you ever do extract the tar.gz to inspect it, pass an explicit
> `-C /tmp/cloudbase-restore-test` so it can **only** land in the temp folder:
> `tar -xzf "$B/nextcloud_data.tar.gz" -C /tmp/cloudbase-restore-test/nc`.

## 5. Validate the MariaDB dump safely

Inspect **metadata only** — never print data rows (they may contain personal
data):

```bash
# Harmless header (server version, dump tool) — first comment lines
gzip -dc "$B/mariadb_dump.sql.gz" | grep -m 6 '^--'

# Structural counts only
gzip -dc "$B/mariadb_dump.sql.gz" | grep -c 'CREATE TABLE'      # table count
gzip -dc "$B/mariadb_dump.sql.gz" | grep -c 'Dump completed'    # 1 = not truncated
```

A trailing `-- Dump completed on …` line means `mariadb-dump` finished cleanly.
The expected databases are `mysql` (system) and `nextcloud`.

> **Importing into a real, temporary MariaDB container** is the strongest test,
> but it spins up a container and is out of scope for a read-only check. If you
> want that, do it deliberately in an **isolated** stack (see "Future
> improvement" below) — never import into `cloudbase-mariadb`.

## 6. Validate the Nextcloud data archive safely

```bash
# Total entries
tar -tzf "$B/nextcloud_data.tar.gz" | wc -l

# Top-level application items only (safe — no user data paths)
tar -tzf "$B/nextcloud_data.tar.gz" | sed 's#^\./##' \
  | awk -F/ 'NF<=1 && $1!="" {print $1}' | sort -u

# Counts under data/ and apps/ without listing private filenames
tar -tzf "$B/nextcloud_data.tar.gz" | sed 's#^\./##' | grep -c '^data/'
tar -tzf "$B/nextcloud_data.tar.gz" | sed 's#^\./##' | grep -c '^apps/'
```

Summarize counts and safe sample paths only. **Do not** print the contents of
`data/<user>/files/...` — those are private filenames.

## What NOT to do

- ❌ Do **not** extract a backup over `~/projects/cloudbase-lab` (the real repo).
- ❌ Do **not** restore into the live Docker volumes or run a dump against
  `cloudbase-mariadb`.
- ❌ Do **not** delete or move existing backups.
- ❌ Do **not** print SQL data rows, `.env`, tokens, or private Nextcloud
  filenames.
- ❌ Do **not** use `docker compose down -v` (it would wipe the volumes).

## Clean up the temporary restore test folder

The temp folder only ever holds throwaway copies, so it is safe to remove:

```bash
rm -rf /tmp/cloudbase-restore-test
```

(This path is under `/tmp` and contains no production data — it is the **only**
thing these procedures delete.)

## Future improvement: full restore into an isolated test stack

A read-only check proves the archives are intact; a *full* restore drill proves
they actually boot. To do that safely later, without touching production:

1. Copy the stack into a separate directory and give it its own
   **project name** and **volume names** (e.g. `COMPOSE_PROJECT_NAME=cbtest`,
   distinct `name:` on each volume) so it cannot collide with the live volumes.
2. Use throwaway ports and a throwaway `.env`.
3. Start only `mariadb` + `nextcloud`, then:
   - `gzip -dc mariadb_dump.sql.gz | docker exec -i <test-mariadb> mariadb -uroot -p…`
   - extract `nextcloud_data.tar.gz` into the **test** Nextcloud volume.
4. Open the test Nextcloud, confirm login and files, then tear the test stack
   down with `docker compose -p cbtest down -v` (safe — it only removes the
   *test* volumes).

This is intentionally manual and isolated; automate it only once the volume/
project-name separation is proven to never touch the production stack.
