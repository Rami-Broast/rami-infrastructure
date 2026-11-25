# Publishing the privacy policy and terms

Both stores require a **publicly reachable URL** for a privacy policy before a
listing can be submitted, and Apple's App Privacy answers have to match what the
policy says. `legal/` in this repo is that page, ready to deploy.

## What is here

| File | |
| --- | --- |
| `legal/privacy.html` | Privacy policy, English + Arabic in one document |
| `legal/terms.html` | Terms of service, English + Arabic in one document |
| `legal/index.html` | Links to both |
| `legal/legal.js` | Language toggle, and the DRAFT banner that counts unfilled blanks |
| `legal/style.css` | One stylesheet, no build step, no CDN |
| `legal/vercel.json` | `cleanUrls` so `/privacy` works as well as `/privacy.html` |

Each page carries both languages in one document with a toggle, rather than
sitting at two URLs. A store listing carries **one** privacy URL, and a customer
who lands on the wrong language must not have to go looking for the other. The
page follows the browser's language and falls back to English for anything that
is not Arabic — never to an empty page.

## Deploy

Static files, so anything that serves HTML will do. Vercel, matching how the
admin app and the Branch POS are already deployed:

```bash
cd legal
npx vercel deploy --prod
```

Point it at a stable hostname you control — `legal.ramibroast.com`, or a
`/legal` path on the restaurant's site. **The URL goes in the store listings and
into the apps, so it must not move afterwards.** A privacy URL that 404s is a
rejection on resubmission, and it is the kind of link nobody checks again.

Once it is live, put it in three places:

1. App Store Connect → App Privacy → Privacy Policy URL.
2. Play Console → App content → Privacy policy.
3. The support/marketing URL fields, if the restaurant has no other site.

## Before it goes live — this is not a finished legal document

**Start at `legal-handover.md`.** It lists every unfilled blank, who answers it
(restaurant / accountant / lawyer), and the one finding that is not a blank at
all: the service currently runs in Google Cloud's `me-central2`, which is
**Doha, Qatar**, not the Dammam region this repo's terraform names — so
personal data is being processed outside the Kingdom, which the PDPL regulates.

Every page says, on the page, that it is **the working version pending the
restaurant's own legal review**. That line is deliberate and must not be deleted
to make the page look finished:

- **It has to become the restaurant's document.** The footer names the
  restaurant as the data controller, not us. A lawyer acting for the restaurant
  has to read, amend and adopt it.
- **The Arabic is a translation of text that has not itself been reviewed.** It
  should go to the same lawyer as the English, and which language governs is
  their decision, not one this repo should make by putting a sentence on the
  page.
- **The retention wording must match what the backend does.** It currently
  describes account deletion accurately — anonymise and deactivate, orders
  retained without a name on them (`backend/src/customers/README.md`) — but the
  actual *period* those records are kept for is an open question for the
  restaurant's accountant against Saudi tax-record rules. When that is answered,
  it goes on this page and nowhere else changes.
- **A policy that contradicts what the app does is worse than no policy.** If
  the apps change what they collect, this page changes in the same commit.

## Keeping the app and the page in step

`customer-app/src/screens/LegalScreen.tsx` shows the same text inside the app.
The two are maintained by hand, not generated from one source — the in-app
screen is a native layout and the page is HTML — so **when one changes the other
changes with it**. The app screen is what a customer reads; this page is what a
store reviewer and a regulator read, and they must not say different things.
