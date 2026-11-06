# DineCircle — v0.1.0 Test Build

Internal testing build of the **DineCircle** user app (Flutter prototype). DineCircle lets
anyone discover, host and book social dining experiences — the same account can act as diner,
host and food influencer, with a unified "Host Studio" for event management, earnings and
analytics.

---

## 1. Which file do you need?

| File | Use it if |
|---|---|
| `DineCircle-v0.1.0-arm64-release.apk` (43 MB) | **Almost everyone.** Phones from ~2019 onwards (Pixel, Samsung S9+, Xiaomi, OnePlus, etc.). |
| `DineCircle-v0.1.0-arm32-release.apk` (41 MB) | Very old / low-end 32-bit devices. Try this only if the arm64 install fails. |

You cannot mix the two on one device — uninstall one before installing the other.

---

## 2. Install

1. Copy the APK to the phone (USB cable, Drive, WhatsApp to yourself — anything).
2. Tap the file in the Files app.
3. Android will warn about **unknown sources**. Choose *Settings → Allow from this source*,
   then go back and tap **Install**.
4. Open **DineCircle** from the app drawer.

> "App not installed / Parse error" almost always means the wrong ABI was chosen
> (use the other APK) or a different build is already installed (uninstall it first).

---

## 3. What works in this build

This is a **UI prototype driven entirely by mock data** — there is no backend, no real accounts
and no real payments yet. Everything below is clickable and behaves as designed, but nothing is
persisted between restarts.

- **Onboarding & auth** — 5-slide intro, sign-up / log-in screens, cuisine preferences.
- **Home feed** — 15 sections (upcoming events, followed hosts/influencers, near you, trending
  restaurants, exclusive menus, discounted dining, recommendations…) + 4 quick actions.
- **Explore** — 11 tappable categories, Featured Hosts / Influencers / Restaurants carousels,
  Trending Experiences, Popular This Week, live filtered results.
- **Search & Map** — 10 search categories with real-time filtering; map with dinner, restaurant
  and special-event pins showing distance, price and seat availability, tapping through to details.
- **Location** — city selector with current location, recent locations and popular cities.
- **Dinner / Event details** — full event info (schedule, venue, menu, dress code, age
  restriction, cancellation policy, offers), host card, attendee previews, reviews, other events
  by the host, Join / Waitlist / Save / Share / Report.
- **Booking flow** — 3-step checkout (seats → guest info + promo codes → review & pay),
  price breakdown with 10 % service fee, booking-confirmed screen.
  Promo codes to try: `FOODIE5`, `WELCOME10`, `DINE20`, `VIP15`.
- **My bookings** — 6 statuses (pending / confirmed / cancelled / completed / no-show / refunded),
  check-in QR pass, directions, contact host, cancel with refund notice, contextual Past actions,
  review form and digital receipts.
- **Digital pass** — ticket-style pass with QR + barcode and a simulated check-in animation.
- **Payments** — saved methods (card / Apple Pay / Google Pay / Venmo / bank), transaction history
  with status filters, receipts, refund requests, failed-payment retry.
- **Create dinner** — 6-step wizard (basics → pricing → dining details → menu → guest settings →
  review & publish), plus post-publish edit / pause / cancel actions.
- **Host Studio** — Overview, Events, Earnings (withdraw, commission breakdown, payout history)
  and Collabs (invitations, promote to followers) tabs; Event Management (guest requests with
  approve/reject, attendance, announcements, seat capacity, cancel-with-refund).
- **Analytics** — period selector, 6-metric summary, views chart, booking funnel, per-event table,
  follower engagement.
- **Also included** — restaurant detail, user profiles with follow, offers, saved items, messages
  and chat, notifications, wallet, review composer, help & support, settings.

---

## 4. Known limitations of this build

- **No backend.** All data is mock data; the app restarts from the same state every time and
  actions (booking, publishing, withdrawals, follow) are simulated rather than saved.
- **Payments are not real.** No card is charged; the payment step is a UI simulation.
- **QR codes are decorative.** They render a deterministic pattern from the booking ID, not a
  scannable standard QR, and check-in is simulated in-app.
- **Map is a styled placeholder,** not a live map provider (no pan/zoom/gesture navigation).
- **Notifications and messages are not delivered** from real events, other users or pushes.
- **iOS is not included** in this folder — this build is Android-only.
- **No trust & safety backend:** verification badges, reports and blocks are UI only — nothing is
  reviewed, moderated or enforced anywhere.
- **Some rough edges remain.** This is an 80 %-complete prototype; the remaining 20 % (real data,
  persistence, live maps/QR, push delivery) is scheduled for the next round.

---

## 5. Feedback

Report anything that looks broken — ideally with **screenshots/screen recording, the exact
taps you made, your device model and Android version**. Screens that crash on open are the
highest priority.

---

## 6. Build details

| | |
|---|---|
| Version | 0.1.0 |
| Application ID | `com.dinecircle.dine_circle` |
| Engine | Flutter 3.47.5 / Dart 3.13.4 |
| Build type | release, split per ABI |
| Signing | **Android debug key** — internal testing only |
| Distribution | direct APK install; not on Google Play |

Because this build is signed with a debug key, a future release signed with a proper keystore
will **not** be able to update it in place — expect to uninstall this one when the signed
release arrives.

*Prototype build — not production software.*
