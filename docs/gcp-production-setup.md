# Google Cloud production setup — from scratch

This is a complete, step-by-step guide to standing up the **production** Google
Cloud environment for the Rami Broast backend. It assumes **you have never used
Google Cloud before**. Follow it in order.

By the end you will have:

- a Google Cloud project with billing attached,
- a Cloud SQL PostgreSQL database,
- the backend's two required secrets in Secret Manager,
- a dedicated deploy identity that GitHub Actions can use **without any stored
  key** (Workload Identity Federation),
- all the GitHub repository variables and secrets the deploy workflow reads.

It will **not** deploy the production service — that stays blocked until the Tap
payment gateway and a real SMS provider are ready (see the repo README). What
you build here is the environment that deploy drops into later.

> **Terminology:** a *project* is the top-level container for everything in
> Google Cloud. A *service account* is a non-human identity that software uses.
> A *secret* is an encrypted value (like a password) stored by Google and handed
> to the service at runtime. You do not need to understand these deeply to
> follow along.

---

## What this costs

You pay only while resources exist. Rough monthly order of magnitude (confirm
with the [pricing calculator](https://cloud.google.com/products/calculator)):

| Resource | Idle (deploy-later) | In production |
| --- | --- | --- |
| Cloud SQL (`db-g1-small`, zonal) | ~$25–35/mo running 24/7 | upsize to `db-custom-1-3840`+ |
| Cloud Run | ~$0 when no traffic (scales to zero) | pay per request |
| Secret Manager / Artifact Registry | cents | cents |

**New Google Cloud accounts get ~$300 of free credit for 90 days**, which covers
all of this during setup and the demo period.

> **Decision — because you are deploying later:** Cloud SQL bills 24/7 even with
> no traffic. If launch is weeks away, either (a) create the smallest instance
> now (`db-g1-small`, this guide's default) and upsize at launch, or (b) skip
> Step 6 for now and run it closer to launch. Everything else here is
> near-free at rest.

---

## Step 1 — Create your Google Cloud account

1. Go to <https://console.cloud.google.com/>.
2. Sign in with the Google account that should **own** this (use a company
   account you control, not a personal one you might lose access to).
3. Accept the terms. If prompted, start the **free trial** to get the $300
   credit — this requires a credit card for identity verification but is not
   charged unless you manually upgrade.

You now have access to the console. You will do almost everything from here on
in **Cloud Shell**, not your own computer — it is simpler and avoids installing
anything.

---

## Step 2 — Open Cloud Shell (no local install needed)

In the console, click the **terminal icon** (`>_`) in the top-right toolbar.
A terminal opens at the bottom of the browser. This is **Cloud Shell**: a free
Linux shell with `gcloud` already installed and **already signed in as you**.

> Everything in Steps 3–11 is typed into this Cloud Shell terminal. You can
> copy-paste. If Cloud Shell times out, just reopen it and re-run
> `source ~/rami-env.sh` (you create that file in Step 3).

Verify you are signed in:

```bash
gcloud auth list
```

You should see your email with `*` next to it.

---

## Step 3 — Choose your settings (do this once)

Pick your values, then paste this block **after editing it**. Saving them to a
file means you can re-source them if Cloud Shell restarts.

```bash
cat > ~/rami-env.sh <<'EOF'
# ---- EDIT THESE ----
export PROJECT_ID="rami-broast-prod"        # must be globally unique; lowercase, digits, hyphens
export REGION="me-central2"                  # Dammam (Saudi Arabia). Fallback: europe-west1
export BILLING_ACCOUNT=""                    # fill in after running the command in Step 4

# ---- names you can leave as-is ----
export SQL_INSTANCE="rami-pg"
export SQL_DB="rami"
export SQL_USER="rami_app"
export SERVICE_NAME="rami-backend"
export DEPLOY_SA="gh-deployer"
export POOL="github-pool"
export PROVIDER="github-provider"
export GITHUB_REPO="Rami-Broast/rami-backend"
export GITHUB_OWNER="Rami-Broast"
EOF
source ~/rami-env.sh
echo "Project will be: $PROJECT_ID in $REGION"
```

> **Region check.** `me-central2` (Dammam) keeps data in Saudi Arabia — best for
> latency and for customer-PII / tax-record residency. Confirm it offers Cloud
> SQL and Cloud Run before committing:
>
> ```bash
> gcloud run regions list --filter="name:$REGION" 2>/dev/null | grep -q "$REGION" \
>   && echo "Cloud Run OK in $REGION" || echo "Cloud Run NOT in $REGION — use europe-west1"
> gcloud sql tiers list --project="$PROJECT_ID" 2>/dev/null >/dev/null \
>   && echo "run this again after Step 5 to confirm Cloud SQL tiers"
> ```
>
> If either comes back wrong, set `export REGION="europe-west1"` in
> `~/rami-env.sh`, `source` it again, and continue.

---

## Step 4 — Find your billing account

```bash
gcloud billing accounts list
```

Copy the `ACCOUNT_ID` (looks like `0X0X0X-0X0X0X-0X0X0X`), put it into
`~/rami-env.sh` as `BILLING_ACCOUNT`, then:

```bash
source ~/rami-env.sh
```

If the list is empty, you have no billing account yet — set one up at
<https://console.cloud.google.com/billing> (this is where the free-trial card
lives) and re-run.

---

## Step 5 — Create the project, link billing, enable APIs

```bash
# Create the project (skip if it already exists)
gcloud projects create "$PROJECT_ID" --name="Rami Broast (prod)" || true

# Point gcloud at it
gcloud config set project "$PROJECT_ID"

# Attach billing (nothing bills until you create paid resources)
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"

# Turn on the APIs the platform needs
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com
```

Enabling APIs takes a minute. The `compute` API is what creates the default
runtime identity you will grant permissions to in Step 9.

---

## Step 6 — Create the Cloud SQL (PostgreSQL) database

> This is the one step that starts billing in earnest. See the cost note above.

```bash
# The instance (small/zonal for the deploy-later period — upsize at launch).
gcloud sql instances create "$SQL_INSTANCE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --database-version=POSTGRES_16 \
  --tier=db-g1-small \
  --storage-size=10GB \
  --storage-auto-increase \
  --availability-type=ZONAL
```

Creating the instance takes several minutes. When it finishes, set passwords and
create the application database and user:

```bash
# Generate strong, URL-safe (alphanumeric) passwords — no special chars to escape.
export POSTGRES_PW="$(openssl rand -hex 24)"
export APP_PW="$(openssl rand -hex 24)"

# Lock the built-in superuser
gcloud sql users set-password postgres \
  --instance="$SQL_INSTANCE" --password="$POSTGRES_PW"

# The application database and its own user
gcloud sql databases create "$SQL_DB" --instance="$SQL_INSTANCE"
gcloud sql users create "$SQL_USER" \
  --instance="$SQL_INSTANCE" --password="$APP_PW"

# The connection name the deploy and the proxy use: PROJECT:REGION:INSTANCE
export CLOUDSQL_CONN="$(gcloud sql instances describe "$SQL_INSTANCE" \
  --format='value(connectionName)')"
echo "CLOUDSQL_CONN=$CLOUDSQL_CONN"
```

> Keep this Cloud Shell tab open — `APP_PW` and `CLOUDSQL_CONN` are used in the
> next step. If you lose them, re-run the `describe` line for `CLOUDSQL_CONN` and
> reset `APP_PW` with `gcloud sql users set-password`.

---

## Step 7 — Store the two secrets the backend requires

The backend needs exactly two secret values at boot: `DATABASE_URL` and
`JWT_ACCESS_SECRET`. Everything else has a safe default and is set as plain env
vars by the deploy workflow.

```bash
# DATABASE_URL in the Cloud Run "unix socket" form. Cloud Run mounts the Cloud
# SQL socket at /cloudsql/<connection-name>; the deploy's migrate step rewrites
# this to a TCP URL automatically when it runs through the proxy.
export DATABASE_URL="postgresql://${SQL_USER}:${APP_PW}@localhost/${SQL_DB}?host=/cloudsql/${CLOUDSQL_CONN}"

printf '%s' "$DATABASE_URL" | gcloud secrets create DATABASE_URL \
  --data-file=- --replication-policy=automatic

# A long random signing key for access tokens.
openssl rand -base64 48 | tr -d '\n' | gcloud secrets create JWT_ACCESS_SECRET \
  --data-file=- --replication-policy=automatic
```

> **The app password now lives only inside the `DATABASE_URL` secret** — that is
> correct and intended. You never pass it through GitHub.

---

## Step 8 — Create the deploy identity

This service account is what GitHub Actions *becomes* when it deploys. It never
has a downloadable key — Step 10 lets GitHub impersonate it directly.

```bash
gcloud iam service-accounts create "$DEPLOY_SA" \
  --display-name="GitHub Actions deployer"

export DEPLOY_SA_EMAIL="${DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

# Roles the deploy needs: build the image, push it, deploy Cloud Run, read
# secrets, reach Cloud SQL, and act as the runtime identity.
for ROLE in \
  roles/run.admin \
  roles/cloudbuild.builds.editor \
  roles/artifactregistry.admin \
  roles/storage.admin \
  roles/cloudsql.client \
  roles/secretmanager.secretAccessor \
  roles/iam.serviceAccountUser \
  roles/logging.logWriter ; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${DEPLOY_SA_EMAIL}" --role="$ROLE" --condition=None
done
```

Now grant the **runtime** identity (the default Compute service account that
Cloud Run uses to *run* the container) permission to read the secrets and reach
the database:

```bash
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
export RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/secretmanager.secretAccessor" --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/cloudsql.client" --condition=None
```

> **Hardening option (optional):** instead of the default Compute account, create
> a dedicated runtime SA and add `--service-account=<that SA>` to the
> `gcloud run deploy` line in `deploy-production.yml`. The guide uses the default
> account so the existing workflow works unchanged.

---

## Step 9 — Create an Artifact Registry repository

`gcloud run deploy --source` builds a container and stores it here.

```bash
gcloud artifacts repositories create cloud-run-source-deploy \
  --repository-format=docker \
  --location="$REGION" \
  --description="Cloud Run source deploys" || true
```

(`cloud-run-source-deploy` is the default name Cloud Run uses; creating it
explicitly avoids a first-deploy permission surprise.)

---

## Step 10 — Let GitHub Actions authenticate (Workload Identity Federation)

This is the step that replaces stored keys. GitHub's Actions runner presents a
short-lived OpenID token; Google trusts it **only** for your repo.

```bash
# A pool to hold external identities
gcloud iam workload-identity-pools create "$POOL" \
  --location=global --display-name="GitHub Actions pool" || true

export POOL_ID="$(gcloud iam workload-identity-pools describe "$POOL" \
  --location=global --format='value(name)')"

# A provider that trusts GitHub's token issuer, restricted to your org
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --location=global --workload-identity-pool="$POOL" \
  --display-name="GitHub provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner=='${GITHUB_OWNER}'" || true

# Allow ONLY the backend repo to impersonate the deploy service account
gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

# The two values GitHub needs — copy both from the output
export WIF_PROVIDER="$(gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --location=global --workload-identity-pool="$POOL" --format='value(name)')"
echo
echo "========== COPY THESE INTO GITHUB (Step 11) =========="
echo "GCP_WORKLOAD_IDENTITY_PROVIDER = $WIF_PROVIDER"
echo "GCP_DEPLOY_SA_EMAIL            = $DEPLOY_SA_EMAIL"
echo "GCP_PROJECT_ID                 = $PROJECT_ID"
echo "GCP_REGION                     = $REGION"
echo "CLOUDSQL_CONN                  = $CLOUDSQL_CONN"
echo "======================================================"
```

---

## Step 11 — Configure the GitHub repository

The deploy workflow reads these from the **`rami-backend`** repository. Set them
in GitHub → **Settings → Secrets and variables → Actions**.

### Variables (the `Variables` tab — not secret)

| Name | Value | Notes |
| --- | --- | --- |
| `GCP_PROJECT_ID` | your `$PROJECT_ID` | |
| `GCP_REGION` | your `$REGION` | |
| `CLOUDSQL_CONN` | `PROJECT:REGION:INSTANCE` from Step 6 | |
| `PROD_SERVICE_NAME` | `rami-backend` | the Cloud Run service name |
| `CLIENT_ORIGINS` | your real admin/POS/customer/driver origins, comma-separated | used for CORS — see note |
| `PUSH_PROVIDER` | `mock` | only value available today |
| `PAYMENT_GATEWAY` | **leave unset** | setting it to anything but `tap` (unavailable) keeps the deploy blocked, which is intended |
| `SMS_PROVIDER` | **leave unset** | same — no real provider exists yet |

> `CLIENT_ORIGINS` must list every front-end origin that calls the API, or those
> apps get CORS-rejected before any route runs. The canonical list belongs in
> `docs/client-origins-and-cors.md` (create it when the production domains are
> known).

### Secrets (the `Secrets` tab)

| Name | Value |
| --- | --- |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | the `WIF_PROVIDER` printed in Step 10 |
| `GCP_DEPLOY_SA_EMAIL` | the `$DEPLOY_SA_EMAIL` printed in Step 10 |

> Note: `DATABASE_URL` and `JWT_ACCESS_SECRET` are **not** GitHub secrets — they
> live in Google Secret Manager (Step 7) and are read by the service directly.
> Nothing sensitive passes through GitHub.

**Using the `gh` CLI instead of the UI** (run on a machine logged into `gh`):

```bash
gh variable set GCP_PROJECT_ID   --repo "$GITHUB_REPO" --body "$PROJECT_ID"
gh variable set GCP_REGION       --repo "$GITHUB_REPO" --body "$REGION"
gh variable set CLOUDSQL_CONN    --repo "$GITHUB_REPO" --body "$CLOUDSQL_CONN"
gh variable set PROD_SERVICE_NAME --repo "$GITHUB_REPO" --body "rami-backend"
gh variable set PUSH_PROVIDER    --repo "$GITHUB_REPO" --body "mock"
# CLIENT_ORIGINS: set once you know the real domains
gh secret   set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "$GITHUB_REPO" --body "$WIF_PROVIDER"
gh secret   set GCP_DEPLOY_SA_EMAIL            --repo "$GITHUB_REPO" --body "$DEPLOY_SA_EMAIL"
```

---

## Step 12 — Protect the production environment in GitHub

The production workflow is scoped to a GitHub **Environment** called
`production`, so you can require a human approval before any run.

1. GitHub → **Settings → Environments → New environment → `production`**.
2. Add yourself (and anyone who may approve) under **Required reviewers**.

Now the only way to production is a manual run that a named person approves — it
is never deployed by merging.

---

## Step 13 — Verify the infrastructure (without deploying)

You cannot do a production deploy yet (Tap + SMS are missing, by design). But you
can prove the database and secrets are wired correctly, from Cloud Shell:

```bash
# Prove the app user can reach the database through the proxy
curl -sSL -o /tmp/csp \
  https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.13.0/cloud-sql-proxy.linux.amd64
chmod +x /tmp/csp
/tmp/csp --port 5433 "$CLOUDSQL_CONN" &
PROXY_PID=$!
sleep 5
PGPASSWORD="$APP_PW" psql "host=127.0.0.1 port=5433 user=$SQL_USER dbname=$SQL_DB" -c '\conninfo'
kill "$PROXY_PID"

# Prove the secrets exist and are readable
gcloud secrets versions access latest --secret=DATABASE_URL >/dev/null && echo "DATABASE_URL OK"
gcloud secrets versions access latest --secret=JWT_ACCESS_SECRET >/dev/null && echo "JWT_ACCESS_SECRET OK"
```

If those print `OK`, the environment is ready and waiting.

**What happens if you run the production deploy today:** it will stop at the
`Refuse demo configuration` step with a clear error, because `PAYMENT_GATEWAY`
and `SMS_PROVIDER` are unset. That is the correct, intended behaviour.

---

## When Tap and SMS are ready (the remaining unblock)

1. Land the real `TapPaymentGateway` adapter in `rami-backend` (needs official
   Tap docs + merchant credentials).
2. Add the chosen SMS provider to the `SmsProvider` enum with its adapter, and
   add its production boot-guard.
3. Store any new provider credentials in **Secret Manager** (never GitHub).
4. Set the GitHub variables `PAYMENT_GATEWAY=tap` and `SMS_PROVIDER=<provider>`.
5. Run **Deploy backend — PRODUCTION** from the Actions tab, type the
   confirmation phrase, and approve the environment gate.

---

## Teardown (to stop all charges)

```bash
gcloud sql instances delete "$SQL_INSTANCE"            # the only big cost
gcloud run services delete "$SERVICE_NAME" --region="$REGION" 2>/dev/null || true
# Secrets, Artifact Registry and the WIF pool cost ~nothing; delete if you want:
# gcloud secrets delete DATABASE_URL
# gcloud secrets delete JWT_ACCESS_SECRET
```

Deleting the project entirely (`gcloud projects delete "$PROJECT_ID"`) removes
everything at once.

---

## Troubleshooting

- **A deploy fails with a permissions error naming a role.** Grant that exact
  role to `$DEPLOY_SA_EMAIL` (newer Cloud Build sometimes needs an extra one);
  re-run.
- **`PERMISSION_DENIED` from the WIF auth step in Actions.** The repo name in the
  `principalSet` binding (Step 10) must match `owner/repo` exactly, and the
  workflow must request `id-token: write` permissions (it does).
- **The service boots then crashes on the database.** Check the `DATABASE_URL`
  secret's socket path matches `CLOUDSQL_CONN`, and that the deploy includes
  `--add-cloudsql-instances` (it does).
- **CORS errors in a browser app.** The app's origin is missing from
  `CLIENT_ORIGINS`.
