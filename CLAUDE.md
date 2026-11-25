# infrastructure — project context

Docker, CI/CD, environments, monitoring, backups.

## Client-demo decisions (locked)

**Read `../backend/DEMO_DECISIONS.md`.**

- We are in the client-demo phase. Nothing production-facing is provisioned
  without explicit client approval. Real secrets never come through
  GitHub — they arrive via secure secret management on the day.
- **Google Maps API keys** are the one credential we need before the demo.
  Wire them into the customer/admin/driver build envs, not into the repo.
- **Tap, real SMS, real push, printer/POS hardware** — do not stand up
  their infra until the client approves and hands over credentials.
- **QZ Tray signing — self-signed** (owner decision, 2026-09-10).
  `docs/qz-tray-signing.md` is the whole procedure and
  `scripts/generate-qz-certificate.sh` makes the pair. Two variables, set
  together or not at all: `QZ_SIGNING_CERTIFICATE` (public) and
  `QZ_SIGNING_PRIVATE_KEY` (**a secret** — Secret Manager only; the backend
  refuses to boot on half a pair).
  Its one per-machine cost is handled by the POS rather than by a person: Print
  settings offers a **one-file installer with the certificate inside it**, which
  the branch runs as administrator. Nothing to email, no path to type. Skipped
  or unconfigured, every branch still prints and is prompted once a session.
  **Rotation has an order**: every counter needs the new certificate installed
  *before* the new key starts signing, or every branch is prompted until
  somebody visits it.

## Status (from the platform status audit)

Configured as code in this repo (each becomes live the moment its cloud login /
credentials are in hand — nothing production-facing is provisioned before then):

- **Per-app CI** — `ci.yml` (lint + typecheck + test + build) now in
  `admin-app`, `customer-app`, `driver-app` and `kitchen-pos` (the Branch POS
  is scaffolded; its CI runs on every push and PR).
- **Branch POS deploy** — `docs/deploy-kitchen-pos.md`: one static build for
  every branch (each signs in with its own creds; the backend scopes to that
  branch), pointed at the API URL. Printer/QZ Tray is configured per counter
  machine, not part of the deploy. No Maps key.
- **Staging** — `env/backend.staging.env.example`,
  `.github/workflows/deploy-backend-staging.yml`, `docs/staging.md`.
- **Monitoring / alerting** — `monitoring/*.json` (uptime, error rate, latency,
  payment/webhook failures) + `scripts/setup-monitoring.sh` + `docs/monitoring.md`.
- **Backups + tested restore** — `scripts/db-backup.sh` / `db-restore.sh` +
  `docs/backups-and-restore.md`. The backup→restore roundtrip is tested.
- **Client origins / CORS** — `docs/client-origins-and-cors.md`, the single
  source of truth. Four clients run in a browser, and **two of them are the Expo
  apps** (`customer-app`, `driver-app` each carry a `vercel.json` and are
  deployed as web builds for the demo) — they read as "mobile" and get left off
  the list, which is exactly how a sign-in fails with "no internet connection"
  on a working connection. The value comes from the `CLIENT_ORIGINS` repo
  variable on **every** backend deploy, so a `gcloud run services update` is a
  temporary override; and `--update-env-vars` replaces the variable rather than
  appending, so a per-app one-liner locks out every other app.
- **Secret management** — `scripts/setup-secrets.sh` + `docs/secrets.md`; repo
  holds names only, values go straight to Secret Manager.
- **IaC** — `terraform/` skeleton (Cloud SQL, Secret Manager, GCS, Cloud Run).
  Not yet `terraform validate`d (no toolchain here) — review before apply.
- **Mobile store release** — `docs/app-store-release-readiness.md` is the
  checklist of what has to be true before either Expo app can be submitted, and
  `docs/deploy-mobile-eas.md` is the mechanics for once it is. Both apps now
  carry a committed `eas.json` (three profiles, `API_BASE_URL` per profile,
  Maps key from an EAS secret), store-valid PNG icons, and **Expo SDK 57** —
  Play has required **API 36** since 31 Aug 2026 and SDK 51 targeted 34, so
  nothing from those repos could be uploaded at all. Both apps therefore now run
  on the **New Architecture**, which nothing short of a handset can verify.
  **A build is not the same as a submission.** What still blocks it is almost
  all yours: no SMS provider, so nobody — customer or App Store reviewer — can
  sign in to a production backend; no square app icon; no store accounts; no
  device testing; and the legal documents below still need a lawyer. Account
  deletion (Apple 5.1.1(v)) is built.
- **Drivers now get the customer's real phone number** (owner decision). The
  privacy notice said "A driver is never given your phone number" in as many
  words; that is no longer true, so `legal/privacy.html` and the customer app's
  `LegalScreen` were both corrected — those two are maintained by hand and must
  change together. The number is shown only while the
  delivery is in progress and withheld again once it closes — finished jobs stay
  visible in the driver app, so a number that outlived the drop would have made
  every past customer one tap from being dialled. `docs/legal-handover.md` §4b
  is the brief for the lawyer.
- **Legal pages** — `legal/` is the privacy notice and terms as deployable
  static HTML, English + Arabic in one document each (a store listing carries
  one privacy URL, and a customer landing on the wrong language must not have to
  hunt for the other). Structured against the **Saudi PDPL**: controller
  identity, legal basis per purpose, recipients, transfers outside the Kingdom,
  a retention table, data-subject rights with the 30-day response, breach
  notification, and the route to complain to SDAIA. `docs/legal-pages.md`
  deploys it; **`docs/legal-handover.md` is the brief for the lawyer** and lists
  every blank and who answers it.
  Facts only the restaurant, its accountant or its lawyer can supply are written
  as `[[ BLANKS ]]`; `legal.js` highlights each one and prints a red DRAFT
  banner counting them, so the pages **cannot be published half-finished without
  it being obvious**. Do not delete the draft notice at the top of either page
  to make it look finished — that line goes when a lawyer has adopted the text,
  and not before. `customer-app`'s `LegalScreen` is the plain-language summary
  of the same facts and says so on the page; the two are maintained by hand and
  **must change together**, because the customer reads one and a regulator reads
  the other.
  **One finding worth surfacing here:** the deployed API runs in Google Cloud
  `me-central2`, which is **Doha, Qatar** — not the `me-central2` (Dammam)
  region `terraform/variables.tf` names. Saudi customers' personal data is
  therefore being processed outside the Kingdom, which the PDPL and the transfer
  regulation govern. Either move the service or establish and disclose the
  transfer basis; see `legal-handover.md` §4.
- **Store listing copy** — `docs/store-listing-copy.md`: names, descriptions
  (EN + AR), keywords, and the Apple/Play privacy declarations read off the
  code rather than assumed. Two things in it are decisions, not drafts: the
  card-payment line must come out of the description if the first release is
  cash-only, and the **App Review demo account has no clean answer** while
  sign-in is OTP-only — the pinned demo code cannot be it.

Still needs client input to actually stand up: GCP project + billing, Cloud SQL
instance, a domain + DNS + SSL, and the notification channel for alerts. Real
secrets (Tap, SMS, push, Maps, DB) arrive via secret management on the day.

Production is Phase 20 — gated on explicit client approval.
