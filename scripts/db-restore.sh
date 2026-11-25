#!/usr/bin/env bash
#
# Restore a pg_dump custom-format backup into a target database.
#
# Contains NO secrets. The target comes from $RESTORE_DATABASE_URL — deliberately
# a SEPARATE variable from $DATABASE_URL so a restore can never silently clobber
# production by defaulting to it. The backup path may be a local file or a
# gs:// object (downloaded first).
#
# Usage:
#   RESTORE_DATABASE_URL=postgresql://user:pass@host:5432/restore_target \
#   ./scripts/db-restore.sh ./backups/rami-20260823T120000Z.dump
#   ./scripts/db-restore.sh gs://rami-db-backups/rami-20260823T120000Z.dump
#
# The target database must already exist and be EMPTY (or you must accept the
# --clean drop of matching objects). Restoring over live data is destructive —
# the script requires an explicit confirmation unless CONFIRM=yes is set.

set -euo pipefail

: "${RESTORE_DATABASE_URL:?set RESTORE_DATABASE_URL (the target to restore INTO — never production by default)}"
SRC="${1:?usage: db-restore.sh <backup.dump | gs://bucket/backup.dump>}"

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

LOCAL="$SRC"
if [[ "$SRC" == gs://* ]]; then
  WORK="$(mktemp -d)"
  LOCAL="${WORK}/$(basename "$SRC")"
  echo "Downloading ${SRC} ..."
  gsutil cp "$SRC" "$LOCAL"
fi

if [ ! -f "$LOCAL" ]; then
  echo "ERROR: backup file not found: $LOCAL" >&2
  exit 1
fi

if [ "${CONFIRM:-}" != "yes" ]; then
  echo "About to restore '${LOCAL}' INTO:"
  echo "  ${RESTORE_DATABASE_URL%%\?*}"
  echo "This overwrites matching objects in the target. Type 'yes' to proceed."
  read -r REPLY
  [ "$REPLY" = "yes" ] || { echo "Aborted."; exit 1; }
fi

echo "Restoring ..."
# --clean --if-exists → drop then recreate objects, so a re-restore is idempotent.
# --no-owner/--no-privileges → match the dump flags; restore under any role.
# --single-transaction → all-or-nothing; a failed restore leaves no partial DB.
pg_restore \
  --dbname "$RESTORE_DATABASE_URL" \
  --clean --if-exists \
  --no-owner \
  --no-privileges \
  --single-transaction \
  "$LOCAL"

echo "Restore complete."
