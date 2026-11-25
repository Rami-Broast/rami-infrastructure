# Getting `customer-app` and `driver-app` into the App Store and Google Play

> **Update, 6 September 2026.** B3, B4, B5 and B7 are **done**, and B2 and B6
> are done on the engineering side. What remains is almost entirely yours:
> B1 (SMS provider), B8 (rotate the Maps key), B10 (store accounts),
> B11 (driver distribution), B12 (device testing), the artwork for B4, and a
> lawyer for B6. Each section below carries its own status line.
>
> One correction worth reading: **B5 was wrong, in the direction that matters.**

**Status as of 6 September 2026: not submittable.** Not "needs polish" —
several items below are automatic rejections, and two mean a binary cannot be
produced at all today.

This document is the *readiness checklist*. The mechanics of building and
submitting once these are cleared already live in
[`deploy-mobile-eas.md`](./deploy-mobile-eas.md); this page is what has to be
true **before** those commands are worth running.

Everything marked ✅ VERIFIED was checked against the actual files in the repos,
not assumed. Everything marked ⚠️ VERIFY is a moving external requirement that
must be re-checked against the current store policy before you plan around it.

---

## 1. The blockers, shortest path first

| # | Blocker | Apps | Whose job | Blocks |
| --- | --- | --- | --- | --- |
| B1 | No SMS provider — **nobody can sign in**, including App Review | customer | **You** (decision) | Both stores |
| ~~B2~~ | ~~No in-app account deletion~~ — **built**; the retention *period* is still yours | customer | **You** (retention period) | ✅ code |
| ~~B3~~ | ~~No `eas.json` in either app~~ — **done**, three profiles committed | both | Engineering | ✅ |
| B4 | App icon — format **fixed**; still a wordmark in a square, needs a real square mark | both | **You** (artwork) | Apple, quality |
| ~~B5~~ | ~~Expo SDK 51 targets Android API 34~~ — **done**, both apps on SDK 57; Play now requires **API 36**, not 35 | both | Engineering | ✅ |
| B6 | Privacy policy / terms — **written and deployable** (`infrastructure/legal/`); needs a lawyer and a URL | both | **You** (legal review) | Both stores |
| ~~B7~~ | ~~Version `0.1.0`~~ — **done**, `1.0.0` with EAS-managed build numbers | both | Engineering | ✅ |
| B8 | Google Maps keys empty; previously-committed key never rotated | both | **You** (GCP console) | Function + security |
| B9 | Tap payments not implemented (adapter is a stub that throws) | customer | **You** (merchant account) | Launch, not submission |
| B10 | Store accounts do not exist (Apple, Google, Expo) | both | **You** | Everything |
| B11 | Driver app has no public sign-up | driver | **You** (distribution choice) | Apple 4.2 risk |
| B12 | Neither app has ever run on a physical device | both | Engineering + you | Quality |

Four of these are decisions only you can make (B1, B6, B10, B11) and they gate
most of the engineering work. **B1 is the one to answer first** — it unblocks
three other items and it has been the outstanding decision for some time.

---

## 2. Each blocker, in detail

### B1 — No SMS provider: sign-in is impossible ✅ VERIFIED

`SmsProvider` in `backend/src/config/env.validation.ts` has exactly one value,
`mock`, and the mock adapter delivers nothing. Customer authentication is
**OTP-only** — there is no password path.

The `123456` demo shortcut comes from `OTP_DEMO_FIXED_CODE`, and
`assertProductionPaymentRails`/`resolveDemoFixedCode` in
`backend/src/config/configuration.ts` **refuse to boot** with it set when
`NODE_ENV=production`. That guard is correct and must not be relaxed. The
consequence is exact: against a production backend, **no customer and no App
Store reviewer can log in.**

Apple and Google both sign in to the app during review. An app they cannot get
past the first screen of is rejected under Apple 2.1 (App Completeness) and
Play's equivalent.

**What to do**

1. Choose a provider with a **Saudi-registered sender ID** — SMS to KSA numbers
   without one is unreliable or blocked. Candidates commonly used in the region:
   Unifonic, Taqnyat, Msegat; Twilio works but sender-ID registration in KSA is
   the harder part with a non-local vendor. *We have not evaluated pricing or
   deliverability for you — that is a commercial call.*
