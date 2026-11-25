# Legal documents — what is needed before these can be published

`legal/privacy.html` and `legal/terms.html` are **drafts**, written from what
the software actually does and structured against the Saudi Personal Data
Protection Law (PDPL) and its Implementing Regulations. They are not finished
legal documents and must not be linked from a store listing yet.

Two things stand between them and publication: **21 blanks in the privacy
notice and 12 in the terms**, and **a lawyer acting for the restaurant** to
review and adopt them. The pages count their own blanks and print a red DRAFT
banner across the top until every one is filled, so it is not possible to
publish them half-finished without noticing.

> **These documents were not written by a lawyer.** They were drafted by
> engineering from the behaviour of the system, so that the restaurant's lawyer
> starts from an accurate description rather than a blank page or a competitor's
> policy. Every judgement that is legal rather than factual has been left as a
> marked blank rather than guessed. Treat this page as the brief for that
> review.

---

## 1. Facts only the restaurant can supply

Straightforward, and none of them needs a lawyer. Until they are filled in, the
privacy notice names no controller — which is the one thing a privacy notice
exists to do.

| Blank | Where | Notes |
| --- | --- | --- |
| Restaurant legal name | both | The registered company name, not the trading name "Rami Broast" |
| Commercial registration (CR) number | both | Required on e-commerce disclosures as well |
| VAT registration number | terms | |
| Registered address | both | |
| Privacy contact email | privacy | Must be monitored — the notice promises a reply within 30 days |
| Privacy contact phone | privacy | |
| Payment provider legal name | privacy | Tap Payments, or whoever is actually contracted |
| SMS provider legal name | privacy | Blocked on B1; fill in when the provider is chosen |

## 2. Questions for the accountant

| Blank | Where |
| --- | --- |
| Retention period for order, payment, VAT and refund records | privacy §6 |
| Retention period before the anonymised account record is purged | privacy §6 |
| Retention period for driver delivery records and proof of delivery | privacy §6 |
| Retention period for driver location points | privacy §6 |
| Retention period for technical and security logs | privacy §6 |

The first of these also unblocks `backend/src/customers/README.md`, where the
same question is recorded as open. **Whatever is decided has to match on both
sides**: a notice promising deletion after N years, against a database that
keeps rows forever, is a false statement rather than a mismatch.

## 3. Questions for the lawyer

These are the ones that are legal judgements, not facts. Each is marked in the
documents at the point where the answer goes.

**Privacy notice**

1. **Is a Data Protection Officer required?** The Implementing Regulations
   require one in defined circumstances. If one is appointed, their contact
   details go in §1.
2. **Confirm the legal basis for each purpose** in the §3 table. In particular:
   are any marketing messages sent? If so, they need separate consent and their
   own row — today the app sends only transactional messages about an order, and
   the table says so.
3. **Cross-border transfer — see §5 and section 4 below.** This is the most
   consequential item on the page.
4. **Written processing agreements** with the payment, SMS, maps and hosting
   providers, as the Regulations require. The notice states they exist.
5. **Minimum age and any guardian-consent requirement** (§10).
6. **Is the restaurant registered with SDAIA** as a controller, where required?
   Not a blank in the document, but it is the obligation behind it.

**Terms**

7. **Cancellation and refunds (§7) against the E-Commerce Law** and its
   Implementing Regulations. The draft relies on the exemption for perishable
   and made-to-order goods, which is why there is no cooling-off period — that
   reasoning needs checking, along with the required complaint-handling
   timescales.
8. **Failed delivery (§5):** if the driver cannot hand the order over, is the
   customer charged? A consumer-facing decision with a legal edge.
9. **Payment timing (§6):** authorised at placement and captured on acceptance,
   or charged in full at placement? This changes what a customer sees on their
   statement, and the current answer is an implementation detail nobody has
   written down.
10. **Limitation of liability (§11).** Deliberately left blank. What may
    lawfully be excluded in a consumer contract in the Kingdom is a legal
    question, and an unenforceable cap is worse than none — it misleads the
    customer about rights they actually have.
11. **Governing law and forum (§14)**, including whether a consumer keeps a
    route to the Ministry of Commerce regardless.
12. **Allergen disclosure (§3)** against SFDA requirements for prepared food
    sold online.

## 4. One finding that is not a blank, and needs deciding before launch

**The service currently runs outside Saudi Arabia.**

