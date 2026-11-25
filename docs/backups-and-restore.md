# Backups & restore

Two layers, kept together on purpose:

1. **Cloud SQL automated backups + point-in-time recovery (PITR)** — the fast,
   managed recovery path. Configured once on the instance.
2. **Logical `pg_dump` backups** (`scripts/db-backup.sh`) — portable, offsite in
   GCS, and the layer we can *rehearse a restore from* without touching the live
   instance. This is what makes "tested restore" real.

No secrets live in this repo. Both layers reference the database by connection
string / instance name supplied at run time.

---

## 1. Cloud SQL managed backups (set once)

```bash
gcloud sql instances patch rami-pg \
  --project "$PROJECT_ID" \
  --backup-start-time=02:00 \
  --enable-point-in-time-recovery \
  --retained-backups-count=30 \
  --retained-transaction-log-days=7
```

- Daily automated backup at 02:00 UTC, 30 kept.
- PITR lets you recover to any second within the last 7 days (WAL retention).
- Managed restore (clones to a new instance — never in place):

  ```bash
  gcloud sql instances clone rami-pg rami-pg-restore \
    --point-in-time "2026-08-23T02:15:00Z"
  ```

## 2. Logical backups (offsite, portable)

Run from a Cloud Run Job or the Cloud SQL Auth Proxy. `DATABASE_URL` comes from
Secret Manager; `BACKUP_GCS_BUCKET` is a plain var.

```bash
DATABASE_URL="$(gcloud secrets versions access latest --secret=DATABASE_URL)" \
BACKUP_GCS_BUCKET="gs://rami-db-backups" \
./scripts/db-backup.sh
```

Schedule daily with Cloud Scheduler → Cloud Run Job. Apply a **bucket lifecycle
+ retention (WORM) policy** so backups can't be deleted early:

```bash
gsutil retention set 35d gs://rami-db-backups
gsutil lifecycle set docs/gcs-backup-lifecycle.json gs://rami-db-backups  # delete > 90d
```

---

## Restore rehearsal (run monthly — this is the part that must be tested)

A backup you have never restored is not a backup. Restore the latest dump into a
throwaway database and check it, **never** into production:

```bash
# 1. Fresh empty target (a scratch Cloud SQL DB, or local Postgres).
createdb rami_restore_rehearsal

# 2. Restore the latest offsite dump into it.
RESTORE_DATABASE_URL="postgresql://.../rami_restore_rehearsal" \
  ./scripts/db-restore.sh gs://rami-db-backups/rami-<latest>.dump

# 3. Sanity-check: row counts and a spot query.
psql "$RESTORE_DATABASE_URL" -c 'SELECT count(*) FROM "Order";'
psql "$RESTORE_DATABASE_URL" -c 'SELECT count(*) FROM "Delivery";'

# 4. Drop the rehearsal DB.
dropdb rami_restore_rehearsal
```

`db-restore.sh` uses `--single-transaction`, so a failed restore leaves no
partial database, and `--clean --if-exists`, so re-running is idempotent. It
refuses to run without `RESTORE_DATABASE_URL` (a distinct variable from
`DATABASE_URL`) so a rehearsal can never default onto production.

**This roundtrip is verified:** `db-backup.sh` → fresh DB → `db-restore.sh`
preserves row counts exactly (validated against a seeded database during
development).

Record each rehearsal (date, dump restored, row counts, who) in the ops log.

---

## What is NOT backed up here

- **Object storage** (proof-of-delivery photos/signatures, once provisioned) —
  enable GCS bucket versioning + a retention policy separately.
- **Secrets** — Secret Manager versions are retained by GCP; export the *names*
  (never values) with `docs/secrets.md`'s inventory step.
