# Deploy the Branch POS (`kitchen-pos`)

`kitchen-pos` is a Vite + React SPA — the **front-of-house POS** that runs in a
browser on each branch's counter machine. Staff work incoming orders, take
counter (walk-in / phone) orders, watch their branch's deliveries, and print
kitchen tickets to the thermal printer wired to that machine.

Two things make its deploy different from the admin app:

- **It is per-branch, but the build is not.** Every branch signs in with its own
  owner-created credentials, and the backend scopes everything to that branch.
  There is nothing branch-specific to bake into the build — you ship **one**
  build and every branch loads the same URL and signs in.
- **The printer lives on the machine, not in the cloud.** The printer model +
  connection (and the QZ Tray client, for real printing) are configured **on
  each counter machine** in the app's Print settings and stored in that
  machine's `localStorage`. None of that is part of this deploy. See
  `kitchen-pos/CLAUDE.md` and the app's Print settings tab.

No Google Maps key is needed here — the POS has no map.

> Deploy the **backend first** (`deploy-backend-gcp.md`) so you have an API URL
> to point at. A live POS with no backend renders the sign-in screen but can't
> sign in.

## Environment variables

Vite inlines `VITE_*` at **build time**, so set this before building (or in the
host's project settings) and **rebuild/redeploy** after any change.

| Variable | Value |
| --- | --- |
| `VITE_API_BASE_URL` | Your Cloud Run URL + `/api/v1`, e.g. `https://rami-api-xxxx.a.run.app/api/v1` |

## Option A — host it as a static site (recommended)

The POS is a static SPA; host it anywhere that serves static files (Vercel,
Netlify, a GCS bucket + CDN, an nginx box). Each branch counter machine opens
the URL in its browser.

Vercel example (mirrors the admin app):

1. Vercel → **Add New → Project → Import** the `Rami-Broast/kitchen-pos` repo.
2. Framework preset: **Vite** (auto-detected). Build command `npm run build`,
   output `dist`.
3. Add `VITE_API_BASE_URL`.
4. Deploy. Every push to `main` then redeploys automatically.

Add an SPA rewrite if the host needs one (serve `index.html` for unknown
paths); the app is a single page.

## Option B — build and serve on the branch machine

If a branch runs offline-ish or you prefer no external hosting, build once and
serve the `dist/` folder from the counter machine (or a small on-site box):

```bash
cd kitchen-pos
npm ci
VITE_API_BASE_URL="https://<api-host>/api/v1" npm run build   # emits dist/
npx serve dist      # or any static file server, e.g. nginx pointing at dist/
```

The QZ Tray client (for real thermal printing) is installed **per machine**
separately — it is not part of this build. Until it is set up, the app's default
preview/mock printer shows the ticket on screen.

## After deploy — allow the origin on the backend

The POS calls the API from the browser, so its origin must be in the backend's
CORS allow-list. Update the Cloud Run service (append to any existing origins):

```bash
gcloud run services update rami-api --region $REGION \
  --update-env-vars "CORS_ALLOWED_ORIGINS=<every origin from client-origins-and-cors.md>"
```

If each branch serves the POS from its own on-site origin (Option B), add each
of those origins here too.

## Custom domain (optional)

Point e.g. `pos.ramibroast.com` at the host, then add that origin to the backend
CORS list above. No Maps referrer list to update — the POS uses no maps.
