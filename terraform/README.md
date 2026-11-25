# Terraform (IaC) — starting skeleton

Reproducible GCP environments: service account, Cloud SQL (with managed backups
+ PITR), Secret Manager secret **names**, a GCS backup bucket, and the Cloud Run
service shell. One config, two environments via `env = "staging" | "production"`.

> **Status: skeleton, not yet applied or `terraform validate`d** (no Terraform
> toolchain in the dev sandbox). Review and run `terraform validate` + `plan`
> before any `apply`. This is the optional/"recommended" infra item — the
> gcloud scripts and workflows are the primary, tested path today.

## What Terraform owns vs. not

- **Owns:** SA, Cloud SQL instance/db, secret *containers*, backup bucket,
  Cloud Run service shell + scaling + Cloud SQL wiring, IAM.
- **Does NOT own:** secret **values** (added via `scripts/setup-secrets.sh`, so
  nothing sensitive lands in TF state), the container **image** and **env**
  (pushed by CI on each deploy — `ignore_changes` keeps TF from fighting CI),
  and the DB user/password (created out-of-band into `DATABASE_URL`).

## Use

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit project/region/env
terraform init
terraform validate
terraform plan
terraform apply
```

Run it once per environment (separate state prefixes / workspaces). Configure the
GCS state backend in `versions.tf` before collaborating.

## After apply

1. `scripts/setup-secrets.sh` — add secret values for the created names.
2. CI (`deploy-backend-*.yml`) pushes the real image + env to the Cloud Run shell.
3. `scripts/setup-monitoring.sh` — uptime check + alerts.
