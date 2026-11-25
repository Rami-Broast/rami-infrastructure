#!/usr/bin/env bash
#
# Logical backup of the Postgres database with pg_dump (custom format).
#
# Works anywhere pg_dump can reach the database — locally, in a Cloud Run job,
# or from the Cloud SQL Auth Proxy. Contains NO secrets: the connection comes
# from $DATABASE_URL, and an optional GCS upload target from $BACKUP_GCS_BUCKET.
#
# This is the portable, restore-rehearsable layer that sits ALONGSIDE Cloud
# SQL's own automated backups + point-in-time recovery (see
# docs/backups-and-restore.md). Keep both: managed backups for fast recovery,
# logical dumps for portability and a tested restore path.
#
# Usage:
#   DATABASE_URL=postgresql://user:pass@host:5432/db \
#   [BACKUP_DIR=./backups] [BACKUP_GCS_BUCKET=gs://rami-db-backups] \
#   ./scripts/db-backup.sh

set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL (the database to back up)}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BACKUP_DIR}/rami-${STAMP}.dump"

mkdir -p "$BACKUP_DIR"

echo "Backing up to ${OUT} ..."
# --format=custom → compressed, selective restore possible with pg_restore.
# --no-owner/--no-privileges → restore into any role without ownership clashes.
pg_dump "$DATABASE_URL" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file "$OUT"

BYTES="$(wc -c < "$OUT" | tr -d ' ')"
echo "Wrote ${OUT} (${BYTES} bytes)"

if [ -z "${BYTES}" ] || [ "${BYTES}" -lt 1024 ]; then
  echo "ERROR: backup looks too small (${BYTES} bytes) — failing." >&2
  exit 1
fi

if [ -n "${BACKUP_GCS_BUCKET:-}" ]; then
  echo "Uploading to ${BACKUP_GCS_BUCKET}/ ..."
  gsutil cp "$OUT" "${BACKUP_GCS_BUCKET}/"
  echo "Uploaded ${BACKUP_GCS_BUCKET}/$(basename "$OUT")"
fi

echo "Backup complete."
