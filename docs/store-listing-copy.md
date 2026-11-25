# Store listing copy and privacy declarations

Drafts for App Store Connect and the Play Console, written from what the apps
actually do rather than from what a food-delivery listing usually says. Nothing
here describes a feature that does not exist — most listing rejections and most
angry first reviews come from the gap between the two.

**Screenshots are not here and cannot be**: they have to be taken from a running
build on a real device, which is blocked on the same things as § B12 of
`app-store-release-readiness.md`.

Character limits are given because both stores truncate silently, and a
description cut mid-sentence is what the customer reads.

---

## customer-app — public listing

### Name and subtitle

| Field | Limit | Value |
| --- | --- | --- |
| App name (Apple) | 30 | `Rami Broast · رامي` |
| Subtitle (Apple) | 30 | `Order from your nearest branch` |
| Title (Play) | 30 | `Rami Broast — رامي` |

The Arabic is in the name deliberately: the customers are in Saudi Arabia, and
the sign over the branch is Arabic. If the combined string is rejected for
length in a locale, drop the Latin half in the Arabic storefront rather than the
Arabic half everywhere.

### Short description (Play, 80 characters)

> **EN** — Order Rami Broast for delivery or pickup, and follow it to your door.
>
> **AR** — اطلب من رامي توصيلًا أو استلامًا، وتابع طلبك حتى باب بيتك.

### Full description (4000 characters)

**English**

> Rami Broast, ordered from your phone.
>
> Browse the full menu from the branch nearest you, build your order with the
> sizes and extras you want, and choose delivery or pickup. The price you see is
> the price you pay — every total, including VAT and the delivery fee, is worked
> out before you confirm, and the itemised bill is one tap away.
>
> **Delivery, priced honestly.** The delivery fee is worked out from the
> distance between the branch and your saved address, and it is shown to you
> before you pay, not added at the end. If your basket is under the minimum, the
> app tells you how much more to add instead of refusing you at the last press.
>
> **Follow your order.** See it accepted, prepared and picked up, and watch the
> driver's position on the map while it is on the way. When the driver's
> position is a few minutes old, the app says so rather than showing you a
> confident guess.
>
> **Offers that actually work.** Every offer in the app is a real coupon with a
> real code, and some discounts apply automatically with no code to type. Where
> a discount applies, the bill shows what the item would have cost beside what
> it did.
>
> **Pay how you like.** Card, or cash on delivery where the branch offers it.
> Card details are handled by the payment provider and never reach the app.
>
> English and Arabic throughout.

**العربية**

> رامي، من جوالك.
>
> تصفّح القائمة كاملة من الفرع الأقرب إليك، وكوّن طلبك بالأحجام والإضافات التي
> تريدها، واختر التوصيل أو الاستلام. السعر الذي تراه هو السعر الذي تدفعه: يُحتسب
> كل مبلغ، بما فيه ضريبة القيمة المضافة ورسوم التوصيل، قبل أن تؤكّد، وتفصيل
> الفاتورة على بعد ضغطة واحدة.
>
> **توصيل بسعر واضح.** تُحتسب رسوم التوصيل من المسافة بين الفرع وعنوانك المحفوظ،
> وتُعرض لك قبل الدفع لا في آخر لحظة. وإذا كانت سلتك دون الحد الأدنى، يخبرك
> التطبيق بالمبلغ المتبقي بدل أن يرفض طلبك عند الضغط الأخير.
>
> **تابع طلبك.** تابعه وهو يُقبل ويُحضَّر ويُستلم، وشاهد موقع السائق على الخريطة
> أثناء الطريق. وإذا مضى على آخر تحديث لموقعه بضع دقائق، يخبرك التطبيق بذلك بدل
> أن يعرض تقديرًا غير دقيق.
>
> **عروض حقيقية.** كل عرض في التطبيق كوبون حقيقي برمز حقيقي، وبعض الخصومات
> تُطبَّق تلقائيًا دون كتابة أي رمز. وحيثما طُبِّق خصم، تعرض الفاتورة السعر قبله
> إلى جانب السعر بعده.
>
> **ادفع كما يناسبك.** بالبطاقة، أو نقدًا عند الاستلام في الفروع التي توفّر ذلك.
> تتولى جهة الدفع بيانات بطاقتك ولا تصل إلى التطبيق.
>
> بالعربية والإنجليزية بالكامل.

**One line must be removed before submission if card payment is not live.**
"Card, or cash on delivery" describes `TapPaymentGateway`, which is still a stub
that throws (§ B9). If the first release ships cash-on-delivery only, the
listing must not advertise card — that is a functionality claim a reviewer can
check in about ninety seconds.

### Keywords (Apple, 100 characters, comma-separated, no spaces)

