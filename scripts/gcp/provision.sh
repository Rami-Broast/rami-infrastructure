#!/usr/bin/env bash
#
# Optional, idempotent provisioning of the Rami Broast production Google Cloud
# environment. This runs the same steps narrated in
# docs/gcp-production-setup.md (Steps 5-10). It does NOT deploy the service.
#
# READ THIS BEFORE RUNNING IT — it creates billable resources (chiefly Cloud SQL).
#
# Prerequisites:
#   - You are authenticated: `gcloud auth login` (or run inside Cloud Shell).
#   - You have a billing account id (see `gcloud billing accounts list`).
#   - You have edited the variables below.
#
# Usage:
#   ./provision.sh            # create everything
#   SKIP_SQL=1 ./provision.sh # everything except Cloud SQL (create it later)
#
set -euo pipefail

# ─────────────────────────── EDIT THESE ───────────────────────────
PROJECT_ID="${PROJECT_ID:-rami-broast-prod}"
REGION="${REGION:-me-central2}"           # fallback: europe-west1
BILLING_ACCOUNT="${BILLING_ACCOUNT:?set BILLING_ACCOUNT=0X0X0X-0X0X0X-0X0X0X}"
GITHUB_OWNER="${GITHUB_OWNER:-Rami-Broast}"
GITHUB_REPO="${GITHUB_REPO:-Rami-Broast/rami-backend}"
# ─────────────────── names you can leave as-is ────────────────────
SQL_INSTANCE="${SQL_INSTANCE:-rami-pg}"
SQL_DB="${SQL_DB:-rami}"
SQL_USER="${SQL_USER:-rami_app}"
SQL_TIER="${SQL_TIER:-db-g1-small}"
DEPLOY_SA="${DEPLOY_SA:-gh-deployer}"
POOL="${POOL:-github-pool}"
PROVIDER="${PROVIDER:-github-provider}"
# ───────────────────────────────────────────────────────────────────

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

log "Project: $PROJECT_ID   Region: $REGION"

log "Creating project (ok if it exists)"
gcloud projects create "$PROJECT_ID" --name="Rami Broast (prod)" 2>/dev/null || true
gcloud config set project "$PROJECT_ID"

log "Linking billing"
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"

log "Enabling APIs"
gcloud services enable \
  run.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com compute.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com

if [[ "${SKIP_SQL:-0}" != "1" ]]; then
  if ! gcloud sql instances describe "$SQL_INSTANCE" >/dev/null 2>&1; then
    log "Creating Cloud SQL instance ($SQL_TIER) — this takes a few minutes"
    gcloud sql instances create "$SQL_INSTANCE" \
      --project="$PROJECT_ID" --region="$REGION" \
      --database-version=POSTGRES_16 --tier="$SQL_TIER" \
      --storage-size=10GB --storage-auto-increase --availability-type=ZONAL
  else
    log "Cloud SQL instance already exists — skipping create"
  fi

  log "Setting postgres superuser password"
  gcloud sql users set-password postgres --instance="$SQL_INSTANCE" \
    --password="$(openssl rand -hex 24)"

  gcloud sql databases describe "$SQL_DB" --instance="$SQL_INSTANCE" >/dev/null 2>&1 \
    || gcloud sql databases create "$SQL_DB" --instance="$SQL_INSTANCE"

  if ! gcloud sql users list --instance="$SQL_INSTANCE" --format='value(name)' | grep -qx "$SQL_USER"; then
    APP_PW="$(openssl rand -hex 24)"
    gcloud sql users create "$SQL_USER" --instance="$SQL_INSTANCE" --password="$APP_PW"
  else
    log "App user exists — resetting its password so DATABASE_URL is known"
    APP_PW="$(openssl rand -hex 24)"
    gcloud sql users set-password "$SQL_USER" --instance="$SQL_INSTANCE" --password="$APP_PW"
  fi

  CLOUDSQL_CONN="$(gcloud sql instances describe "$SQL_INSTANCE" --format='value(connectionName)')"
  DATABASE_URL="postgresql://${SQL_USER}:${APP_PW}@localhost/${SQL_DB}?host=/cloudsql/${CLOUDSQL_CONN}"

  log "Storing DATABASE_URL secret"
  if gcloud secrets describe DATABASE_URL >/dev/null 2>&1; then
    printf '%s' "$DATABASE_URL" | gcloud secrets versions add DATABASE_URL --data-file=-
  else
    printf '%s' "$DATABASE_URL" | gcloud secrets create DATABASE_URL --data-file=- --replication-policy=automatic
  fi