Both apps point at `rami-api-…me-central2.run.app`. Google Cloud's `me-central2`
is **Doha, Qatar**. `me-central2` is Dammam, Saudi Arabia — and that is the
region `terraform/variables.tf` and `deploy-backend-gcp.md` both name.

So the intent in this repo is to host in the Kingdom, and the running deployment
is not. Personal data of Saudi customers is being processed abroad, which the
PDPL and the Regulation on Personal Data Transfer Outside the Kingdom regulate
directly, and which may require a documented risk assessment before the transfer
takes place.

There are two ways to resolve it, and it is a business decision rather than an
engineering one:

- **Move to `me-central2` (Dammam).** Note the practical obstacle: Google
  requires KSA-billing customers to purchase Dammam-region services through
  CNTXT, which is a commercial arrangement to set up, not a config change. That
  may well be why the demo ended up in Doha.
- **Stay in Doha and do it properly** — establish and document the transfer
  basis, carry out the risk assessment, and disclose it plainly in §5 of the
  privacy notice, which is drafted to accommodate exactly that.

What is not an option is leaving §5 vague. It is the section a regulator reads
first, and "your data is held securely" is not an answer to "where".

This was found while drafting, not by an audit. **A wider check of what else
leaves the Kingdom is worth doing before launch** — the maps, SMS and payment
providers each process data somewhere, and each needs the same treatment.

---

## 4b. Drivers are now given the customer's real phone number

**Owner decision, and a change of position rather than a gap.** Until now no
driver was ever given a customer's mobile number: no call-masking provider is
contracted, and the platform's default was to withhold it. The owner has decided
a driver should be able to ring the customer directly when they arrive, because
a driver at an unmarked gate with a cooling bag and nobody to reach was the cost
of the old rule.

What actually happens, so the lawyer can review the fact rather than a summary
of it:

- Only the driver a delivery is **assigned to** receives it, and only **while
  that delivery is in progress** — from the moment they collect the order until
  they mark it delivered or failed. Before and after, the number is not in the
  response at all, not merely hidden by the app.
- It is the **real, undisguised** number. There is no masking layer.
- **It does not accumulate.** Finished deliveries stay visible in the driver
  app, so an earlier draft that kept the number past the drop would have left
  every customer a driver had ever served one tap from being dialled. The
  server withholds it after the job closes, so a driver's handset never becomes
  a customer directory.

Both documents were updated to say so (privacy §"Who we share it with", and the
plain-language summary on the customer app's Legal screen — those two are
maintained by hand and must always change together). They previously stated the
opposite in as many words, which is why this is called out here rather than
filed as a routine edit.

**Three things for the lawyer:**

1. Whether this needs anything beyond the disclosure now in §"Who we share it
   with" — a lawful-basis line of its own in the §4 table, say.
2. **Whether "the duration of the delivery" is the right window**, and whether
   anything needs saying about the copy a driver may have made by hand — the
   system stops showing the number, which is not the same as the driver
   forgetting it, and no software boundary can be.
3. Whether drivers need a written instruction on using it (calling about the
   delivery in hand and nothing else), and whether that belongs in their
   contract rather than in a notice to customers.

If masking is ever contracted, `backend/src/delivery/customer-contact.ts` is the
single place that changes.

---

## 5. Editing the documents

Both pages carry English and Arabic in one file, as `data-en` / `data-ar`
attribute pairs on each element. To change a sentence, change both attributes.
A blank is written as `[[ LIKE THIS ]]` in the source; `legal.js` highlights
every one and counts them into the banner, so removing a blank is simply
replacing the whole `[[ … ]]` token with the real text.

**The Arabic is a translation prepared by engineering alongside the English.**
It should go to the same lawyer, not be treated as already-reviewed because the
English was. Which language governs is the lawyer's decision, and the drafts
deliberately do not state one.

Once the review is complete:

1. Remove the yellow `notice` paragraph from the top of each page — that is the
   line that says these are drafts, and it should go only when they are not.
2. Change the version from `0.9 (draft)` to `1.0` and set the date.
3. Confirm the banner is gone, which means no blank was missed.
4. Deploy per `legal-pages.md` and put the URLs into both store listings.
5. Update `customer-app`'s `LegalScreen`, which carries the plain-language
   summary of the same facts and says so on the page. **A change to one is a
   change to both, in the same commit** — the customer reads the summary and the
   regulator reads the document, and they must not disagree.
