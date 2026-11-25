# Google Maps API keys — how to get them and where they go

The platform uses Google Maps in three places, and Google treats them as
**three different products**, each needing its own API enabled:

| Where | Google product to enable | Used by |
| --- | --- | --- |
| Admin web dashboard (delivery board map) | **Maps JavaScript API** | `admin-app` (browser) |
| Customer app map (address pin, live tracking) | **Maps SDK for Android** + **Maps SDK for iOS** | `customer-app` |
| Driver app map (navigation, live position) | **Maps SDK for Android** + **Maps SDK for iOS** | `driver-app` |

You can put all of these under **one Google Cloud project** — the same project
you deploy the backend into, which keeps billing and keys in one place.

> **A Maps key is not really a secret, and that changes what protects it.**
>
> A mobile Maps key ships inside the APK; a browser key ships in the JS bundle.
> Anyone can extract either. Google's own guidance accepts this — what stops
> someone else using your key is not secrecy, it is **application restrictions**
> (package name + signing fingerprint, bundle id, or HTTP referrer) plus **API
> restrictions**. An unrestricted key is abusable whether or not it ever
> appeared in a repository.
>
> Keys still never get committed — a repository is read by a different set of
> people than an app binary, git history is permanent, and a committed key is
> one nobody remembers to rotate. But treat **Step 3 (restrictions) as the
> security control** and keeping it out of git as hygiene, not the other way
> round. Every app repo contains an **empty** placeholder and takes the real
> value from the environment at build time.

---

## Step 1 — create / pick a Google Cloud project

1. Go to <https://console.cloud.google.com/>.
2. Top bar → project picker → **New Project** (or reuse the one you deploy the
   backend into). Name it e.g. `rami-broast`.
3. **Enable billing** on the project (Maps requires a billing account; Google
   gives a recurring free tier that is generous for a single restaurant).

## Step 2 — enable the APIs

Console → **APIs & Services → Library**, search and **Enable** each:

- **Maps JavaScript API** (for the admin web dashboard)
- **Maps SDK for Android** (for the two mobile apps)
- **Maps SDK for iOS** (for the two mobile apps)

Or with the `gcloud` CLI:

```bash
gcloud services enable \
  maps-backend.googleapis.com \
  maps-android-backend.googleapis.com \
  maps-ios-backend.googleapis.com \
  --project rami-broast
```

## Step 3 — create the keys, and restrict every one

Console → **APIs & Services → Credentials → Create credentials → API key**.

Separate keys per platform, because the restriction *types* are mutually
exclusive: a key restricted to HTTP referrers cannot also be restricted to an
Android package. One key covering everything would have to be unrestricted,
which is the thing to avoid.

**`kitchen-pos` needs no key** — the Branch POS uses no maps.

### Key A — web (admin dashboard)

1. Create the key, rename it `maps-web-admin`.
2. **Application restrictions → Websites (HTTP referrers).** Add your admin
   domains, e.g.:
   - `https://admin.ramibroast.com/*` (your custom domain, once set)
   - `https://<your-vercel-project>.vercel.app/*` (the Vercel URL)
   - `http://localhost:5173/*` (local dev)
3. **API restrictions → Restrict key → Maps JavaScript API.**

### Key B — Android (customer + driver apps)

1. Create the key, rename it `maps-android`.
2. **Application restrictions → Android apps.** Add a package + SHA-1 pair for
   each app:
   - `com.ramibroast.driver` + its signing SHA-1
   - `com.ramibroast.customer` + its signing SHA-1

   One key can carry both pairs. Two separate keys are better if you want
   independent quotas and blast radius; one is fine to start.

   Get the fingerprint with `eas credentials` (EAS-managed signing) or
   `keytool -list -v -keystore <your.keystore>`. **Debug and release builds are
   signed differently** — add the debug SHA-1 too, or maps will work in
   production and be blank on your own machine.
3. **API restrictions →** Maps SDK for Android.

### Key C — iOS (optional)

1. Create the key, rename it `maps-ios`.
2. **Application restrictions → iOS apps** → bundle IDs
   `com.ramibroast.driver`, `com.ramibroast.customer`.
3. **API restrictions →** Maps SDK for iOS.

Optional because `AppMap.tsx` uses Google on iOS only when a key is present and
otherwise falls back to **Apple Maps**, which needs no key and works fine. Add
this key only if you want the two platforms to look identical.

> Restricting keys is not optional. An unrestricted browser key is visible in
> the shipped JS bundle and can be scraped and abused against your billing.

## Step 4 — put each key where it belongs

| Key | Goes into | How |
| --- | --- | --- |
| `maps-web-admin` | Vercel env var `VITE_GOOGLE_MAPS_API_KEY` | Vercel dashboard → Project → Settings → Environment Variables. See `deploy-admin-vercel.md`. |
| `maps-android` | `customer-app` / `driver-app` | EAS secret / env var **`GOOGLE_MAPS_API_KEY`**. `app.config.js` injects it; `app.json` stays empty. See "How the mobile apps actually read the key" below. |
| `maps-ios` | same | same variable — set it in the iOS build profile if you use a separate iOS key. |

After setting the web key in Vercel, **redeploy** the admin app so the new env
var is baked into the build (Vite inlines `VITE_*` at build time).

## Cost control (do this once)

- Console → **Billing → Budgets & alerts** → set a budget + email alert.
- Also set a **per-key quota**: APIs & Services → the API → Quotas. A budget
  alert tells you after the money is spent; a quota stops it being spent.
- The keys are restricted (Step 3), so usage is bounded to your own apps.

---

## Rotating a key that has been exposed

