# QZ Tray signing — removing "allow this site to print?" at the counter

QZ Tray shows an **untrusted website** dialog once per session for any page it
cannot verify. On a branch terminal that is every morning, mid-service, in front
of a person who does not know what the dialog is asking — with the first order
of the day waiting behind it.

Signing each print request removes it. The mechanism is built and deployed; what
this document covers is the part that is a **decision and a purchase**, not code.

---

## What is already built

| Piece | Where | State |
| --- | --- | --- |
| Signing endpoints (`/printing/qz/certificate`, `/printing/qz/sign`, `/printing/qz/status`) | `backend/src/printing/` | Built, tested |
| Client wiring (`setCertificatePromise` / `setSignaturePromise`, SHA-512) | `kitchen-pos/src/print/qz-signing.ts` | Built, tested |
| The `printing:sign` permission, granted to KITCHEN and BRANCH_ADMIN | `backend/prisma/seed/permissions.ts` | Seeded |

**With no certificate configured, everything still prints** — with the prompt.
That is a deliberate working state: printing that stopped until a certificate
was bought would hold a shop's service hostage to a purchase order.

The **private key never leaves the backend.** The Branch POS is a static bundle
served to every branch; a key inside it is a published key. The browser sends
QZ's challenge string to the API, the API signs it, and the signature comes back.

---

## The decision: self-signed (owner, 2026-09-10)

**The owner has chosen the self-signed route.** The rest of this document is
that route, start to finish. The paid alternative is described at the end for
whenever the branch count makes it worth revisiting.

Its one cost is that each counter machine has to trust the certificate once, and
**the POS now does that step for the branch**: it builds a one-file installer
with the certificate already inside it. A branch downloads it and runs it. There
is nothing to email, no path to type and no order to get wrong.

---

## The whole procedure

### Once, for the platform

```bash
scripts/generate-qz-certificate.sh
```

That writes two files:

| File | What it is | Where it goes |
| --- | --- | --- |
| `qz-certificate.pem` | the certificate — **public** | `QZ_SIGNING_CERTIFICATE` |
| `qz-private-key.pem` | the private key — **a secret** | `QZ_SIGNING_PRIVATE_KEY` |

Put both into Secret Manager together (`scripts/setup-secrets.sh`,
`docs/secrets.md`), redeploy the backend, then **delete your local copy of the
key**. The backend refuses to boot on half a pair.

The certificate is not a secret and does not need guarding: it is served to
every branch by the API and embedded in the installer each counter downloads.
The key never leaves Secret Manager and the backend.

### Once, at each branch — one file, one press

1. Branch POS → **Print settings**.
2. **Download the certificate installer.**
3. Windows: right-click it → *Run with PowerShell* as an administrator.
   Mac/Linux: `sudo sh install-printer-certificate.sh`.
4. It writes the certificate, restarts QZ Tray, and says so.

That is the entire per-machine step. It takes seconds, needs no typing, and the
script refuses clearly if QZ Tray is not installed rather than half-doing it.

**If it is skipped, the branch still prints** — QZ asks it to allow printing
once each session. A nuisance, not a fault, and it can be done later.

### When a counter machine is replaced

Step 3 again on the new machine. Nothing else changes: the pair on the platform
stays the same.

---

## Rotating the certificate

The generated certificate lasts ten years, deliberately: an expiry is a day
every branch stops printing at once, for a reason nobody on site can diagnose.

If it ever has to be replaced, the order matters — **every counter needs the new
certificate installed before the new key starts signing**, or every branch is
prompted until somebody visits it. In practice: generate the new pair, install
it at each branch from a POS still running the old configuration, and switch the
backend last.

---

## The alternative, for later

There are two routes, and they differ in exactly one way that matters — **how
much has to be done on each branch machine.**

### A. A QZ code-signing certificate (paid, nothing per machine) — not chosen

Bought from QZ Industries' premium support programme. Every QZ Tray install
trusts it out of the box, so a new branch machine needs **no printing setup at
all** beyond choosing the printer.

- Cost: a yearly fee to QZ. Ask them for current pricing for a commercial
  deployment across multiple sites — **do not assume last year's figure.**
- Setup per branch: **none.**
- This is the route to pick if branches will be opened by people who are not
  technical, or opened without anyone from the platform present.

### B. A self-signed certificate (free, one file per machine) — **chosen**

Generate a key pair yourself, configure the backend with it, and install the
certificate into QZ Tray's allow list on each counter machine as `override.crt`.

- Cost: nothing.
- Setup per branch: **one file, once**, at the same visit the printer is plugged
  in and the POS is signed in. It is not a recurring task and it is not a
  service-time task — but it is a visit.
- The trade is real: it costs nothing and it costs a step. If a branch machine
  is ever replaced, the step returns.

**Worth revisiting when** the branch count grows enough that "one file per new
counter machine" stops being a step somebody is happy to do, or when branches
start opening with nobody technical on site. Switching later is the rotation
procedure above plus a new certificate from QZ — no code changes.

---

## Where the certificate actually goes

The installer handles this; it is written down because somebody will one day
have to check it by hand.

| Platform | Path |
| --- | --- |
| Windows | `C:\Program Files\QZ Tray\override.crt` (since QZ Tray 2.1) |
| macOS | `/Applications/QZ Tray.app/Contents/Resources/override.crt` — **inside** the bundle |
| Linux | `/opt/qz-tray/override.crt` |

QZ Tray reads it **at startup**, so it must be restarted afterwards — the
installer does that too. QZ also supports an `authcert.override` entry in
`qz-tray.properties` as an alternative.

**Check these against QZ's own documentation for the version you install.** They
differ by platform and have moved between releases, and this document is not the
authority on them.

---

## Configuring the backend

Two variables, and they are useless apart — the backend **refuses to start** on
one without the other, because a certificate with no key signs nothing while the
person who set it believes printing is configured.

| Variable | Value |
| --- | --- |
| `QZ_SIGNING_CERTIFICATE` | the certificate PEM |
| `QZ_SIGNING_PRIVATE_KEY` | the private key PEM |

Both accept a PEM whose newlines survived the environment as the two characters
`\n`, because that is how Secret Manager and most shells hand one back.

Add them with `scripts/setup-secrets.sh` like every other secret; this repository
holds **names only**.

---

## Checking it worked

1. Sign in to the Branch POS on the counter machine.
2. **Print settings** → the setup panel. When it finishes it says either
   *"Prints are signed, so QZ Tray will not ask this computer to allow
   printing"* or *"QZ Tray will ask this computer to allow printing once each
   session"*.
3. Print a real docket. No dialog is the whole test.

If it still prompts on route B, the certificate is not in QZ's allow list on
**that** machine — the backend half is shared and the machine half is not.

---

## What signing is and is not

A signature says **this platform approved this print**. It is not encryption, it
does not authenticate the person at the counter, and it does not protect the
contents of a receipt — the ticket travels from the browser to QZ on the same
machine either way.

One property worth knowing before it is discovered in a review: the signing
endpoint signs what it is given. That is QZ's protocol, not a choice made here.
It is authenticated, gated on `printing:sign`, rate-limited by the global
throttle, capped at 8 KB, and never logged — but an authenticated staff account
can obtain a signature for a string of its choosing, and what that signature
asserts is only ever "this platform approved a print".
