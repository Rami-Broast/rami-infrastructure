# Deploy the admin app to Vercel

`admin-app` is a Vite + React SPA. Vercel auto-detects Vite; the only real work
is the two environment variables and the SPA rewrite (already committed as
`admin-app/vercel.json`).

> Deploy the **backend first** (`deploy-backend-gcp.md`) so you have an API URL
> to point at. A live admin app with no backend renders the login screen but
> can't sign in.

## Environment variables

Vercel → Project → **Settings → Environment Variables**. Add both, for
Production (and Preview if you use it):

| Variable | Value |
| --- | --- |
| `VITE_API_BASE_URL` | Your Cloud Run URL + `/api/v1`, e.g. `https://rami-api-xxxx.a.run.app/api/v1` |
| `VITE_GOOGLE_MAPS_API_KEY` | The `maps-web-admin` key from `google-maps-keys.md` |

Vite inlines `VITE_*` at **build time**, so after changing either value you must
**redeploy** (Deployments → ⋯ → Redeploy) for it to take effect.

## Option A — deploy from the Git repo (recommended, gives CI on every push)

1. Vercel → **Add New → Project → Import** the `Rami-Broast/admin-app` repo.
2. Framework preset: **Vite** (auto-detected). Build command `npm run build`,
   output `dist` — auto-filled.
3. Add the two env vars above.
4. Deploy. Every push to `main` then redeploys automatically.

## Option B — deploy the built output directly (no Git link)

```bash
cd admin-app
npm ci
npm run build           # emits dist/
npx vercel deploy --prod dist   # or: npx vercel --prod
```

## After deploy — allow the origin on the backend

The admin app calls the API from the browser, so its origin must be in the
backend's CORS allow-list. **See `client-origins-and-cors.md` — that page is the
source of truth and lists every origin.** Two things it will save you from:

- `--update-env-vars` **replaces** the whole variable rather than appending to
  it, so the command below with only the admin origins in it will lock out the
  POS and both Expo web builds.
- The value is reset from the `CLIENT_ORIGINS` repo variable on every backend
  deploy, so a `gcloud` change is a temporary override. Change the variable.

For a fix you need live in the next thirty seconds, pass the **complete** list:

```bash
gcloud run services update rami-api --region $REGION \
  --update-env-vars "CORS_ALLOWED_ORIGINS=<every origin from client-origins-and-cors.md>"
```

## Custom domain (optional)

Vercel → Project → **Settings → Domains** → add `admin.ramibroast.com` and
follow the DNS instructions. Then add that domain to both the Maps key referrer
list (`google-maps-keys.md`) and the backend CORS list above.