A live key was committed to **`driver-app/app.json`** (commit `ed4023f`) and to
**`customer-app/app.json`** (commit `cbdaf7e`), and is still readable in the
history of both. Removing it from the current file does not un-expose it —
`git show <commit>:app.json` returns it to anyone with the repo.

The `customer-app` copy was found on 2026-09-04, three weeks after the audit
recorded this as a `driver-app`-only problem. It had been sitting on `main` in
the *current* file the whole time, in two places, directly beneath a comment
reading "Never commit a real key". Two independent commits placing the same
key in two repositories is the signature of a key being pasted wherever it was
needed — so **before closing this out, sweep every repository** (the loop in
step 5 does it) rather than trusting any list, this one included.

**Do these in order. The order matters:** rotating first closes the exposure,
so a history rewrite afterwards is tidying rather than a race.

### 1. Check whether the exposed key was restricted — this sets the urgency

Console → **APIs & Services → Credentials** → open the key.

- **Application restrictions set** (Android apps / iOS apps / HTTP referrers)
  **and** API restrictions set → someone with the key cannot easily use it.
  Rotate as hygiene, not as an emergency.
- **"None" under application restrictions** → the key is usable by anyone for
  any enabled API, and has been for as long as it was in the repo. Rotate now
  and check the usage graphs (APIs & Services → Metrics) for traffic you do
  not recognise.

As of the last check, `maps-mobile` had API restrictions but **no application
restriction**, which is the second case: rotate now. Separately, the
`Maps Platform API Key` in the same project is restricted to **35 APIs** behind
only an HTTP-referrer restriction — narrow it to **Maps JavaScript API** only.
A referrer restriction is trivially forgeable outside a browser, so the API
list is doing most of the work there, and 35 APIs is not a list.

### 2. Regenerate

On the key's page, **Regenerate key**. This issues a new string and
**invalidates the old one immediately** — which is the point, and also means
any build still carrying the old key stops showing maps until it is rebuilt.

Prefer *regenerate* over *delete and create*: it keeps the key's name,
restrictions and API list intact, so there is nothing to re-apply.

### 3. Restrict the replacement before it goes anywhere

Follow Step 3 above. For the mobile key that means package name **and** SHA-1
fingerprint — the package name alone is not a restriction, since anyone can
build an app claiming to be `com.ramibroast.driver`.

### 4. Put it in the environment, never the file

See the table in Step 4. Nothing goes back into `app.json`.

### 5. Purge the key from git history *(optional, after step 2)*

Once the old key is dead this is cleanup, not containment. It is still worth
doing so a future audit does not re-flag it, and so nobody copies it out of
history believing it works.

**Two repositories, not one.** The same key was committed to **`driver-app`**
(`ed4023f`) and to **`customer-app`** (`cbdaf7e`). Run this for both. Confirm
the list before you start, rather than trusting this document:

```bash
for repo in driver-app customer-app admin-app kitchen-pos backend infrastructure; do
  git -C "$repo" log --all -S'AIzaSy' --oneline | sed "s|^|$repo |"
done
```

```bash
# In a fresh MIRROR clone. This rewrites every commit — coordinate first.
git clone --mirror git@github.com:Rami-Broast/<repo>.git
cd <repo>.git

# The key itself never goes in this file. Read it from the environment, so the
# runbook does not become the next place the secret is published — which is
# exactly what happened to an earlier revision of this page.
printf '%s==>REDACTED\n' "$OLD_MAPS_KEY" > /tmp/redact.txt
git filter-repo --replace-text /tmp/redact.txt
shred -u /tmp/redact.txt

git push --force --all && git push --force --tags
```

**Branch tips carry it too.** A mirror rewrite covers every ref, which is the
point of `--mirror` — but check afterwards that nothing reintroduces it, and
delete stale branches rather than rebasing them where nobody needs them. As of
2026-09-04 five open `customer-app` branches still had the key in `app.json`
at their tip:

```bash
git for-each-ref --format='%(refname:short)' refs/remotes/origin |
  xargs -I{} sh -c 'git grep -l AIzaSy {} -- 2>/dev/null'
```

**Everyone with a clone must re-clone afterwards.** Old clones still contain the
old history and will fight the rewrite on their next push. Open branches need
rebasing onto the rewritten history.

### 6. Stop the next one at the door

GitHub → repository **Settings → Code security** → enable **Secret scanning**
and **Push protection**. Push protection blocks a commit containing a
recognised credential *before* it lands, which is the only control here that
does not depend on someone remembering.

---

## How the mobile apps actually read the key

`customer-app` and `driver-app` each have an `app.config.js` that extends
`app.json` at build time:

```js
const mapsApiKey = process.env.GOOGLE_MAPS_API_KEY ?? '';
// injected into android.config.googleMaps, ios.config, and extra
```

So the key is supplied as the environment variable **`GOOGLE_MAPS_API_KEY`**:

```bash
# local development
GOOGLE_MAPS_API_KEY=AIza... npx expo start

# a real build
eas secret:create --scope project --name GOOGLE_MAPS_API_KEY --value AIza...
```

`app.json` keeps an empty string. Nothing needs editing to supply a key, and
there is no file for a key to be accidentally committed into.

**A missing key is not fatal**, by design:

| App | No key | Consequence |
| --- | --- | --- |
| `driver-app` (Android) | Google map does not render | navigation map shows "map unavailable"; the delivery flow still works |
| `customer-app` (iOS) | falls back to **Apple Maps** | fully functional — an iOS key is genuinely optional |
| `customer-app` (Android) | Google map does not render | address pin + tracking degrade to the fallback card |
| `admin-app` | `MapPanel` renders an explainer | Live Ops and Deliveries lists work; only the map is missing |
| `kitchen-pos` | — | **uses no maps at all. It needs no key.** |
