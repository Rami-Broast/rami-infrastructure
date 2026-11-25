#!/usr/bin/env bash
#
# Deploy the backend to Cloud Run. Run from your own gcloud login.
# Secrets must already exist in Secret Manager (see docs/deploy-backend-gcp.md).
# This script contains NO secrets — it only references them by name.
#
# Usage:
#   PROJECT_ID=rami-broast REGION=me-central2 \
#   BACKEND_DIR=../backend CONN=<instance-connection-name> \
#   CLIENT_ORIGINS=https://admin.example.com,https://customer.example.com,https://pos.example.com \
#   ./scripts/deploy-backend-cloudrun.sh

set -euo pipefail

: "${PROJECT_ID:?set PROJECT_ID}"
: "${REGION:?set REGION}"
: "${CONN:?set CONN (PROJECT:REGION:INSTANCE from: gcloud sql instances describe ...)}"
BACKEND_DIR="${BACKEND_DIR:-../backend}"
SERVICE="${SERVICE:-rami-api}"
CLIENT_ORIGINS="${CLIENT_ORIGINS:-}"

echo "Deploying '$SERVICE' from '$BACKEND_DIR' to $PROJECT_ID/$REGION (Cloud SQL: $CONN)"

gcloud run deploy "$SERVICE" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --source "$BACKEND_DIR" \
  --platform managed \
  --add-cloudsql-instances "$CONN" \
  --allow-unauthenticated \
  --port 3000 \
  --set-env-vars "NODE_ENV=production,LOG_LEVEL=info,LOG_PRETTY=false,SWAGGER_ENABLED=false,TRUSTED_PROXY_HOPS=1,PAYMENT_GATEWAY=mock,PAYMENT_SANDBOX=true,SMS_PROVIDER=mock,PUSH_PROVIDER=mock,VAT_STANDARD_RATE=0.15,PRICES_INCLUDE_VAT=true,DELIVERY_FEE_TAXABLE=true,LOYALTY_POINTS_PER_SAR=1" \
  ${CLIENT_ORIGINS:+--set-env-vars "CORS_ALLOWED_ORIGINS=$CLIENT_ORIGINS"} \
  --set-secrets "DATABASE_URL=DATABASE_URL:latest,JWT_ACCESS_SECRET=JWT_ACCESS_SECRET:latest,PAYMENT_MOCK_WEBHOOK_SECRET=PAYMENT_MOCK_WEBHOOK_SECRET:latest"

URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT_ID" --region "$REGION" --format='value(status.url)')
echo
echo "Deployed. API base URL for clients:  ${URL}/api/v1"
