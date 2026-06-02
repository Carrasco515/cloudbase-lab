# CloudBase Lab — Isolated restore drill

A backup you have only *verified* is intact still hasn't proven it can be
**restored**. The restore drill closes that gap: it actually imports the latest
backup into a **throwaway, fully isolated** environment and checks that the data
comes back — without ever touching the production stack.

> ⚠️ **Safety first.** The drill only ever creates resources whose names contain
> `restore-test` / `restore_test`, plus a folder under `/tmp`. It never mounts,
> writes, or deletes a production volume, container, network or backup, and it
> never prints secrets or private Nextcloud filenames.

Run it with:

```bash
./scripts/restore-drill.sh                              # drill the latest backup
./scripts/restore-drill.sh backups/2026-05-30_21-58-00  # drill a specific backup
```

It exits `0` on success and non-zero if any validation fails.

---

## Backup verification vs. restore drill

These are two complementary levels of confidence:

| | [`verify-backup.sh`](../scripts/verify-backup.sh) | [`restore-drill.sh`](../scripts/restore-drill.sh) |
|---|---|---|
| Question answered | "Are the archives intact and readable?" | "Does the backup actually restore?" |
| MariaDB dump | `gzip -t` + checks the `Dump completed` marker | **imported** into a temporary MariaDB container |
| Nextcloud archive | `gzip -t` + read-only `tar` listing | read-only `tar` listing + required framework paths |
| Containers started | none | one **temporary** MariaDB container |
| Speed | seconds | a minute or two (starts a container) |
| Side effects | none (read-only) | temporary container/volume/network, auto-removed |

Run `verify-backup.sh` often (it is cheap); run the restore drill periodically
to prove the dump genuinely reloads.

## What the drill restores

- **MariaDB dump** — decompresses `mariadb_dump.sql.gz` and imports it into a
  fresh, temporary MariaDB container (same image as production, `mariadb:lts`).
  It then validates the result using **safe metadata only**: how many databases
  exist and how many tables each application schema has. No row data is ever
  read or printed.
- **Nextcloud archive** — validates `nextcloud_data.tar.gz` by a read-only `tar`
  listing (the archive is ~250 MB, so it is not extracted) and confirms the
  framework paths `index.php`, `status.php`, `version.php`, `occ` and
  `config/config.php` are present. Private user filenames are never printed; the
  listing is discarded immediately after the check.
- **Project files** — copies `project-files/` into the temp folder and confirms
  `docker-compose.yml`, `README.md`, `.env.example` and `scripts/backup.sh` are
  restorable. Backups taken with the current `backup.sh` include the whole
  `scripts/` directory, so the operational scripts come back too.

## What the drill does **not** do

- It does **not** touch the production MariaDB container (`cloudbase-mariadb`).
- It does **not** mount or write any production volume
  (`cloudbase_nextcloud_data`, `cloudbase_mariadb_data`, `cloudbase_redis_data`,
  `cloudbase_portainer_data`, `cloudbase_uptimekuma_data`,
  `cloudbase_vaultwarden_data`).
- It does **not** extract the Nextcloud archive over the live volume or the
  project directory.
- It does **not** delete or modify any backup.
- It does **not** start, stop or recreate the production stack.
- It does **not** read `.env` or print any password, token or secret.

## Safety guarantees

- `set -Eeuo pipefail` plus an `EXIT`/`INT`/`TERM` cleanup trap, so it fails
  loudly and always tears its temporary resources down.
- A `assert_temp_name` guard refuses to remove anything whose name is not a
  `restore-test` resource, and explicitly refuses the known production names.
- The temporary database uses a **randomly generated** root password that is
  created in memory and never printed — the production `.env` is never read.
- The Nextcloud file listing (which can contain private filenames) is kept only
  in `/tmp` for the duration of the check and deleted right after.

## Temporary resources used

| Resource | Name | Removed by |
|---|---|---|
| Container | `cloudbase-restore-test-mariadb` | cleanup trap |
| Volume | `cloudbase_restore_test_mariadb` | cleanup trap |
| Network | `cloudbase_restore_test_network` | cleanup trap |
| Temp folder | `/tmp/cloudbase-restore-test` | cleanup trap |

## How to run it

```bash
cd ~/projects/cloudbase-lab
chmod +x scripts/restore-drill.sh   # first time only
./scripts/restore-drill.sh
```

Docker must be running. The script pulls `mariadb:lts` if it is not already
present (it usually is, since production uses it).

## How to interpret success

A successful run ends with:

```
✔  Restore drill PASSED — backup is restorable.
```

and, along the way, reports safe metadata such as:

- the **backup folder** used,
- artifact presence and sizes,
- `gzip`/`tar` validation results,
- **MariaDB import verified: N database(s) total, M application schema(s) with tables**
  and a per-schema table count (e.g. `nextcloud → 103 tables`),
- the Nextcloud framework paths found,
- the project files restored into the temp folder,
- a **cleanup** section confirming every temporary resource was removed.

Any failed validation prints a `[FAIL]` line and exits non-zero. A `[WARN]`
does not fail the drill as long as the essentials are present — for example an
**older** backup taken before `backup.sh` began capturing the whole `scripts/`
directory will warn that `scripts/backup.sh` is absent, which is expected.

## How to clean up if interrupted

The cleanup trap runs even on `Ctrl-C`, so interruption normally leaves nothing
behind. If a run was killed hard (e.g. `kill -9`) and you want to be sure,
remove **only** the clearly-named temporary resources:

```bash
docker rm -f cloudbase-restore-test-mariadb 2>/dev/null || true
docker volume rm cloudbase_restore_test_mariadb 2>/dev/null || true
docker network rm cloudbase_restore_test_network 2>/dev/null || true
rm -rf /tmp/cloudbase-restore-test
```

> Never run `docker compose down -v` or remove a `cloudbase_*_data` volume to
> "clean up" — those are production volumes.

## What a future full disaster-recovery test would include

The drill proves the **data** restores. A complete DR exercise would also prove
the **application boots** end to end, on a separate machine:

1. Provision a clean host, install Docker, and clone the repo from Git.
2. Recreate `.env` from your secret store (the backup intentionally excludes it).
3. Bring up an **isolated** copy of the full stack with a distinct
   `COMPOSE_PROJECT_NAME` and distinct volume names so it cannot collide with
   production.
4. Restore the MariaDB dump into the test DB **and** extract
   `nextcloud_data.tar.gz` into the test Nextcloud volume.
5. Run `php occ maintenance:data-fingerprint`, log in through Traefik, and
   confirm files, Vaultwarden and monitoring all come up.
6. Time the whole thing to establish a realistic **RTO**, then tear the test
   stack down with `docker compose -p <test-name> down -v` (safe — it only
   removes the *test* volumes).

See also the read-only checks in [`restore-test.md`](restore-test.md) and the
manual restore steps in [`../scripts/restore-notes.md`](../scripts/restore-notes.md).
