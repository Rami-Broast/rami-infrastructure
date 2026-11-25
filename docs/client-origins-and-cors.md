# Client origins and CORS

Four of our clients run **in a browser** and therefore need their origin in the
backend's CORS allow-list. A request from an origin that is not on the list is
refused by the browser before it reaches a route, and — this is the part that
costs a day — `fetch` reports it as an ordinary network failure with no reason
attached. The app cannot tell it apart from a flat battery.

This page is the single source of truth for that list. Read it before adding a
client, a preview URL or a custom domain.

## The list

These are the **actual** demo origins, not placeholders. They are written out
in full so the complete line can be copied rather than reconstructed from
memory, which is how one gets left out:

| Client | Runs in a browser? | Origin |
| --- | --- | --- |
| `admin-app` | Yes — Vite SPA on Vercel | `https://rami-admin.vercel.app` (later `https://admin.ramibroast.com`) |
| `kitchen-pos` | Yes — Vite SPA, one build per branch | `https://rami-pos.vercel.app` (later `https://pos.ramibroast.com`) |
| `customer-app` | **Yes, on the Vercel web build** | `https://rami-customer.vercel.app` |
| `driver-app` | **Yes, on the Vercel web build** | `https://rami-driver.vercel.app` |
| local development | Yes | `http://localhost:5173` |

The last two are the ones that get forgotten. `driver-app` **was** forgotten:
the list deployed on 2026-09-06 named the admin, POS and customer origins and
localhost, and drivers signing in on the Vercel build got "Your device is
online but the app could not reach the server" on a working connection —
because that is the only thing the app can honestly say when a browser refuses
to tell it why the request failed.

They get forgotten because they are Expo apps and so read as "mobile" — but
each carries a `vercel.json` and is deployed as a web build for the demo, and
in a browser they are subject to CORS exactly like the SPAs. A native build
(Expo Go, a dev client, EAS/TestFlight) is **not** subject to CORS and needs
nothing here.

**Production origins only, by decision.** Preview deployments each get their
own hostname, so a feature branch's build is a different origin and is refused
by this list. That is accepted: signing in on a preview build will not work
unless you add that specific hostname. Widening the list to a wildcard or a
preview-matching pattern is a real loosening on a service that issues sessions,
and nobody has asked for it.

## Where the value actually comes from

`CORS_ALLOWED_ORIGINS` on the Cloud Run service, set on **every backend deploy**
from the `CLIENT_ORIGINS` GitHub repository variable:

```
backend/.github/workflows/deploy.yml   → CORS_ALLOWED_ORIGINS=${{ vars.CLIENT_ORIGINS }}
```

So the repo variable is the source of truth, and **a `gcloud run services
update` is a temporary override that the next backend deploy silently
reverts.** Change the variable, not the service, unless you need the fix live in
the next thirty seconds — in which case do both.

Set it at **Settings → Secrets and variables → Actions → Variables** on
`Rami-Broast/backend`, as one comma-separated line with no spaces:

```
https://rami-admin.vercel.app,https://rami-pos.vercel.app,https://rami-customer.vercel.app,https://rami-driver.vercel.app,http://localhost:5173
```

Then re-run the backend deploy workflow so Cloud Run picks it up.

## The deploy checks this now

`backend/.github/workflows/deploy.yml` ends with **Verify CORS allows every
configured client origin**: after the rollout it sends a real preflight from
each origin in `CLIENT_ORIGINS` and fails the job, naming the origin, if any is
refused. It also fails on an empty variable.

What it **cannot** catch is an origin nobody put in the variable in the first
place — a passing check means "everything listed works", never "everything that
needs to be listed is". That is what the table above is for. When a new browser
client or a custom domain appears, add it here **and** to the variable.

## Two ways this list gets quietly emptied

**`--update-env-vars` replaces the whole variable, it does not append.** Running
the one-liner from `deploy-admin-vercel.md` and then the one from
`deploy-kitchen-pos.md` leaves you with only the POS origins and an admin app
that can no longer sign in. Always pass the complete list.

**An empty list allows nothing.** `bootstrap.ts` only calls `enableCors` when
the list is non-empty — the correct default for a native-only deployment, and a
total browser blackout for this one. If `CLIENT_ORIGINS` is unset, every browser
client fails at once.

## Confirming a CORS block

The browser refuses to tell JavaScript why a request failed, but it always tells
the **console**. Open the failing app, DevTools → Console, and try the action:

- `Access to fetch at '…' from origin '…' has been blocked by CORS policy` —
  this page is the fix. Note the origin it prints; that exact string is what
  goes in the list.
- `net::ERR_NAME_NOT_RESOLVED` / `ERR_CONNECTION_REFUSED` — not CORS. The API
  URL is wrong or the service is down.
- A `401` or a `4xx` with a JSON body — not CORS either. The request reached a
  route; this is credentials or validation.

The Network tab is the other half: a CORS-blocked request shows the preflight
`OPTIONS` (or the request itself) with **no response headers** and status
`(failed)`, while a genuine outage shows nothing leaving at all.
