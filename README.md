# rami-infrastructure

Infrastructure, CI/CD, environments and operational docs for the Rami Broast
platform (see each app repo's `CLAUDE.md` for product context).

The backend deploys to **Google Cloud Run** with **Cloud SQL (PostgreSQL)**,
secrets in **Secret Manager**, and GitHub Actions authenticating through
**Workload Identity Federation** (no long-lived service-account keys).

## Start here

- **[`docs/gcp-production-setup.md`](docs/gcp-production-setup.md)** — the
  complete, from-scratch guide to standing up the production Google Cloud
  environment. Written for someone who has never opened the Google Cloud
  console. Read it top to bottom.
- **[`scripts/gcp/provision.sh`](scripts/gcp/provision.sh)** — an optional,
  idempotent script that runs the same steps the guide narrates, once you have
  filled in the variables at the top. **Read it before running it** — it
  creates billable resources.

## Important: the production deploy is intentionally blocked right now

Standing up this infrastructure does **not** make the production backend
deployable yet. The production pipeline (`rami-backend`'s
`.github/workflows/deploy-production.yml`) refuses to deploy while two business
inputs are missing:

1. **Tap Payments** — the real gateway adapter is a stub awaiting official Tap
   docs + merchant credentials.
2. **A real SMS provider** — the only `SMS_PROVIDER` value today is `mock`,
   which delivers no sign-in codes.

Until both land, leave the GitHub repo variables `PAYMENT_GATEWAY` and
`SMS_PROVIDER` **unset** (the guide does this deliberately). The infrastructure
will be ready; the deploy button becomes usable the day those two credentials
arrive. This is by design — a production backend that half-works is worse than
one that refuses to start.