else
  log "SKIP_SQL=1 — not creating Cloud SQL. Set DATABASE_URL yourself later."
  CLOUDSQL_CONN="(create Cloud SQL and fill this in)"
fi

log "Storing JWT_ACCESS_SECRET secret (only if absent)"
if ! gcloud secrets describe JWT_ACCESS_SECRET >/dev/null 2>&1; then
  openssl rand -base64 48 | tr -d '\n' | gcloud secrets create JWT_ACCESS_SECRET --data-file=- --replication-policy=automatic
fi

log "Creating deploy service account + roles"
DEPLOY_SA_EMAIL="${DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$DEPLOY_SA_EMAIL" >/dev/null 2>&1 \
  || gcloud iam service-accounts create "$DEPLOY_SA" --display-name="GitHub Actions deployer"

for ROLE in roles/run.admin roles/cloudbuild.builds.editor roles/artifactregistry.admin \
            roles/storage.admin roles/cloudsql.client roles/secretmanager.secretAccessor \
            roles/iam.serviceAccountUser roles/logging.logWriter ; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${DEPLOY_SA_EMAIL}" --role="$ROLE" --condition=None >/dev/null
done

log "Granting runtime (default Compute) SA access to secrets + Cloud SQL"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for ROLE in roles/secretmanager.secretAccessor roles/cloudsql.client ; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${RUNTIME_SA}" --role="$ROLE" --condition=None >/dev/null
done

log "Artifact Registry repo"
gcloud artifacts repositories describe cloud-run-source-deploy --location="$REGION" >/dev/null 2>&1 \
  || gcloud artifacts repositories create cloud-run-source-deploy \
       --repository-format=docker --location="$REGION" --description="Cloud Run source deploys"

log "Workload Identity Federation"
gcloud iam workload-identity-pools describe "$POOL" --location=global >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools create "$POOL" --location=global --display-name="GitHub Actions pool"
POOL_ID="$(gcloud iam workload-identity-pools describe "$POOL" --location=global --format='value(name)')"

gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --location=global --workload-identity-pool="$POOL" >/dev/null 2>&1 \
  || gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
       --location=global --workload-identity-pool="$POOL" --display-name="GitHub provider" \
       --issuer-uri="https://token.actions.githubusercontent.com" \
       --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
       --attribute-condition="assertion.repository_owner=='${GITHUB_OWNER}'"

gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GITHUB_REPO}" >/dev/null

WIF_PROVIDER="$(gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --location=global --workload-identity-pool="$POOL" --format='value(name)')"

cat <<SUMMARY

============================================================
 Done. Put these into GitHub ($GITHUB_REPO):

 Variables:
   GCP_PROJECT_ID    = $PROJECT_ID
   GCP_REGION        = $REGION
   CLOUDSQL_CONN     = $CLOUDSQL_CONN
   PROD_SERVICE_NAME = rami-backend
   PUSH_PROVIDER     = mock
   (leave PAYMENT_GATEWAY and SMS_PROVIDER UNSET — deploy stays blocked by design)

 Secrets:
   GCP_WORKLOAD_IDENTITY_PROVIDER = $WIF_PROVIDER
   GCP_DEPLOY_SA_EMAIL            = $DEPLOY_SA_EMAIL
============================================================
SUMMARY
