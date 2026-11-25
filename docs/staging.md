# Staging environment

A production-like, isolated environment for verifying a release before it reaches
production. Same code path, same shape, **its own data** — never a pointer at
production.

## What "isolated" means here

| Piece | Production | Staging |
| --- | --- | --- |
| Cloud Run service | `rami-api` | `rami-api-staging` |
| Cloud SQL | prod instance | separate instance/DB |
| Secrets | `DATABASE_URL`, … | `DATABASE_URL_STAGING`, … |
| Admin (Vercel) | prod project | staging project / preview |
| Providers | mock (until approved) | mock, OTP pinned to `123456` |
| Swagger | off | on |

## Provision (once)

```bash
# Separate Cloud SQL instance (smaller tier is fine for staging).
gcloud sql instances create rami-pg-staging \
  --project "$PROJECT_ID" --database-version POSTGRES_16 \
  --tier db-custom-1-3840 --region "$REGION"
gcloud sql databases create bah --instance rami-pg-staging --project "$PROJECT_ID"

# Staging secrets (values supplied out-of-band, never committed):
for s in DATABASE_URL_STAGING JWT_ACCESS_SECRET_STAGING PAYMENT_MOCK_WEBHOOK_SECRET_STAGING; do
  gcloud secrets create "$s" --project "$PROJECT_ID" --replication-policy automatic
done
# ...then add a version to each: gcloud secrets versions add <name> --data-file=-
```

Env reference: [`env/backend.staging.env.example`](../env/backend.staging.env.example).

## Deploy

Automatic on push to `main` via the template workflow
[`deploy-backend-staging.yml`](../.github/workflows/deploy-backend-staging.yml)
(copy into the backend repo). It migrates the staging DB, then rolls out
`rami-api-staging`. Production stays a **manual promote** afterward.

Manual deploy with the existing script:

```bash
PROJECT_ID=rami-broast REGION=me-central2 \
SERVICE=rami-api-staging \
CONN=<staging-instance-connection-name> \
BACKEND_DIR=../backend \
ADMIN_ORIGINS=https://staging-admin.example.com \
./scripts/deploy-backend-cloudrun.sh
```

(Point its `--set-secrets` at the `…_STAGING` secrets — the script references
secrets by name; adjust for staging or use the workflow which already does.)

## Seed demo data

Staging is where the full suite should run green before a release. Seed it with
the backend's own seeders (permissions, then a staff user) against the staging
DB via the Cloud SQL Auth Proxy:

```bash
DATABASE_URL="$(gcloud secrets versions access latest --secret=DATABASE_URL_STAGING)" \
  npm --prefix ../backend run prisma:seed
DATABASE_URL="..." npm --prefix ../backend run staff:create
```

## Release gate

Before promoting staging → production:

1. Backend test suites green against staging (unit always; integration/e2e via
   the Auth Proxy).
2. Smoke: OTP login (`123456`), place an order, drive it to DELIVERED, run the
   mock payment webhook, record COD cash.
3. Uptime check + alerts green (see [`monitoring.md`](./monitoring.md)).
4. A restore rehearsal has been done this month (see
   [`backups-and-restore.md`](./backups-and-restore.md)).