2. Register the sender ID with the CITC. **Lead time is weeks, not days.** Start
   this before anything else on this page.
3. Engineering then: add the value to the `SmsProvider` enum, write the adapter
   behind the existing `SMS_SENDER` port, and add the matching production boot
   guard — there is already a comment in `configuration.ts` saying exactly where
   it goes and why it was deliberately left out.

**Do not** ship a build with the demo OTP enabled as a workaround. Two API calls
would then sign anyone in as any phone number.

---

### B2 — No account deletion — ✅ **DONE (engineering)**

> `DELETE /customer/me` anonymises and deactivates; the customer app has a
> Delete screen stating what is erased and what the restaurant keeps. See
> `backend/src/customers/README.md`. **Still yours:** the retention period —
> how long the anonymised record and the order rows are kept — which is an
> accountant's answer against Saudi tax-record rules, and which must match what
> the published privacy notice says.



Apple **App Store Review Guideline 5.1.1(v)**: an app that supports account
creation must let the user initiate account deletion **from inside the app**.
This is not negotiable and it is checked in review.

`backend/src/customers/customer-profile.controller.ts` exposes `GET` and `PATCH`
on `/customer/me`. There is **no `DELETE`** anywhere in the customer surface,
and no delete affordance in the app's Account screen.

**This is not a small change, and the reason matters.** In
`backend/prisma/schema.prisma`, `Order.customerId` is `onDelete: Restrict`, as
are `CouponUsage` and `LoyaltyTransaction`. A customer with orders **cannot** be
row-deleted, and should not be: those orders are the restaurant's sales and VAT
records, which it is legally required to retain.

So "delete my account" has to mean **anonymise and deactivate**, not erase:

- Clear `fullName`, `email`, and every `CustomerAddress`.
- Replace `phone` with a non-reusable placeholder. It is `@unique`, so it must
  be released or the same person can never sign up again — and it must not
  collide with a real number.
- Set `deletedAt`, `isActive = false`, and revoke every refresh-token family.
- **Leave `Order` rows intact.** Their price snapshots and the reports built
  from them must not change.

**Decision needed from you:** how long before the anonymised record is purged,
and what the retention period is for the order rows. That is a question for your
accountant against Saudi tax-record rules — do not let engineering guess it, and
whatever you decide has to match what the privacy notice says (B6).

The app also has to tell the customer, before they confirm, that their past
orders remain as the restaurant's sales records. Saying "everything is deleted"
when it is not is the kind of statement a regulator reads literally.

---

### B3 — No build configuration — ✅ **DONE**

> Both apps carry a committed `eas.json` with `development` / `preview` /
> `production` profiles. **Do not run `eas build:configure`** — it overwrites
> them. See `deploy-mobile-eas.md`.



Neither app has an `eas.json`, and neither has `ios/` or `android/`
directories. There are no build profiles, no credential configuration and no
submit configuration. **There is nothing to upload today.**

Engineering runs `eas build:configure` in each app and commits the result, with
at least three profiles: `development`, `preview` (internal device testing) and
`production`. See [`deploy-mobile-eas.md`](./deploy-mobile-eas.md).

---

### B4 — The app icon is a wide JPEG banner — ⚠️ **HALF DONE**

> The file structure is fixed: both apps now point at a 1024 × 1024 no-alpha
> PNG icon, a transparent Android adaptive foreground, a splash and a favicon,
> generated by `scripts/generate-icons.py`. That clears the upload rejection
> and **nothing else** — the current icon is the 4 : 1 wordmark letterboxed in a
> square, which is illegible at icon size. **Still yours:** the square brand
> mark, per the spec in each app's `assets/README.md`.



Both apps use `assets/logo.jpeg` — a **1600 × 384 JPEG** — as the app icon, the
splash image, the Android adaptive-icon foreground *and* the web favicon.

- Apple requires a **1024 × 1024 PNG** with **no alpha channel and no
  transparency**. A JPEG fails App Store Connect validation outright.
- A 4 : 1 wordmark is not an icon at any size; on a home screen it will be
  letterboxed into an unreadable strip.
- The Android adaptive-icon foreground needs to be a **PNG with transparency**,
  drawn inside the safe zone (the outer ~33% gets masked away on many devices).

