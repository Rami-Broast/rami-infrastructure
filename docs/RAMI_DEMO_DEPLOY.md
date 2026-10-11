# Rami Broast — bring the DEMO up (Cloud Shell runbook)

This gets the **demo** live end-to-end on mocks. When you finish:

- backend running on Cloud Run as `rami-api`, with its own database,
- all four client apps deployed and talking to it,
- OTP pinned to `123456`, payments auto-settling on the mock gateway, push mocked,
- **the only things still "fake" are exactly the ones that need real vendors:
  the SMS/OTP provider, the Tap payment gateway, and (for invoices) the RestoPOS
  ZATCA service.** Everything else is real.

> Isolation: give Rami its **own** Google Cloud project, database and secrets.
> Never reuse another project's values. The code cannot create a cross-connection;
> only shared infrastructure can, and this runbook never introduces any.

This is the **demo** path. The production path is a different workflow and stays
blocked on Tap + SMS — see `gcp-production-setup.md`. Where that guide and this
one overlap (GCP provisioning), this one is authoritative **for the demo**
because it creates one extra secret and uses the demo deploy workflow.

---

## 0. What you need before you start

- A Google account that will **own** this (a company account, not personal).
- Admin access to the **`Rami-Broast`** GitHub org (to set repo variables/secrets
  and run workflows).
- A **Google Maps API key** (one real key — maps degrade to "unavailable" without
  it but the demo still runs). Vercel account for the four front-ends.
- ~$300 free GCP trial credit covers the whole demo period.

Decide your **four Vercel project names now** — you need them before the backend
deploy (see §4). Recommended:

| App | Vercel project | Origin you will use |
| --- | --- | --- |
| Admin (owner + branch) | `rami-admin` | `https://rami-admin.vercel.app` |
| Branch POS | `rami-pos` | `https://rami-pos.vercel.app` |
| Customer | `rami-customer` | `https://rami-customer.vercel.app` |
| Driver | `rami-driver` | `https://rami-driver.vercel.app` |

(If a name is taken, Vercel appends a suffix — then use the real URL it gives you
and keep `CLIENT_ORIGINS` in step with it.)

---

## 1. Open Cloud Shell and set your variables

Google Cloud console → the **`>_`** terminal icon (top right). Then:

```bash
cat > ~/rami-env.sh <<'EOF'
# ---- EDIT THESE ----
export PROJECT_ID="rami-broast-demo"      # globally unique; lowercase/digits/hyphens
export REGION="me-central2"               # Dammam, KSA. Fallback: europe-west1
export BILLING_ACCOUNT=""                 # fill from `gcloud billing accounts list`

# ---- leave as-is ----
export SQL_INSTANCE="rami-pg"
export SQL_DB="rami"
export SQL_USER="rami_app"
export DEPLOY_SA="gh-deployer"
export POOL="github-pool"
export PROVIDER="github-provider"
export GITHUB_OWNER="Rami-Broast"
export GITHUB_REPO="Rami-Broast/rami-backend"
EOF
source ~/rami-env.sh
gcloud auth list   # confirm your email has a '*'
```

```bash
gcloud billing accounts list     # copy the ACCOUNT_ID into BILLING_ACCOUNT above, then:
source ~/rami-env.sh
```

> If Cloud Shell times out later, reopen it and run `source ~/rami-env.sh` again.

---

## 2. Create the project, link billing, enable APIs

```bash
gcloud projects create "$PROJECT_ID" --name="Rami Broast (demo)" || true
gcloud config set project "$PROJECT_ID"
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"

gcloud services enable \
  run.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com compute.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com
```

---

## 3. Provision the rest with one script

The repo ships an idempotent script that does Cloud SQL + the two base secrets +
the deploy identity + Workload Identity Federation. Run it, then come back here
for the **one demo-only secret it does not create**.

```bash
git clone https://github.com/Rami-Broast/rami-infrastructure.git
cd rami-infrastructure/scripts/gcp
BILLING_ACCOUNT="$BILLING_ACCOUNT" PROJECT_ID="$PROJECT_ID" REGION="$REGION" \
  ./provision.sh
cd ~
```

It prints a **COPY THESE INTO GITHUB** block at the end — keep that terminal
output; you need `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_DEPLOY_SA_EMAIL` and
`CLOUDSQL_CONN` in §5.

> Prefer to go step-by-step by hand instead of the script? Follow
> `gcp-production-setup.md` Steps 5–10 — they are identical — then return here.

### 3a. The demo-only secret (REQUIRED — the script does not create it)

The **demo** deploy mounts a third secret, `PAYMENT_MOCK_WEBHOOK_SECRET`, that the
mock gateway signs its own webhooks with. Without it the demo deploy fails at
rollout. Create it once:

```bash
source ~/rami-env.sh
gcloud config set project "$PROJECT_ID"
openssl rand -base64 32 | tr -d '\n' | \
  gcloud secrets create PAYMENT_MOCK_WEBHOOK_SECRET --data-file=- --replication-policy=automatic
```

You now have three secrets in Secret Manager: `DATABASE_URL`, `JWT_ACCESS_SECRET`,
`PAYMENT_MOCK_WEBHOOK_SECRET`.

### 3b. Let the runtime SA read that third secret

`provision.sh` already granted the runtime service account access to the first
two secrets. Grant it the new one too (project-level `secretAccessor` already
covers it if you used the script — this is belt-and-braces and harmless):

```bash
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud secrets add-iam-policy-binding PAYMENT_MOCK_WEBHOOK_SECRET \
  --member="serviceAccount:${RUNTIME_SA}" --role="roles/secretmanager.secretAccessor"
```

---

