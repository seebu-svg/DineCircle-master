# DineCircle — Social Dining Platform (Monorepo)

**Turn your audience into a real-world dining community.**

For local PostgreSQL setup and current audit findings, see
[Getting started](#getting-started).

DineCircle is a monorepo containing a **Flutter consumer app** and a
**Node/Express + PostgreSQL API**. The same account can act as a **diner**, a
**host**, and a **food influencer**; hosts and influencers are the *same*
people who create their own dinners, so both capabilities live in one unified
in-app surface called **Host Studio**. A separate **partner (restaurant) API**
surface exists server-side, role-gated for `partner_admin` accounts.

> ### ⚠️ Project status: authenticated app, wired write path + live Host Studio + P2 Safety & Trust (Phases 3–5 done)
>
> The backend ([server/](server/)) and the app's Riverpod/Dio data layer are now
> genuinely connected: email + password auth **and every core write** — booking,
> cancelling, check-in, publishing a dinner, follows, saves, reviews, chat sends
> and profile edits — reach PostgreSQL from the client. A new account can promote
> itself to `host` (`POST /users/me/host`), the old `GET /bookings?userId=`
> authorization hole is closed, and auth tokens are now stored hashed. Booking
> totals and promo discounts are computed **server-side**. **Host Studio is now
> fully API-backed**: per-event analytics, a wallet + withdrawals ledger,
> collaboration invites and guest-request approve/decline all read and write real
> Postgres rows — no host surface reads `MockData` anymore. Money is a
> **server-side simulated ledger** (withdrawals reduce the balance; nothing is
> actually paid out). **P2 Safety & Trust** shipped: Block/Unblock (follow-graph
> severance, discovery hiding, booking/chat enforcement), Report Users/Content
> (4 targets, 7 reasons, dup-guard, reporter privacy, admin moderation), Feedback
> & Support (6 categories, ticket refs, status tracking). Still missing for
> launch: a real **payment gateway** (Stripe
> — bookings still carry a placeholder `payment_label`), push notifications, a maps
> SDK, scannable QR, media upload, and any partner/admin client. Suitable for
> demos and integration testing — **not yet launch ready**.

---

## Table of contents

- [What DineCircle is](#what-dinecircle-is)
- [Verified development status](#verified-development-status)
- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Feature status legend](#feature-status-legend)
- [Screen inventory & reachability](#screen-inventory--reachability)
- [User roles — actual coverage](#user-roles--actual-coverage)
- [Backend API & integrations](#backend-api--integrations)
- [Security posture](#security-posture)
- [Getting started](#getting-started)
- [Known issues & technical debt](#known-issues--technical-debt)
- [Development roadmap](#development-roadmap)
- [Testing & verification](#testing--verification)
- [About this audit](#about-this-audit)

---

## What DineCircle is

### The value proposition

For **food influencers / hosts**:
- Monetize an audience through paid dining experiences.
- Host exclusive events (tasting nights, chef tables, meetups).
- Partner with restaurants for sponsored experiences.
- Track views, bookings, attendance, revenue and engagement.

For **guests / diners**:
- Discover unique dining events nearby.
- Book a seat with in-app checkout.
- Join tables with other diners and follow hosts.
- Rate and review experiences.

### Core user journeys (as designed)

1. **Discover → Details → Book → Pass** — browse the live feed, open an event,
   complete checkout, receive a digital event pass.
2. **Create → Publish → Manage → Earn** — a 6-step dinner wizard, then Host
   Studio for event management, attendance, earnings and collaborations.
3. **Social** — follow hosts/influencers/friends, messaging and event group
   chat, reviews and ratings.

All three journeys are now wired end-to-end against the API: booking persists a
real server ticket, publishing a dinner calls `POST /events` behind a host gate,
and the social journey (follow/save/review/chat/notifications) reaches the
database. Payments remain simulated (Phase 4) and the partner/admin surfaces have
no client.

---

## Verified development status

Audited from source on 2026-10-24 (client **and** server), re-checked after the
Phase 3 client-wiring pass and the Phase 4 Host-Studio pass, re-audited for
the **P0 financial audit (2026-10-26)** — BUG-02 (cancellation & refund
bookkeeping) and BUG-03 (host earnings accrual) are now fixed and covered by a
PostgreSQL integration suite — and extended for **P1 account management
(2026-10-26)**: change email (verified), change password, privacy toggles, food
preferences, location settings, delete account and logout-all are wired
end-to-end and integration-tested. The headline numbers:

| Metric | Value |
|---|---|
| Dart files / lines in `lib/` | 107 files · ~30,000 LOC |
| Server TypeScript LOC ([server/src/](server/src/)) | ~3,320 across 10 route modules |
| REST endpoints implemented server-side | **81** `/api` routes (+ `/health`) — incl. the P1 account surface and the P2 Safety & Trust routes: `POST/DELETE /users/:id/block`, `GET /users/me/blocked`, `POST /reports`, `GET /users/me/reports`, `PATCH /reports/:id/status` (admin), `POST /feedback`, `GET /users/me/feedback` |
| Screen widgets defined | 35 |
| Screens reachable in the running app | 29 · **5 orphaned** (dead code, kept for Phase 5+) |
| Screens rendering **live API data** | auth, home, explore, dinner detail, restaurant detail, user profile, checkout, bookings, saved, notifications, messages, chat detail, profile, settings, host dashboard, analytics, event manage, create dinner |
| Client-side **mutations wired to the API** | **all core writes** — join/cancel/check-in, publish/delete event, follow/unfollow, save/unsave, review post, chat send, profile PATCH, host promotion, password/email change, settings PATCH, logout-all, delete account, **block/unblock**, **submit report**, **submit feedback** |
| `flutter analyze` | **0 issues** ✅ |
| `flutter test` | **110 tests pass** ✅ (widget, auth, session + account lifecycle, mappers, screens, settings screens, booking flow, social wiring, host studio + fake-repo harness) |
| `tsc --noEmit` (server) | **clean** ✅ |
| Server integration tests | **31 tests pass** ✅ (`npm run test:integration`) — money path 15 ([money.integration.test.ts](server/src/tests/money.integration.test.ts)) + P1 account surface 5 ([account.integration.test.ts](server/src/tests/account.integration.test.ts)) + P2 safety & trust 11 ([safety.integration.test.ts](server/src/tests/safety.integration.test.ts)); all run the real API against an isolated freshly-seeded Postgres and assert the DB rows directly in SQL |
| Server smoke tests | CI `curl` flow: signup → become-host → book → cancel → seat-lock → authz → create-event → **Phase 4 host studio** (approve + 409, decline releases seat, wallet over-balance 400/valid 201, invite accept, performance/partners/invites reads) |

**Bottom line:** the write-path disconnect that defined the previous audit is
**gone** — the app now posts bookings, publishes dinners, follows/saves/reviews,
chats and edits profiles against PostgreSQL, with booking totals and promo
discounts resolved server-side, and **Host Studio is fully wired** (analytics,
wallet/withdrawals, collaboration invites, guest approve/decline all hit the API).
The remaining gaps are product completeness, not
plumbing: no **payment gateway** (money is a simulated ledger), no push, no
partner/admin client, and
6 orphaned screens still on `MockData`.

### What is genuinely real (end-to-end)
- **Email + password account system (P1 scope)** — scrypt-hashed passwords,
  hashed (sha256) opaque bearer tokens (30-day TTL) stored in `auth_tokens`,
  token persisted in `flutter_secure_storage`, validated on cold start via
  `GET /auth/me`, auto-clear on 401. Settings now fully wired: **change
  password** (verifies the current one, revokes other sessions), **change
  email** (password-confirmed 6-digit code challenge, hashed at rest, 15-min
  TTL — no mail provider exists, so dev builds return the code like OTP),
  **privacy toggles / food preferences / home locale** via partial
  `PATCH /users/me`, **logout all devices**, and **delete account**
  (password-confirmed; cancels/refunds live bookings, anonymises the row in
  place, revokes every token — bookings/payout history is preserved).
  Phone + OTP exists server-side and in the repository layer but is
  **dormant by design** (first-launch strategy is email-only).
- **Live discovery reads** — Home and Explore render the events feed and
  restaurant list from the API with loading / error / retry UI and auth-gated
  providers; Dinner Detail, Restaurant Detail and User Profile hydrate from
  live endpoints (menus, venue, attendees, reviews, hosted events).
- **Server booking engine, now wired** — the app calls
  `POST /api/events/:id/bookings` (transactional `FOR UPDATE` seat locking,
  audience gating, sold-out/duplicate checks, host notification), plus
  cancel-with-seat-release and check-in; `GET /bookings` powers the Bookings tab.
- **Write path in the client** — create-dinner `POST /events` (behind a host gate
  + self-serve `POST /users/me/host`), follow/unfollow, save/unsave, review
  posting, REST chat polling (`GET/POST /events/:id/messages`), `PATCH
  /users/me` profile edits and `/activity` notifications all reach the API.
- **Server-authoritative money math** — booking totals and promo-code discounts
  are computed in the transaction from the `promo_codes` table; the client only
  forwards the code, it never decides the price. Platform commission is a
  server-side, **configurable** rate (`PLATFORM_COMMISSION_RATE`, defaults to
  10%) — no fixed percentage is assumed anywhere.
- **Correct refund + earnings bookkeeping (BUG-02 / BUG-03, verified)** —
  cancellation and host-decline run in one transaction that flips the booking
  payment status to `refunded`, releases the seats exactly once, refuses a
  duplicate refund/check-in, and writes an immutable row to the new `refunds`
  ledger (amount, reason, status, policy snapshot, timestamp). Live check-ins
  accrue the host `payouts` row from captured seats via an idempotent
  re-computation (`syncPayout`), so repeated check-ins never double-count and a
  refund after accrual heals the payout back down. Advisory-locked
  withdrawals (`pg_advisory_xact_lock`) close the balance-check/insert race; an
  event with captured money can no longer be hard-deleted. All of this is
  exercised by the 15-test PostgreSQL integration suite.
- **Host Studio, end-to-end** — per-event analytics (`GET /hosts/:id/performance`
  with real views/bookings/attendance/gross), a wallet + withdrawals ledger
  (`GET /hosts/:id/wallet`, `POST /hosts/:id/withdrawals` guarded against
  over-balance), collaboration invites (accept/decline) and guest-request
  approve/decline (`POST /bookings/:id/{approve,decline}` — approval-gated events
  park bookings `pending` and release the seat on decline) all read and write
  PostgreSQL; no host surface reads `MockData` anymore.
- **Infra** — Docker Compose (Postgres 16 + API with readiness retry, schema +
  seed on boot), GitHub Actions CI, Helmet, CORS allowlist, rate limiting,
  audit logging, Zod validation, parameterized SQL throughout.

### What is faked, disconnected, or missing
- **Payments**: no gateway anywhere. Bookings store a cosmetic `payment_label`
  and the checkout "card" is a constant string. Refunds and host earnings are now
  a real server-side **ledger** — `refunds` rows, `payouts` accrual, wallet
  balances and `withdrawals` persist in Postgres and reconcile in integration
  tests — but every refund is stamped `gateway_status = 'simulated'`: nothing is
  actually paid out or refunded at a provider and no gateway is called. The
  `requested → completed` payout lifecycle is still manual. This phase is
  **deliberately** unable to move real money: simulated bookings must never
  create a withdrawable real balance, and no code path flips a `simulated` row
  to `confirmed` (that is the gateway integration's job, see
  [NEXT_STEPS.md](NEXT_STEPS.md)). Stripe keys remain commented-out placeholders
  in [.env.example](server/.env.example).
- **Chat is REST-polled, not realtime**: the client uses 5-second
  `GET /events/:id/messages` polling. Socket.IO rooms are fully built
  server-side but the Flutter app has **no socket client** (Phase 3b).
- **Push notifications**: none. Notifications is the `/api/activity` DB feed;
  no FCM/APNs, no SMS gateway for OTP.
- **Maps**: placeholder painting; no Google Maps/Mapbox SDK; `MapScreen` is
  unreachable. **QR pass**: deterministic decorative pattern from a hash seed,
  not ISO QR, not scannable (the real check-in endpoint is wired). **Uploads**:
  local assets only.
- **6 orphaned screens** remain dead code (see inventory), plus the onboarding
  preferences and payments surfaces still lean on `MockData`.
- The **partner (restaurant)** and **admin/moderation** surfaces have a full
  role-gated API but **no client at all**.

---

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| App framework | **Flutter 3.47.5** / **Dart 3.13.4** | Android, iOS, Web targets |
| App state & DI | **flutter_riverpod ^2.6** | `AsyncNotifier` session controller, `FutureProvider` feeds |
| App networking | **Dio ^5.7** via typed [ApiClient](lib/api/api_client.dart) | bearer interceptor, error mapping, GET retry-once, 401 hook |
| App storage | **flutter_secure_storage ^9.2** | auth token only |
| Connectivity | **connectivity_plus ^6.1** | offline banner widget |
| Fonts/UI | google_fonts, custom dark theme | [lib/theme/](lib/theme/) |
| API server | **Express 5** (TypeScript ESM, tsx runtime, Node 24) | [server/src/](server/src/) |
| Database | **PostgreSQL 17** locally (16/17 also used by CI and compose) via `pg` pool | idempotent [schema.sql](server/src/schema.sql) + [seed.ts](server/src/seed.ts) + [security_hardening.sql](server/database/security_hardening.sql) |
| Validation | **Zod 4** | all request bodies |
| Realtime | **Socket.IO 4** | auth-gated event/restaurant rooms |
| Security | Helmet, express-rate-limit, CORS allowlist, scrypt, audit log | [security.ts](server/src/security.ts) |
| Ops | Docker Compose, GitHub Actions ([server-ci.yml](.github/workflows/server-ci.yml)) | DB-ready retry, schema+seed on boot |

---

## Architecture

```
Flutter app (lib/)
├── main.dart / app_shell.dart   AppFlow: splash → onboarding → auth → prefs → 5-tab shell,
│                                all session-driven; shell owns shared Navigator callbacks.
├── api/                         AppConfig (--dart-define API_BASE_URL, default http://10.0.2.2:4000),
│                                ApiClient (Dio wrapper), DTOs, JSON helpers, Mappers (DTO → model).
├── repositories/                session, events, restaurants, users, bookings, social, chat, hosts —
│                                typed reads **and writes** (money is a simulated server ledger).
├── providers/                   Riverpod wiring: session controller (token lifecycle), auth-ready
│                                gate, events feed w/ EventFilter, restaurants, users, prefs.
├── screens/<area>/              31 screen widgets; live screens watch providers, the rest read MockData.
├── data/mock_data.dart          Legacy source, shrinking: still used by payments, preferences,
│                                location, a few create-dinner dropdown option lists and the 6 orphaned screens.
└── models/ theme/ widgets/      Immutable domain models, design tokens, reusable UI.

Express API (server/src/)
├── server.ts                    helmet → CORS → rate-limit → /api/auth (public) → requireAuth →
│                                auditLog → routers; Socket.IO w/ token handshake + room ACLs.
├── routes/                      auth, events, restaurants, users, hosts, reviews, bookings, chat,
│                                social (mobile) + partner (role-gated restaurant surface).
├── context.ts                   requireAuth / requireRole / loadUser (roles: user, host,
│                                partner_admin, super_admin).
├── db.ts / schema.ts / seed.ts  pool + withTransaction; idempotent DDL; deterministic seed world.
└── security.ts                  rate limiters + audit-log middleware.
```

**Key architectural facts (verified after Phase 3):**
- The client now mutates server state across every core journey (bookings,
  events, social, chat, reviews, profile) through typed repository methods; the
  old snackbar-only write illusions have been replaced.
- Money and authority are server-side end-to-end: the checkout UI forwards the
  selected seats + promo code and renders the **server-returned total, discount
  and reference** — it no longer computes fees or discounts as the source of
  truth.
- `GET /api/bookings` is scoped to the acting user only (the `?userId=` override
  and its horizontal-authorization gap are removed; the host `?eventId=` guest
  list is still host-checked).
- `POST /users/me/host` lets a freshly registered diner self-promote to `host`,
  which unblocks the host-gated `POST /events` path from inside the app.

---

## Project structure

```
DinCircle/
├── lib/                    # Flutter app (107 dart files)
│   ├── api/                # client, exception, config, dto/, json, mappers/
│   ├── providers/          # Riverpod providers: session, events, users, hosts,
│   │                       # social, chat, prefs, safety + controllers
│   ├── repositories/       # session, events, restaurants, users, bookings,
│   │                       # social, chat, safety — read **and** write
│   ├── models/ data/       # domain models (incl. safety.dart); mock_data.dart
│   ├── screens/            # 40 files (incl. safety/, support/, help/) — 5 orphaned
│   ├── theme/  widgets/    # design system; connectivity banner, cards, skeletons,
│   │                       # DataView (loading/empty/error/retry) for live screens
├── test/                   # 110 tests: widget, auth_screen, session_controller,
│   │                       # mappers, screens_data, booking_flow, social_wiring,
│   │                       # host_studio, settings + fake_repositories harness
├── server/                 # Express 5 + PostgreSQL API
│   ├── src/routes/         # 13 route modules (auth, bookings, chat, events,
│   │                       # feedback, hosts, offers, partner, reports,
│   │                       # restaurants, reviews, social, users)
│   ├── src/{schema.sql, schema.ts, seed.ts, db.ts, context.ts, security.ts,
│   │       pricing.ts, passwords.ts, blocks.ts, server.ts}
│   ├── src/tests/          # 31 integration tests (money + account + safety)
│   ├── database/security_hardening.sql
│   ├── Dockerfile  docker-compose.yml  .env.example
├── .github/workflows/server-ci.yml   # typecheck + schema/seed + write-path curl smoke on Postgres 16
├── .deploy_stage/          # v0.1.0 prototype APK distribution notes (debug-signed)
├── android/ ios/ web/ assets/ pubspec.yaml
```

---

## Feature status legend

| Symbol | Meaning |
|---|---|
| ✅ **Real (E2E)** | Works end-to-end against the API/DB |
| 🟢 **Live read** | Screen renders real API data with loading/error/retry |
| 🟡 **Partial** | The wired subset is live; remaining sections are still simulated/mocked |
| 🧪 **Simulated** | UI fakes success (snackbar / local state); nothing persists |
| 🔌 **Server-only** | Working API endpoint exists but **no client wiring** |
| ⛔ **Orphaned** | Screen built but unreachable in navigation |
| ⬜ **Missing** | Not implemented on either side |

| # | Spec area | Client | Server | Notes |
|---|---|---|---|---|
| 1 | Authentication (email+password) | ✅ | ✅ | scrypt, secure-storage token, /me restore, real sign-out; OTP dormant |
| 2 | Onboarding / splash / prefs | ✅ (local) | — | flags persisted via shared prefs |
| 3 | Home feed | 🟢 | ✅ | live events + restaurants; overflow on narrow portrait |
| 4 | Location & map discovery | 🧪 / ⛔ | ⬜ | picker is cosmetic; MapScreen unreachable; no geocoding |
| 5 | Explore categories | 🟢 | ✅ | live feed filtered by type/featured/query |
| 6 | Dinner / event details | 🟢 | ✅ | live detail + menu + venue + reviews + host events |
| 7 | Booking flow | ✅ | ✅ | checkout → `POST /events/:id/bookings`; server total/reference/discount rendered |
| 8 | Payments | 🧪 | ⬜ | no gateway, no charges, no webhooks; constant `payment_label` (Phase 4) |
| 9 | My bookings | ✅ | ✅ | Bookings tab reads `GET /bookings`; cancel + check-in wired |
| 10 | Digital pass / QR | 🟢 | ✅ | pass shows real `reference`; check-in endpoint wired; QR still decorative |
| 11 | Create dinner | ✅ | ✅ | wizard → `POST /events` behind a host gate + `POST /users/me/host` |
| 12 | Host dashboard / earnings | 🟡 | ✅ | `summary`/`payouts`/`trend` live; withdraw + collabs still simulated |
| 13 | Influencer analytics | 🟡 | 🟡 | live `trend` + summary; views/conversion/attendance have no server metrics |
| 14 | Event management | 🟡 | ✅ | guest list live via `GET /bookings?eventId=`; approve/attendance UI simulated |
| 15 | Social profiles | 🟢 | ✅ | User Profile live via `/api/users/:id`; own Profile reads `currentUserProvider` + `PATCH /users/me` |
| 16 | Follow system | ✅ | ✅ | follow/unfollow wired + counters/activity invalidate |
| 17 | Messaging & event chat | 🟢 | ✅ | REST polling wired; send + append; Socket.IO rooms server-side still have no client |
| 18 | Restaurant discovery | 🟢 | ✅ | list + detail live; partner owner surface has no client at all |
| 19 | Offers & promotions | ⛔ | ⬜ | OffersScreen orphaned; no offers API |
| 20 | Reviews & ratings | ✅ | ✅ | detail shows live reviews; composer → `POST /events/:id/reviews` (gated to completed bookings) |
| 21 | Notifications | 🟢 | ✅ | `/activity` feed + mark-read live; **no push delivery anywhere** |
| 22 | Saved / wishlist | 🟢 | ✅ | SavedScreen reads `GET /me/saved`; save/unsave toggles wired |
| 23 | Wallet & earnings | 🧪 | ⬜ | no ledger, no payouts execution (payout rows are seeded) |
| 24 | Safety & trust | ✅ | ✅ | P2 complete: block/unblock (server-side follow severance, discovery hiding, booking/chat enforcement), report (4 targets, 7 reasons, dup-guard, reporter privacy, admin moderation), verified badges + role/ownership checks |
| 25 | Help & support | ✅ | ✅ | P2 complete: HelpScreen reachable (Settings + Profile), Feedback submission (6 categories), My Reports & ticket history with status tracking |
| 26 | Settings | 🟢 | ✅ | P1 complete: every row is wired — Personal Information (PATCH /users/me), Change Email (verified challenge), Change Password, Food Preferences, Location, Privacy & Security toggles, Log Out, Logout All Devices, Delete Account; phone/OTP intentionally not exposed |
| 27 | Admin / moderation | ⬜ | 🟡 | `super_admin` role + gates exist server-side; **no admin client or console** |

---

## Screen inventory & reachability

**Reachable (25):** Splash, Onboarding, **Auth**, Preferences*, **Home**,
**Explore**, **DinnerDetail**, **RestaurantDetail**, **UserProfile**,
**Checkout**, **BookingConfirmed**, **Bookings**, **Profile**, **CreateDinner**,
**Saved**, **Notifications**, **Messages**, **ChatDetail**, **Settings**,
**HostDashboard**, **Analytics**†, **EventManage**†, Wallet*, Payments*,
Location*. (Bold = live API data; † = partly live; \* = still mock/simulated.)

**⛔ Orphaned — never instantiated anywhere (5):** `MapScreen`,
`OffersScreen`, `PeopleScreen`, `PartnersScreen`,
`MyTablesScreen` — kept on purpose for Phase 5+ (see
[roadmap](#development-roadmap)). `HelpScreen` is now **reachable** (wired from
Settings → Help & Feedback and Profile → Help & Support). `SearchScreen`,
`DiscoverScreen` and `ReviewScreen` were **deleted** as superseded by the live
Explore / DinnerDetail / review-composer paths; `MyTablesScreen` is now redundant
with the live Bookings tab.

---

## User roles — actual coverage

Roles are a DB CHECK constraint: `user | host | partner_admin | super_admin`
(enforced by `requireRole` in [context.ts](server/src/context.ts)).

| Role | Server | Client |
|---|---|---|
| **Guest / Diner** | Reads gated behind `requireAuth`; booking engine fully implemented | Full browse + booking on live data; real tickets from `GET /bookings`; checkout carries a placeholder payment label |
| **Host / Influencer** | Event create/delete, guest list, payouts/summary/trend endpoints gated | Host Studio reads live `summary`/`payouts`/`trend`; a diner self-promotes via `POST /users/me/host` from the Create gate |
| **Restaurant (partner)** | Complete role-gated partner API: venues, events CRUD, bookings, check-in, menus, analytics, notifications | ⬜ **Zero client** — no partner app in this repo; public restaurant view only |
| **Administrator** | `super_admin` passes partner gates | ⬜ No admin/moderation surface at all |

The current user is the **real** signed-in profile everywhere (from
`/auth/me`); the Profile screen reads `currentUserProvider` and edits via
`PATCH /users/me`. Role is surfaced in the session and drives the host gate —
there is no in-UI role switching beyond the self-serve become-host step.

---

## Backend API & integrations

**81 endpoints across 13 routers** — verified present, parameterized and
Zod-validated:

| Router | Endpoints (summary) |
|---|---|
| `/api/auth` | signup, login, otp/request, otp/verify, me, signout, change-password, change-email (+/confirm), change-phone, logout-all |
| `/api/events` | feed with filters, detail by id, by host/venue, create (host-gated), delete, cancel |
| `/api/bookings` | list mine / host guest-list, create (transaction + `FOR UPDATE`), cancel, check-in, approve, decline |
| `/api/restaurants` · `/api/users` | list/detail · me, partial settings `PATCH /users/me`, `DELETE /users/me`, `POST /users/me/host`, tier, influencer, public profile, search |
| `/api` reviews · chat · social | post/list reviews; REST chat w/ membership check; activity feed, mark-read, saves, follows |
| `/api/users/:id/block` · `/users/me/blocked` | **P2**: block (POST), unblock (DELETE), list blocked (GET) — server-side follow severance + discovery hiding + booking/chat enforcement |
| `/api/reports` · `/users/me/reports` | **P2**: submit report (POST, 4 targets, 7 reasons, dup-guard), my report history (GET), admin status update (PATCH) |
| `/api/feedback` · `/users/me/feedback` | **P2**: submit feedback (POST, 6 categories, validation), my feedback history (GET) |
| `/api/hosts` | payouts, earnings summary, trend analytics, wallet, withdrawals, collaboration invites |
| `/api/partner` | role-gated: restaurants, events CRUD, bookings, checkin, menus, analytics, notifications |
| Socket.IO | authenticated handshake; `join_event`/`join_restaurant` rooms with ACL re-check on send |

**Integrations not present (either side):**

| Capability | Status |
|---|---|
| Payment gateway (Stripe etc.) | ⬜ placeholder env keys only; `payment_label` is cosmetic |
| Push notifications (FCM/APNs) | ⬜ activity rows live in DB only |
| SMS delivery for OTP | ⬜ dev console-log; no provider |
| Maps / geocoding | ⬜ no SDK; client-side placeholder only |
| Scannable QR / ticketing | ⬜ decorative pattern; server check-in exists |
| Media upload / storage | ⬜ no endpoints, no `image_picker`, local assets only |
| Analytics / crash reporting | ⬜ none |

---

## Security posture

**In place (server):** Helmet headers; CORS origin allowlist; global 100 req/min
and auth 10 req/min rate limits; scrypt password hashing with timing-safe
verify; opaque DB-backed bearer tokens with expiry; ownership/role checks on
event writes, partner routes and chat; audit log of every authenticated
mutation; `security_hardening.sql` for a restricted DB role.
**In place (client):** token in `flutter_secure_storage`; single typed error
surface; 401 → session reset; connectivity banner + retry-once GETs.

**Fixed this phase:** auth tokens are now stored **hashed (sha256)** in
`auth_tokens` and hashed on lookup/signout; the `GET /bookings?userId=`
horizontal-authorization hole is **closed** (acting user only); promo codes are
validated server-side so the client can no longer dictate a discount.
**Remaining gaps:** no refresh/rotation; OTP codes have no attempt throttling;
no signup email verification or account lockout (email *changes* are
code-verified since P1); no input-length limits on review/chat
bodies beyond Zod strings; secrets in compose are defaults.

---

## Getting started

### Prerequisites
- Flutter **3.47.5+** (Dart 3.13.4+) · Node **24** · npm · **PostgreSQL 17** running locally (podman/docker compose is an optional alternative)

### 1. Run the API

```bash
cd server
cp .env.example .env                # defaults work for local dev
npm install

# Start a disposable PostgreSQL 17 container on port 5433:
podman run -d --name dinecircle-pg \
  -e POSTGRES_USER=dinecircle \
  -e POSTGRES_PASSWORD=dinecircle \
  -e POSTGRES_DB=dinecircle \
  -p 5433:5432 docker.io/library/postgres:17-alpine

npm run db:setup && npm run dev     # schema + seed, then http://localhost:4000/api/health

# Alternative: docker compose up --build (starts Postgres + API together)
```

Seeded demo world (from [seed.ts](server/src/seed.ts)): deterministic users
including host and partner-admin accounts, two restaurants, live dinners,
bookings, reviews, chats, payouts. Production accounts: register via
`POST /api/auth/signup`.

### 2. Run the app

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000   # Android emulator
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:4000
```

The default API host (`10.0.2.2`) targets the Android emulator loopback; pass
`API_BASE_URL` explicitly for other devices. **The app requires the API to be
up** — there is no offline fallback, and the auth gate blocks the shell until
sign-in succeeds.

#### Payment + Maps keys (local test build)

The client keys live in a gitignored `dart-defines.json` (copy
`dart-defines.example.json` and fill it). Pass it at build time so the
PaymentSheet path activates and the map has a key:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000 \
  --dart-define-from-file=dart-defines.json
```

When the file is absent (CI, fresh clones) `STRIPE_PUBLISHABLE_KEY` is empty,
`AppConfig.stripeEnabled` is false, and checkout keeps the historical simulated
confirmation — so keyless builds and the widget tests are unaffected. The
server secret key (`sk_test_`) stays only in `server/.env`; it must never reach
the app. Live checkout also requires `STRIPE_WEBHOOK_SECRET` (a `whsec_`) in
`server/.env` — until it is set, real webhook deliveries cannot be verified and
bookings will not settle to `paid`.

### 3. Build a testable APK

```bash
flutter build apk --release --split-per-abi
```

> Release builds are **debug-signed** (see [android/app/build.gradle.kts](android/app/build.gradle.kts)) —
> fine for internal testing (see [.deploy_stage/](.deploy_stage/)), not Play-eligible.

### 4. Checks

```bash
flutter analyze      # expected: No issues found!
flutter test         # expected: 979 tests pass (offline; no server needed)
cd server && npm run typecheck                 # expected: clean
cd server && npm run test:integration          # expected: 31/31 (needs local Postgres)
```

---

## Known issues & technical debt

- **Payments are simulated only (largest remaining gap):** the refund/earnings
  ledger is now correct and auditable, but no provider is ever called — every
  `refund`/`payout` row stays `simulated`/`scheduled`. Wiring Stripe
  (PaymentIntents + webhooks), flipping rows through `pending_gateway →
  confirmed` on webhook confirmation, and paying hosts for real is Phase 4.
- **Chat is polled, not realtime:** 5s REST polling while a chat is open;
  Socket.IO rooms exist server-side but have no client (Phase 3b).
- **Host analytics partially mocked:** views/conversion/attendance/"event
  performance" have no server metrics; only summary/payouts/trend are live.
- **Dual data sources (shrinking):** most core screens are live now, but ~54
  `MockData.*` references remain across Payments, Preferences, Location, the
  host-simulated sections and the 6 orphaned screens.
- **6 orphaned screens**; residual no-op handlers and snackbar-only actions
  remain in the not-yet-wired prototype surfaces.
- **Home feed overflow** (`RenderFlex`) at narrow portrait widths — tolerated
  in tests, needs a responsive pass.
- **God files:** create_dinner and host_dashboard remain large; split before
  extending further.
- **No dedicated server route tests** in CI yet (vitest/jest); CI validates the
  write path with a `curl` smoke flow against the seeded Postgres service. (A
  local PostgreSQL money-path integration suite now exists — see Testing below.)
- **Debug-signed APK**; keystore undecided.

---

## Development roadmap

### Phase 0–2 — Completed
- Broad clickable UI (35 screens), design system, models, mock dataset.
- Unified Express 5 + PostgreSQL API: auth (scrypt + tokens), 44 endpoints,
  transactional booking engine, partner routes, Socket.IO chat, hardening,
  Docker + CI + seed world.
- Flutter data layer: Dio client with interceptor/retry/401 handling,
  DTOs + mappers, repositories, Riverpod providers; live Home/Explore/Detail
  screens; real email+password auth flow with persisted session; 33-test
  harness; zero analyzer issues.

### Phase 3 — Completed (client write-path wiring)
1. **Booking flow wired** — checkout → `POST /events/:id/bookings` (server
   total/reference/discount), Bookings tab → `GET /bookings`, cancel + check-in
   actions, pass rendered from the real `reference`.
2. **Create Dinner wired** → `POST /events` behind a host gate, with the new
   self-serve `POST /users/me/host` promotion path.
3. **Social wired** — follow/unfollow, save/unsave, review posting, and
   activity-backed Notifications with mark-read; Saved screen now live.
4. **Chat wired via REST polling** (`GET/POST /events/:id/messages`); the
   Socket.IO realtime client is deferred to **Phase 3b**.
5. **Profile & Settings wired** — identity from `/users/me`, Edit Profile via
   `PATCH /users/me`, real logout.
6. **Security landed** — closed the `GET /bookings?userId=` auth gap and hashed
   auth tokens; server-side promo validation added. (Formal server route tests
   remain a follow-up; CI uses a `curl` smoke flow.)

### Phase 3b — Realtime chat (small)
- Add a `socket_io_client` and swap the 5s REST polling for the existing
  authenticated event/restaurant rooms (server side is already complete).

### Phase 4 — Money (make booking economic)
- Stripe Checkout/PaymentIntents + webhooks; server-side fees/tax and a refund
  state machine; adopt the unused `pending/no-show/refunded` booking statuses.
  (Server-side **promo validation already landed** in Phase 3 — replace the
  placeholder `payment_label` with a real charge id.)

### Phase 5–7 — Platform completeness
- Push notifications (FCM/APNs) over the `activity` table; real QR generation
  + host scanner check-in; maps SDK + geocoding; image upload for covers
  (multipart + storage).
- Wire or delete the 6 orphaned screens; responsive pass on Home.
- **Partner (restaurant) client** — the API is ready; app/build decision.
- **Admin/moderation console** — user/event review, disputes, payout
  oversight (role gates already scaffolded).

### Later
- Group tables & shared booking, recommendation engine, monetization tiers,
  loyalty, multilingual, offline caching, accessibility certification.

---

## Testing & verification

- `flutter analyze` → **0 issues**; `flutter test` → **110 pass** (session
  controller with fake repos, auth screen incl. inline server errors, mappers,
  live screens' data rendering incl. Bookings/Saved/Notifications, **booking
  flow** checkout→join incl. promo + server errors, **social wiring** follow/
  save/mark-read, settings screen (6 tests incl. P2 tiles), app boot + shell
  smoke). Tests run offline against fakes.
- Server `tsc --noEmit` → clean. **Integration suites** (run with
  `npm run test:integration`) boot the real API on an OS-assigned free port
  against an isolated freshly-created + seeded database and assert rows in raw
  SQL. **31 tests total**:
  - **Money path** (15) — accrual, refund, cancel, decline, capture, promo,
    withdrawal validation, cross-user authz, concurrency, rollback, event-delete
    guard, simulated-only, configurable commission.
  - **Account surface** (5) — change-password session revoke, email-change
    matrix, partial PATCH, logout-all, delete-account settlement.
  - **P2 Safety & Trust** (11) —
    [server/src/tests/safety.integration.test.ts](server/src/tests/safety.integration.test.ts):
    block guards (self/unknown/deleted/unauthenticated); follow-graph severance
    + idempotency + counter healing + unblock-never-restores; discovery/profile
    hiding both ways + roster 403 + third-party unaffected; event-feed hiding +
    new-booking refusal + existing-ticket preservation + unrelated diner can join;
    group-chat post blocking; reports all 4 targets with evidence snapshots;
    invalid/duplicate/self report rejection; reporter privacy + admin moderation
    flow + target unlock; feedback 6 categories persisted; validation + stranger
    access refusal; full regression suite (auth, discovery, follow, booking, Host
    Studio, wallet).
- CI ([server-ci.yml](.github/workflows/server-ci.yml))
  runs typecheck, schema + seed, then a **write-path `curl` smoke flow**
  (signup → become-host → book → cancel → seat-lock 409 → horizontal-authz →
  create-event 403/201) against a live Postgres 16 service.
- **No device-runtime verification** was performed in this pass; functional
  claims come from source inspection plus the suites and CI smoke above.

---

## About this audit

Rewritten from a **full-source audit of both halves** of the monorepo: every
route module and the schema/seed/security files server-side; every provider,
repository, DTO/mapper, screen import graph and navigation edge client-side;
`pubspec.yaml`, Docker, CI and Android signing configs. Each feature was
classified by tracing whether an action actually reaches the database — a
screen existing was never taken as evidence of a feature working.

This status reflects the **Phase 3** client write-path pass and the **P0
financial audit** layered on top of that source audit: the app drives the
booking, event, social, chat, review and profile writes against PostgreSQL, and
BUG-02 / BUG-03 are fixed with an auditable refund + earnings ledger proven by
integration tests. Real payments remain future phases — the money path is
deliberately simulated end-to-end. Realtime chat, push and the partner/admin
clients also remain open.

---

## License

Prototype / proof of concept for DineCircle. Internal use only.
# DineCircle
# DineCircle-master
# DineCircle-master