```
shawarma,مطعم,توصيل,طلبات,وجبات,delivery,restaurant,food,pickup,riyadh,عروض
```

Do not repeat the app name — Apple already indexes it, and the space is worth
more spent on a term nobody else has.

---

## driver-app — private distribution

**This app should not go to the public App Store.** It has no public sign-up:
drivers are created in the admin panel and handed credentials, which is what
Apple rejects under Guideline 4.2. Distribute through Apple Business Manager
(custom apps), or TestFlight for the pilot, and a Play internal/closed track.
See § B11.

Listing copy is therefore minimal and internal:

| Field | Value |
| --- | --- |
| Name | `Rami Broast Driver` |
| Subtitle | `For Rami Broast delivery staff` |
| Description | `The delivery app for Rami Broast drivers. Accounts are issued by the restaurant; there is no public sign-up. Drivers see their assigned deliveries, navigate to the drop-off, capture proof of delivery and record cash collected.` |

Stating "accounts are issued by the restaurant" in the description is not
boilerplate — it is the sentence that explains to a reviewer why there is no
sign-up button, and it belongs in the review notes as well.

---

## Privacy declarations (Apple App Privacy · Play Data safety)

These must match what the code does. They were read off the code, not assumed.

### customer-app

| Data | Collected | Linked to identity | Used for tracking | Purpose |
| --- | --- | --- | --- | --- |
| Phone number | Yes | Yes | No | Sign-in, and the branch contacting you about an order |
| Name | Optional | Yes | No | So the branch and driver know whose order it is |
| Email address | Optional | Yes | No | Account contact |
| Precise location | Yes | Yes | No | Choosing a delivery address; the fee is priced from the distance |
| Purchase history | Yes | Yes | No | The restaurant's record of a sale |
| Payment info | **No** | — | — | Card details never reach our systems |

### driver-app

| Data | Collected | Linked to identity | Used for tracking | Purpose |
| --- | --- | --- | --- | --- |
| Email address | Yes | Yes | No | Sign-in (credentials issued by the restaurant) |
| Precise location | Yes | Yes | No | Navigation, and the customer's live tracking map |
| Photos | Optional | Yes | No | Proof-of-delivery photo, when the delivery requires one |

**The location answer is the one to get exactly right.** The driver app collects
precise location **in the foreground only, and only between pickup and
drop-off** — `driver-app/src/delivery/location-sharing.ts` is the pure function
that decides, and it is tested. Say precisely that.

- Do **not** declare background location. It is not requested and not used, and
  claiming it invites a permissions review the app would fail.
- Do **not** understate it either. Play requires a location-permission
  declaration and often a short demo video for apps requesting location;
  understating is the worse of the two errors.

Neither app uses an advertising SDK or any analytics SDK, so "used for tracking"
is No everywhere and the App Tracking Transparency prompt does not apply. Check
that again if an analytics dependency is ever added — that answer is one `npm
install` away from being false.

---

## Other listing fields

| Field | Answer |
| --- | --- |
| Privacy policy URL | The published `legal/privacy.html` — see `legal-pages.md` |
| Terms / EULA URL | The published `legal/terms.html` |
| Support URL | Needs a page the restaurant controls — not yet decided |
| Support email | Needs a monitored address at the restaurant's domain |
| Age rating | No objectionable content; both apps rate at the lowest tier. Answer the questionnaire honestly — there is no alcohol, gambling or user-generated content |
| Export compliance | Uses HTTPS only, which normally qualifies for the standard exemption — but the question must still be answered |
| Category | Food & Drink (both stores) |

---

## App Review demo account — the unresolved one

**This is B1 wearing a different hat, and it has no clean answer yet.**

Customer sign-in is OTP-only: there is no password path, and the reviewer has to
receive a real SMS to get past the first screen. The pinned demo code
(`OTP_DEMO_FIXED_CODE`) cannot be the answer — the production boot guard in
`backend/src/config/configuration.ts` refuses to start with it set, correctly,
because two API calls would then sign anyone in as any phone number.

The realistic options, in order of preference:

1. **A real number the reviewer can use.** Once an SMS provider is live, give
   App Review a number the restaurant controls and a way to read the code —
   most commonly, the reviewer requests a code and a person at the restaurant
   reads it to them, which does not scale but works for the handful of review
   attempts a release involves.
2. **A reviewer-only account with a fixed code, scoped to that one phone
   number** and to nothing else. This is a real hole and would need to be
   designed deliberately rather than by relaxing the existing guard — it is not
   the demo shortcut with a new name, and it should not be built without a
   decision to accept the risk.
3. Ship the driver app privately (where the reviewer path is easier) and hold
   the customer app until 1 is possible.

Until an SMS provider exists, none of these is available, which is why B1 is
first in the sequence and not fifth.