**What we need from you:** a square brand mark — not the wordmark — supplied as
a 1024 × 1024 PNG, plus a transparent-background version for the Android
foreground. Engineering can generate every derived size from those two, but
cannot invent the mark.

Splash and favicon should be revisited at the same time; a banner is fine for a
splash, but it should be a PNG sized for it.

---

### B5 — Expo SDK and the Play target-API requirement — ✅ **DONE, and the original assessment was wrong**

**This was the one item marked ⚠️ VERIFY, and verifying it changed the answer.**

The original text guessed API 35, minimum since 31 August 2025. The actual
requirement, read from
[Play's own page](https://developer.android.com/google/play/requirements/target-sdk):
since **31 August 2026** — five days before this was written — new apps and app
updates must target **API level 36 (Android 16)**. A level higher than assumed,
and freshly in force.

Both apps were on `expo ~51.0.28` / RN 0.74.5, which targets **API 34**. So this
was never "deferred, nice to have": no build from either repo could be uploaded
at all.

Both are now on **SDK 57** (RN 0.86.3, React 19.2), upgraded together. SDK 56
was skipped deliberately — it carries a Hermes V1 memory regression affecting
`react-native-reanimated` and `react-native-worklets`, which is exactly what
`customer-app` runs moti on.

**The consequence to carry forward: both apps now run on the New Architecture,
and there is no way back.** RN 0.82 removed the legacy architecture and SDK 55
dropped `newArchEnabled` from `app.json`. Every native module — maps, location,
secure store, the image picker, reanimated — goes through Fabric and
TurboModules now.

Typecheck, lint, all 268 tests across the two apps and both web bundles are
green. **None of that is evidence either app runs on a handset**, and after an
architecture change it is weaker evidence than usual. This makes B12 the gate
rather than a formality — see each app's `CLAUDE.md` for what to watch.

**Two things still worth doing in the Play Console:**

1. **Request the target-API extension to 1 November 2026** if it is still
   offered. It costs nothing and it is insurance against anything below taking
   longer than expected.
2. **Check whether the driver app is exempt.** Play excepts apps that are
   permanently private to a single organisation for internal distribution — the
   route B11 recommends anyway. Verify it in the Console rather than relying on
   this sentence.

### B6 — No published privacy policy or terms — ⚠️ **READY TO PUBLISH**

> `infrastructure/legal/` holds both documents as deployable static HTML,
> English and Arabic in one page each, with the retention wording updated to
> match what account deletion now actually does. See `legal-pages.md`.
> **Still yours:** a lawyer to adopt it (including the Arabic, which is a
> translation of unreviewed text), and a stable public URL to deploy it to.



Both stores require a **publicly reachable URL** for a privacy policy before a
listing can be submitted.

The customer app has `src/screens/LegalScreen.tsx`, which is a genuinely
accurate description of what the app does — but it states on the page that it is
*"the working version pending the restaurant's own legal review"*, and it exists
only inside the app. That line is there deliberately and **must not simply be
deleted to make this go away.**

**What to do**

1. Have the restaurant's lawyer review and adopt the text. It has to be the
   restaurant's own legal document; it names the restaurant as the data
   controller, not us.
2. Publish it, and the terms, at stable public URLs.
3. Make sure the policy matches the retention answer from B2 and the data list
   below (B-privacy). A policy that contradicts what the app does is worse than
   no policy.
4. Arabic and English versions — the app ships bilingual and the customers are
   in Saudi Arabia.

---

### B7 — Versioning — ✅ **DONE**

> Both apps at `1.0.0` with `ios.buildNumber` / `android.versionCode` seeded and
> `appVersionSource: remote` + `autoIncrement` on the production profile, so
> EAS owns the build number. One detail the original text got wrong:
> `driver-app`'s `package.json` already said `1.0.0` — only its `app.json` said
> `0.1.0`, so the two files disagreed, which is its own upload hazard.



Both apps sit at `"version": "0.1.0"` with no `ios.buildNumber` and no
`android.versionCode`. Both stores require a version string and a
monotonically-increasing build number per upload.

Set `1.0.0` for the first release and let EAS manage auto-incrementing build
numbers (`"autoIncrement": true` in the production profile).

---

### B8 — Maps keys, and one that needs rotating ✅ VERIFIED

`expo.android.config.googleMaps.apiKey` and `expo.extra.googleMapsApiKey` are
**empty strings** in both apps. Without a key, the address picker, order
tracking and driver navigation degrade to a "map unavailable" card. They do not
crash — but a reviewer opening the tracking screen sees a broken-looking app.

Separately, and more urgently: **the customer app's Maps key was once committed
to `app.json` and is still in that repo's git history.** It has not been
rotated. Rotate it in the Google Cloud console, restrict the replacement by
bundle ID / package name and by API, and set it through an EAS secret. See
[`google-maps-keys.md`](./google-maps-keys.md).

---

### B9 — Payments ✅ VERIFIED

`TapPaymentGateway` is a deliberate stub that throws; the working adapter is
`MockPaymentGateway`. Cash on delivery works today (per-branch opt-in); card
does not.

Two things worth being clear about:

- **This is not an in-app-purchase problem.** Apple's IAP requirement does not
  apply to physical goods and services delivered in the real world (Guideline
  3.1.3(e) / 3.1.5(a)), so taking card payment through Tap is correct and
  permitted. Don't let anyone tell you food delivery needs IAP.
- It *is* a launch blocker but arguably **not a submission blocker**: you could
  submit a first version that is cash-on-delivery only, and add card payment in
  1.1. Whether that is a good idea is a business call. If you do, the store
  listing must not advertise card payment.

To implement it we need the **Tap merchant account, official API documentation
and sandbox credentials**. Nothing about Tap's API may be guessed — that rule is
in `backend/CLAUDE.md` and it stands.

---

### B10 — Accounts you do not yet have

| Account | Cost | Lead time | Notes |
| --- | --- | --- | --- |
| Expo / EAS | free tier | minutes | Build service |
| Apple Developer Program (Organization) | US$99/yr | **1–3 weeks** | Requires a **D-U-N-S number** for a company; getting one is itself 1–2 weeks and free |
| Google Play Developer | US$25 once | days–weeks | Organisation accounts require identity/business verification ⚠️ VERIFY current KSA requirements |

Enrol as the **restaurant company**, not as an individual. Transferring an app
from a personal account to a company account later is possible but tedious, and
an individual-owned listing for a commercial restaurant looks wrong to reviewers
and to customers.

**Start the D-U-N-S application now.** It is free, it is slow, and nothing about
Apple can begin without it.

---

### B11 — How the driver app should be distributed ✅ VERIFIED (design), decision needed

`driver-app` has **no public sign-up**. Drivers are created by the owner in the
admin panel, and they sign in with credentials handed to them. There is no way
for a member of the public to use the app.

Apple routinely rejects apps like this from the public App Store under
Guideline 4.2 (Minimum Functionality) / 4.3, on the grounds that it is not
useful to general users. Publishing it publicly is the **worst** option, and it
is what most teams try first.

Better routes, pick one:

- **Apple Business Manager — Custom Apps.** Distribute privately to your own
  organisation. This is the intended mechanism and the one to choose.
- **TestFlight.** Fine while you have few drivers; 90-day build expiry means
  re-uploading regularly. Good for the pilot, poor as a permanent answer.
- **Play Console — internal or closed testing track**, or an unlisted release.

The customer app goes to the public stores; the driver app almost certainly
should not. **Decide this before creating the listings**, because it changes what
you fill in.

---

### B12 — No device testing has happened

Every test in these repos is jest/vitest running in Node. That is 211 tests in
the customer app and a similar suite in the driver app, and they are worth
having — but **not one of them has run on an iPhone or an Android handset.**

Things that only break on a real device, all of which exist in these apps:
Keychain/Keystore token persistence, location permission dialogs, the camera
roll for proof-of-delivery photos, Google Maps rendering, deep links
(`ramibroast://`), background/foreground transitions, and the notch/safe-area
layout.

Do this with an `eas build --profile preview` internal build against the live
backend, on at least one iPhone and one mid-range Android, before submitting
anything. Walk a whole order through: sign in → browse → cart → checkout →
place → track → driver picks up → delivered.

---

## 3. Store listing material we do not have

None of this is code. All of it is required before a listing can go live, and it
is usually what actually delays a submission.

**Per app, per store:**

- App name (30 chars, Apple) and subtitle
- Short description (80 chars) and full description (4000 chars) — **in Arabic
  and English**
- Keywords (Apple, 100 chars)
- **Screenshots**: iPhone 6.7" and 6.5" at minimum; Android phone; and iPad if
  you keep `supportsTablet: true` (either produce iPad screenshots or set it to
  `false` — Apple checks)
- Feature graphic 1024 × 500 (Play)
- Support URL, marketing URL, support email
- Age rating questionnaire (both stores)
- Export compliance answer (HTTPS-only usually qualifies for the standard
  exemption, but the question must be answered)
- App Review demo account + notes. **With OTP-only auth this is a genuine
  problem** — see B1. You will need a reviewer test number that can receive a
  real code, or a documented reviewer path agreed with engineering that does not
  reintroduce the demo-OTP hole.

**Privacy declarations** — Apple "App Privacy" labels and Play "Data safety".
Both must match what the apps actually do. From reading the code, the truthful
answers are:

| Data | Collected | Linked to identity | Purpose |
| --- | --- | --- | --- |
| Phone number | Yes | Yes | Sign-in, contacting about an order |
| Name | Optional | Yes | So the branch and driver know who the order is for |
| Precise location | Yes | Yes | Delivery address and fee; driver position during a delivery |
| Purchase history | Yes | Yes | The restaurant's record of a sale |
| Payment info | **No** | — | Card details never reach our systems |

The driver app collects **precise location in the foreground only, and only
between pickup and drop-off** (`driver-app/src/delivery/location-sharing.ts`).
Say exactly that. Play requires a **location-permission declaration and often a
short demo video** for apps requesting location; claiming background location
you do not use will fail review, and understating it is worse.

---

## 4. Sequence

Phases overlap; the point is what blocks what.

**Phase 0 — start today, all waiting-time (you)**
- Apply for a D-U-N-S number.
- Choose the SMS provider and start the Saudi sender-ID registration (B1).
- Send the privacy policy and terms to the lawyer (B6).
- Commission the square app icon (B4).
- Decide how the driver app is distributed (B11).

**Phase 1 — engineering, unblocked today**
- `eas.json` in both apps (B3).
- Versioning (B7).
- Icon pipeline, ready for the artwork when it lands (B4).
- Expo SDK upgrade, both apps together (B5).
- Account deletion: endpoint + anonymisation + the Account screen flow (B2) —
  *needs your retention answer first.*

**Phase 2 — once accounts and credentials exist**
- Maps keys rotated, restricted and wired in (B8).
- Real SMS adapter + the production boot guard (B1).
- First `preview` build; device testing (B12).

**Phase 3 — submission**
- Store listings, screenshots, privacy declarations (§3).
- Internal testing track / TestFlight.
- Submit the customer app publicly; the driver app privately.

**Phase 4 — after first release**
- Tap adapter, once the merchant account and official docs exist (B9).

---

## 5. How long

An honest estimate, with the assumptions stated so you can challenge them.

| | |
| --- | --- |
| Engineering work | **1.5–2.5 weeks** (eas.json, versioning, icons, SDK upgrade, account deletion, SMS adapter, device fixes) |
| Waiting on external parties | **3–6 weeks** (D-U-N-S, Apple enrolment, CITC sender-ID registration, legal review) — largely in parallel |
| Store review | **1–7 days** Apple, **hours–days** Play, **assume at least one rejection** |
| **Realistic first submission** | **4–8 weeks from today** |

The engineering is the small part. Almost all of the elapsed time is waiting on
things that cannot start until you start them — which is why Phase 0 is Phase 0.

---

## 6. What is *not* a blocker

Worth saying, so effort does not go to the wrong place:

- **The backend.** It is in good shape: 818 tests, server-side pricing, enforced
  branch isolation, idempotent money operations, promotions and coupons priced
  server-side.
- **App quality and logic.** Both apps have real test coverage, error boundaries
  outside the providers, honest empty and error states, and no white-screen
  paths that we know of.
- **In-app purchase.** Does not apply — see B9.
- **The admin app and Branch POS.** Web apps on Vercel; nothing store-related
  touches them.

---

## 7. Recommendation

Do not aim the client demo at a store release. The **web builds already on
Vercel** demonstrate the entire platform today and need none of the above. Use
them for the demo, and treat the store submission as a separate project whose
first step is a single decision: **which SMS provider.**

Until that is answered, nobody — customer, owner or App Store reviewer — can log
into the production customer app at all.
