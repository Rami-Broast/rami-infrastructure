# Deploy the backend to Google Cloud (Cloud Run + Cloud SQL)

The backend is a stateless NestJS container. The chosen shape:

- **Cloud Run** runs the container (scales to zero, pay-per-request).
- **Cloud SQL for PostgreSQL** is the managed database.
- **Secret Manager** holds every secret (DB URL, JWT signing key, webhook
  secret). Nothing secret is ever committed.

The container already exists and is production-grade: `backend/Dockerfile`
(multi-stage, non-root, `dumb-init` PID 1, healthcheck). It listens on `$PORT`,
which Cloud Run injects — no code change needed.

> You run these commands with **your own** `gcloud` login. Deploying to your
> cloud needs your Google auth; it cannot come from anyone else. Every value in
> angle brackets is yours to choose.

---

## Prerequisites (once)

```bash
# Install the CLI: https://cloud.google.com/sdk/docs/install
gcloud auth login
gcloud config set project <PROJECT_ID>          # e.g. rami-broast

# Enable the services
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com
```

Pick a region close to your customers, e.g. `me-central2` (Dammam) or
`europe-west1`. Export it so the commands below reuse it:

```bash
export REGION=me-central2
export PROJECT_ID=<PROJECT_ID>
```

---

## Step 1 — create the database (Cloud SQL Postgres)

```bash
gcloud sql instances create rami-pg \
  --database-version=POSTGRES_16 \
  --edition=ENTERPRISE \
  --tier=db-custom-1-3840 \
  --region=$REGION \
  --storage-auto-increase

gcloud sql databases create rdp --instance=rami-pg
gcloud sql users create rdp_app --instance=rami-pg --password='<STRONG_DB_PASSWORD>'
```

Note the **instance connection name** (`PROJECT_ID:REGION:rami-pg`):

```bash
export CONN=$(gcloud sql instances describe rami-pg --format='value(connectionName)')
echo "$CONN"
```

Cloud Run reaches Cloud SQL over a unix socket at `/cloudsql/$CONN`. The Prisma
connection string therefore is:

```
postgresql://rdp_app:<STRONG_DB_PASSWORD>@localhost/rdp?host=/cloudsql/<CONN>&schema=public
```

## Step 2 — store the secrets in Secret Manager

Never pass these as plain `--set-env-vars`. Create them once:

```bash
# Database URL (uses the unix-socket form above)
printf 'postgresql://rdp_app:<STRONG_DB_PASSWORD>@localhost/rdp?host=/cloudsql/%s&schema=public' "$CONN" \
  | gcloud secrets create DATABASE_URL --data-file=-

# JWT signing key — generate a fresh one, never reuse the local dev value
openssl rand -base64 48 | gcloud secrets create JWT_ACCESS_SECRET --data-file=-

# Mock payment webhook secret (until the real Tap adapter + credentials exist)
openssl rand -base64 32 | gcloud secrets create PAYMENT_MOCK_WEBHOOK_SECRET --data-file=-
```

Grant the Cloud Run runtime service account read access:

```bash
export SA="$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')-compute@developer.gserviceaccount.com"
for S in DATABASE_URL JWT_ACCESS_SECRET PAYMENT_MOCK_WEBHOOK_SECRET; do
  gcloud secrets add-iam-policy-binding $S \
    --member="serviceAccount:$SA" --role=roles/secretmanager.secretAccessor
done
```

## Step 3 — run database migrations

Migrations must run **before** the first real traffic. Two ways:

**A. From your machine via the Cloud SQL Auth Proxy (simplest):**

```bash
# In one terminal — open a local socket to the instance
cloud-sql-proxy "$CONN" &
# In the backend repo, point Prisma at the proxy and deploy migrations
cd backend
DATABASE_URL="postgresql://rdp_app:<STRONG_DB_PASSWORD>@127.0.0.1:5432/rdp?schema=public" \
  npx prisma migrate deploy
# Seed permission codes (safe/idempotent; seeds NO staff account by design)
DATABASE_URL="postgresql://rdp_app:<STRONG_DB_PASSWORD>@127.0.0.1:5432/rdp?schema=public" \
  npx prisma db seed
```

**B. As a Cloud Run Job** (repeatable in CI) — see
`.github/workflows/deploy-backend-cloudrun.yml` for the job step.

## Step 4 — deploy the service

From the `backend` repo root (Cloud Run builds the Dockerfile for you):

```bash
cd backend
gcloud run deploy rami-api \
  --source . \
  --region $REGION \
  --platform managed \
  --add-cloudsql-instances "$CONN" \
  --allow-unauthenticated \
  --port 3000 \
  --set-env-vars "NODE_ENV=production,LOG_LEVEL=info,LOG_PRETTY=false,SWAGGER_ENABLED=false,TRUSTED_PROXY_HOPS=1,PAYMENT_GATEWAY=mock,PAYMENT_SANDBOX=true,SMS_PROVIDER=mock,PUSH_PROVIDER=mock,VAT_STANDARD_RATE=0.15,PRICES_INCLUDE_VAT=true,LOYALTY_POINTS_PER_SAR=1" \
  --set-env-vars "CORS_ALLOWED_ORIGINS=https://<your-admin-domain>,https://<customer-app-domain>,https://<pos-host>" \
  --set-secrets "DATABASE_URL=DATABASE_URL:latest,JWT_ACCESS_SECRET=JWT_ACCESS_SECRET:latest,PAYMENT_MOCK_WEBHOOK_SECRET=PAYMENT_MOCK_WEBHOOK_SECRET:latest"
```

`--allow-unauthenticated` is correct here: the API does its own auth (JWT +
guards). Cloud Run only terminates TLS and forwards.

`TRUSTED_PROXY_HOPS=1` — Cloud Run is one proxy in front of the app, so client
IPs (used by rate limiting + audit logs) resolve correctly.

The deploy prints a service URL like `https://rami-api-xxxx.a.run.app`. Your API
base URL for the clients is that **plus `/api/v1`**:

```
https://rami-api-xxxx.a.run.app/api/v1
```

## Step 5 — create the first staff account

No staff account is ever seeded (by design). Create the owner once, via the
proxy from Step 3:

```bash
cd backend
DATABASE_URL="postgresql://rdp_app:<PW>@127.0.0.1:5432/rdp?schema=public" \
  npm run staff:create
```

## Step 6 — wire the clients

- Admin app → set `VITE_API_BASE_URL` to the URL from Step 4 in Vercel, plus the
  Maps key, then redeploy. See `deploy-admin-vercel.md`.
- Mobile apps → set the API base URL in their build config. See
  `deploy-mobile-eas.md`.
- Come back and tighten `CORS_ALLOWED_ORIGINS` to all client-app domains
  (admin, customer-app web, kitchen-pos).

---

## What is NOT live yet (and why)

- **Payments** run on the **mock** gateway (`PAYMENT_GATEWAY=mock`). The real
  Tap adapter needs official Tap docs + merchant credentials — not invented.
- **SMS / push** run on **mock** providers. Real providers need contracts +
  credentials.
- **Invoicing / ZATCA** is not deployed — needs legal/CR/VAT data + official
  ZATCA specs.

None of these block a working delivery deployment; they light up when the
business inputs arrive. See the backend `CLAUDE.md` "Blocked on business input".
