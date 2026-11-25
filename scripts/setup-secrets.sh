#!/usr/bin/env bash
#
# Create/update Google Secret Manager secrets from a LOCAL, UNTRACKED env file
# and grant the runtime service account read access.
#
# This script never contains or commits secret VALUES. You point it at a file
# that lives only on your machine (e.g. ~/rami-secrets.env, git-ignored), and it
# pushes each line into Secret Manager as a new version. The repo only ever
# knows secret NAMES (see env/backend.env.example).
#
# Secret file format (KEY=VALUE per line, # comments allowed):
#   DATABASE_URL=postgresql://...
#   JWT_ACCESS_SECRET=...
#   PAYMENT_MOCK_WEBHOOK_SECRET=...
#
# Usage:
#   PROJECT_ID=rami-broast \
#   RUNTIME_SA=rami-api@rami-broast.iam.gserviceaccount.com \
#   ./scripts/setup-secrets.sh ~/rami-secrets.env

set -euo pipefail

: "${PROJECT_ID:?set PROJECT_ID}"
SECRET_FILE="${1:?usage: setup-secrets.sh <local-env-file>}"
RUNTIME_SA="${RUNTIME_SA:-}"

if [ ! -f "$SECRET_FILE" ]; then
  echo "ERROR: secret file not found: $SECRET_FILE" >&2
  exit 1
fi

# Refuse to read a file that is tracked by git — a guard against committing secrets.
if git -C "$(dirname "$SECRET_FILE")" ls-files --error-unmatch "$(basename "$SECRET_FILE")" >/dev/null 2>&1; then
  echo "ERROR: $SECRET_FILE is tracked by git. Secret values must never be committed." >&2
  exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
  # Skip blanks and comments.
  case "$line" in ''|\#*) continue ;; esac
  key="${line%%=*}"
  value="${line#*=}"
  [ -n "$key" ] || continue

  if gcloud secrets describe "$key" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "Updating $key (new version)"
  else
    echo "Creating $key"
    gcloud secrets create "$key" --project "$PROJECT_ID" --replication-policy automatic
  fi
  printf '%s' "$value" | gcloud secrets versions add "$key" --project "$PROJECT_ID" --data-file=-

  if [ -n "$RUNTIME_SA" ]; then
    gcloud secrets add-iam-policy-binding "$key" \
      --project "$PROJECT_ID" \
      --member "serviceAccount:${RUNTIME_SA}" \
      --role roles/secretmanager.secretAccessor >/dev/null
  fi
done < "$SECRET_FILE"

echo "Done. Secret NAMES now in Secret Manager; values never left your machine + GCP."
echo "Inventory (names + versions, no values):"
gcloud secrets list --project "$PROJECT_ID" --format='table(name, createTime)'