## 4. Decide your client origins (breaks the chicken-and-egg)

The demo deploy's final step sends a real CORS preflight from **every** origin in
`CLIENT_ORIGINS` and **fails the whole deploy if the list is empty or any origin
is refused**. You do not need the apps deployed yet — only the origin *strings* —
and because you chose the Vercel project names in §0, you already know them:

```
https://rami-admin.vercel.app,https://rami-pos.vercel.app,https://rami-customer.vercel.app,https://rami-driver.vercel.app
```

Keep that comma-separated string; it goes into GitHub next. (No spaces.)

---

## 5. Set the GitHub variables & secrets on `rami-backend`

GitHub → **Rami-Broast/rami-backend → Settings → Secrets and variables → Actions**.

**Variables** tab:

| Name | Value |
| --- | --- |
| `GCP_PROJECT_ID` | your `$PROJECT_ID` |
| `GCP_REGION` | your `$REGION` |
| `CLOUDSQL_CONN` | `PROJECT:REGION:INSTANCE` (from §3 output) |
| `CLIENT_ORIGINS` | the comma-separated string from §4 |

**Secrets** tab:

| Name | Value |
| --- | --- |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | from §3 output |
| `GCP_DEPLOY_SA_EMAIL` | from §3 output |

> The demo workflow hardcodes `PAYMENT_GATEWAY=mock`, `SMS_PROVIDER=mock`,
> `PUSH_PROVIDER=mock`, `OTP_DEMO_FIXED_CODE=123456` and `NODE_ENV=staging`, so you
> do **not** set those as variables. `DATABASE_URL`, `JWT_ACCESS_SECRET` and
> `PAYMENT_MOCK_WEBHOOK_SECRET` live in Secret Manager, not GitHub.

---

## 6. Deploy the backend

GitHub → **rami-backend → Actions → "Deploy backend — DEMO (Cloud Run)" → Run
workflow** (on `main`).

It will: run migrations, seed permission codes, deploy `rami-api`, then verify
CORS for all four origins. When it goes green, open the run summary — it prints:

```
Service URL: https://rami-api-XXXXXXXX.run.app
API base:    https://rami-api-XXXXXXXX.run.app/api/v1
```

**Copy that API base.** Every client needs it.

> If the CORS step fails naming an origin, your `CLIENT_ORIGINS` doesn't match the
> real Vercel URL — fix the variable and re-run. If it fails earlier on a secret,
> you missed §3a.

---

## 7. Deploy the four front-ends on Vercel

For each app: **New Project → import its GitHub repo → set the env var below →
Deploy.** Use the project **names from §0** so the URLs match `CLIENT_ORIGINS`.

| Repo | Vercel project | Build env vars |
| --- | --- | --- |
| `rami-admin` | `rami-admin` | `VITE_API_BASE_URL = <API base>` and `VITE_GOOGLE_MAPS_API_KEY = <maps key>` |
| `rami-kitchen` | `rami-pos` | `VITE_API_BASE_URL = <API base>` |
| `rami-customer-app` | `rami-customer` | API base per the repo's `DEPLOYMENT`/README (Expo `extra.apiBaseUrl`) |
| `rami-driver-app` | `rami-driver` | `API_BASE_URL = <API base>`, `GOOGLE_MAPS_API_KEY = <maps key>` |

`<API base>` is the `…/api/v1` URL from §6. Admin is the main maps surface (Live
Ops); customer/driver maps degrade gracefully without a key.

> If any app's real Vercel URL differs from §0 (name taken, custom domain), update
> the `CLIENT_ORIGINS` variable (§5) and re-run the backend deploy (§6) so CORS
> allows the real origin.

---

## 8. Create the owner account

No staff is ever seeded. GitHub → **rami-backend → Actions → "Create staff
account" → Run workflow**:

- email: e.g. `owner@demo.test`
- name: `Demo Owner`
- role: `OWNER`
- branch_code: leave blank
- password: a 12+ char password you choose

Sign into the **admin** app with those. Create branches, a menu, and branch-admin
/ kitchen / driver accounts from inside the admin panel. The POS signs in with a
branch account; the driver app with a driver account.

---

## 9. Verify the demo

- Admin: sign in, create a branch + a couple of menu items, mark a branch open.
- Customer app: place an order (OTP is **`123456`**). Because the mock gateway
  auto-settles, the order should reach PAID and appear on the POS **New orders**.
- POS: accept → preparing → ready; for a delivery order, assign a driver.
- Driver app: sign in as the driver, see the job, walk pickup → delivered.
- Admin Live Ops: the driver's pin shows (needs the Maps key).

If all of that flows, the demo is up.

---

## What is still mocked (and why that's correct)

| Area | State in demo | To go real |
| --- | --- | --- |
| OTP / SMS | pinned `123456`, mock sender | contract an SMS provider, add it to `SmsProvider` + its boot guard, set `SMS_PROVIDER` |
| Payments | mock gateway, auto-settles | build the real `TapPaymentGateway` from official Tap docs + merchant creds |
| ZATCA invoices | mock RestoPOS adapter, OFF by default | a real RestoPOS licence + `ZATCA_PROVIDER=restopos` + base URL |
| Push | mock | contract FCM/APNs, set `PUSH_PROVIDER` |

The first two are what you named; the third (RestoPOS/ZATCA) is Rami-specific and
easy to forget, so it's listed here. None blocks the demo.

---

## Teardown (stop all charges)

```bash
source ~/rami-env.sh
gcloud sql instances delete "$SQL_INSTANCE"
gcloud run services delete rami-api --region="$REGION" 2>/dev/null || true
# or remove everything at once:
# gcloud projects delete "$PROJECT_ID"
```
