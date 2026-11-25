#!/usr/bin/env bash
#
# Apply the Cloud Monitoring uptime check, log-based metric, and alert policies
# from monitoring/*.json. No secrets: it substitutes PROJECT_ID / API_HOST /
# NOTIFICATION_CHANNEL placeholders at apply time.
#
# Prereqs:
#   - gcloud authenticated with monitoring.editor + logging.configWriter
#   - A notification channel already created (email/Slack/PagerDuty). Get its id:
#       gcloud beta monitoring channels list --format='value(name)'
#
# Usage:
#   PROJECT_ID=rami-broast \
#   API_HOST=rami-api-xxxx-ww.a.run.app \
#   NOTIFICATION_CHANNEL=projects/rami-broast/notificationChannels/123 \
#   ./scripts/setup-monitoring.sh

set -euo pipefail

: "${PROJECT_ID:?set PROJECT_ID}"
: "${API_HOST:?set API_HOST (the Cloud Run host, no scheme)}"
: "${NOTIFICATION_CHANNEL:?set NOTIFICATION_CHANNEL (projects/.../notificationChannels/ID)}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

render() {
  sed -e "s|PROJECT_ID|${PROJECT_ID}|g" \
      -e "s|API_HOST|${API_HOST}|g" \
      -e "s|NOTIFICATION_CHANNEL|${NOTIFICATION_CHANNEL}|g" \
      "$1" > "$TMP/$(basename "$1")"
  echo "$TMP/$(basename "$1")"
}

echo "== Log-based metric =="
gcloud logging metrics create rami_payment_webhook_failures \
  --project "$PROJECT_ID" \
  --config-from-file "$(render "$HERE/monitoring/log-metric-payment-failures.json")" \
  || echo "  (exists — update with: gcloud logging metrics update ...)"

echo "== Uptime check =="
gcloud monitoring uptime create \
  --project "$PROJECT_ID" \
  --config-from-file "$(render "$HERE/monitoring/uptime-check.json")" \
  || echo "  (exists or unsupported flag on this gcloud version — see docs/monitoring.md)"

echo "== Alert policies =="
for p in alert-uptime alert-error-rate alert-latency alert-payment-failures; do
  echo "  - $p"
  gcloud alpha monitoring policies create \
    --project "$PROJECT_ID" \
    --policy-from-file "$(render "$HERE/monitoring/$p.json")"
done

echo "Monitoring configured."
