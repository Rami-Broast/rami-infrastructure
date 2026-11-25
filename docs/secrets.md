# Secret management

**The one rule (repeated from the README): no key, password, credential or
certificate is ever committed to any repo.** This repo holds only secret
*names*. Values live in the platform's own secret stores.

| Surface | Store | How the app reads it |
| --- | --- | --- |
| Backend (Cloud Run) | **Secret Manager** | `--set-secrets NAME=SECRET:latest` → env var |
| Admin (Vercel) | **Vercel env vars** (encrypted) | build/runtime env |
| Mobile (EAS) | **EAS secrets** | build env |

## Backend secrets (Secret Manager)

Authoritative names — production and their `…_STAGING` twins:

| Name | What |
| --- | --- |
| `DATABASE_URL` | Postgres connection (Cloud SQL socket) |
| `JWT_ACCESS_SECRET` | access-token signing key |
| `PAYMENT_MOCK_WEBHOOK_SECRET` | HMAC secret for the mock gateway's signed webhooks |

Future, once approved (never guessed — added when credentials arrive): Tap keys,
SMS provider key, FCM/APNs, Google Maps server key, object-storage credentials.

## Push values (from your machine only)

Keep values in a local, git-ignored file (e.g. `~/rami-secrets.env`) and sync:

```bash
PROJECT_ID=rami-broast \
RUNTIME_SA=rami-api@rami-broast.iam.gserviceaccount.com \
./scripts/setup-secrets.sh ~/rami-secrets.env
```

`setup-secrets.sh` creates each secret if missing, adds a new version with the
value, and grants the runtime service account `secretAccessor`. It **refuses to
read a git-tracked file**, so a secret file accidentally added to a repo can't
be pushed through it. Values go straight from your shell to GCP — never to a repo
or to logs.

## Rotation

1. `gcloud secrets versions add <NAME> --data-file=-` (new value from stdin).
2. Redeploy so `:latest` is picked up (Cloud Run reads at start), or restart.
3. Disable the old version once traffic is on the new one:
   `gcloud secrets versions disable <VERSION> --secret <NAME>`.

## If a secret leaks

Rotate immediately (steps above), disable the exposed version, and audit access
(`gcloud logging read 'protoPayload.serviceName="secretmanager.googleapis.com"'`).
For a leaked gateway/DB credential, also rotate at the source (gateway dashboard
/ Cloud SQL user password). Never paste the leaked value into an issue or chat.

## Production hardening (pre-launch)

Grant `secretAccessor` only to the runtime SA (least privilege); keep the deploy
SA separate. Consider CMEK on Secret Manager and VPC-SC if the client's
compliance posture calls for it — decide with the client, don't assume.
