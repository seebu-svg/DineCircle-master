# DineCircle — Partner App Integration Readiness Audit

**Date:** 2026-10-29
**Scope:** shared Express/PostgreSQL backend, REST surface, schemas, authorization,
money paths, and the integration tests that prove them — preparing the platform
for a second client (the Partner App) without breaking the Customer App.
**Architecture (unchanged):** one API, one database, two mobile clients.
**Companion document:** [server/docs/PARTNER_API.md](server/docs/PARTNER_API.md) — the endpoint inventory the
Partner App is built against.

> Status: **backend contract verified, not production-ready.** The blocker list in
> §8 is the honest remainder; nothing in §6 is a claim I did not execute.

---

## 1. Executive summary

The Partner surface was **substantially not wired up**. Five route modules
(~40 endpoints) had been written but never imported, so registration,
verification, branches, staff, menus, tables and reservations were dead code. Two
tables (`restaurant_deals`, `restaurant_payouts`) had no API at all, so "deals,
earnings and payouts" did not exist. On top of that the integration suite could
not run at all on this machine, which is why those gaps had gone unnoticed.

All of that is now closed: the routers are mounted, the missing operations module
is implemented, the legacy partner surface uses the same membership model and
response envelope as the new one, and a **15-test partner contract suite** covers
authorization, isolation, registration/verification, the staff ladder, menus,
reservation concurrency, host-event approvals, deals, earnings, the dashboard,
notifications and the response envelope.

Verification actually executed:

| Check | Command | Result |
|---|---|---|
| Typecheck | `cd server && npx tsc --noEmit` | clean |
| Backend integration suite | `npm test` (5 files) | **58 / 58 pass** |
| Fresh schema + seed | `npm run db:setup` on a scratch DB | applies cleanly |
| Live-server smoke (CI assertions) | `bash server/.qa/ci_smoke_check.sh` | 403 / 201 / 200 as asserted, commission 10 % |
| Flutter static analysis | `flutter analyze` | no issues |
| Flutter widget tests | `flutter test` | **979 pass, 0 fail** (§6.2) |

---

## 2. What the audit found, and what was fixed

Severity = production impact if shipped.

### Critical

| # | Symptom | Root cause | Fix | Proof |
|---|---|---|---|---|
| C1 | 40+ partner endpoints answered 404 | `partner_venues`, `partner_menu`, `partner_tables` and the customer `reservations` router were never imported in `server.ts` — the files were complete but orphaned | Mounted all of them, ordered by specificity (`/partner/verification` → venue sub-resources → venue collection → legacy `/partner`) | `partner.integration.test.ts` T3–T6 |
| C2 | `GET /partner/verification/requests` returned `404 Restaurant` | Registered after `GET /:restaurantId`, so the literal path matched the param route | Split a `verificationRouter` mounted at `/partner/verification` | T4 (explicit regression test) |
| C3 | Deals, earnings, payouts, event approvals and the dashboard did not exist | `restaurant_deals` / `restaurant_payouts` were in the schema with zero code; `partner_ops.ts` was missing entirely | New `partner_ops.ts`: dashboard, request approve/decline, deals CRUD + transitions, earnings, payouts | T9–T13 |
| C4 | Creating a venue event always failed with `500` | `POST /partner/events` omitted `host_id`, which is `NOT NULL` | Insert records the acting operator as host; event publishes as `confirmed` (a venue approving its own listing is meaningless) | T11 (create + partial update) |
| C5 | `PUT /partner/events/:id` with `{}` silently reset tagline, description, type, audience, menu style, cover image and tags | Zod `.partial()` does not strip `.default()`s, so every default looked like a client-supplied value; `endAt` was not writable at all | The SET list is now driven by the keys actually present in the request body; an empty patch is `400` | T11 |
| C6 | `GET /partner/restaurants` answered `200 { restaurants: [] }` to any diner | No partner gate on the list route | `requirePartner` on that route only (self-registration stays open to any signed-in account) | T1 |

### High

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| H1 | `restaurant_owner` / `restaurant_staff` / host-owned venues got `403` from the partner API | Legacy gate was `requireRole('partner_admin','super_admin')` and every query filtered `r.owner_id = $1` | Gate → `requirePartner`; scoping → `scopedRestaurantIds` + `venueScopeClause` (membership table, `owner_id` = implicit owner) |
| H2 | Two different `GET /partner/restaurants(/:id)` implementations, the legacy one unscoped-by-membership | Duplicate surface from the pre-membership era | Legacy handlers deleted; `partner_venues` is the single implementation |
| H3 | Hosts could publish into venues that had asked to review events | `restaurants.requires_host_approval` existed but nothing read it | Policy implemented in `events.ts`: gated events land in `requested`, venue is notified; approval/decline in `partner_ops.ts` writes `restaurant_approved_at/by` or `decline_reason` and an `approval` activity for the host |
| H4 | Draft, venue-pending and venue-declined events were visible in discovery and **bookable** by anyone holding the id | Feed/detail/booking queries only filtered by `status <> 'cancelled'` | Feed and detail hide non-published events from everyone but their host; `POST /events/:id/bookings` treats them as unknown (`404`) |
| H5 | A partner could attach another restaurant's `branchId` to a reservation | `createReservation` validated the branch id's existence, not its venue | Branch membership check → `422 Unknown branch for this restaurant` |
| H6 | The platform's commission silently became **0 %** when `PLATFORM_COMMISSION_RATE` was unset | `Number('') === 0` passed the `0 <= rate < 1` guard, so the documented 10 % default never applied | Unset/blank now falls back to the default; an explicit `0` still waives commission. Test harness no longer pins the rate, so the suite fails if the default regresses |
| H7 | Five legacy partner endpoints returned five different shapes (`{events,count}`, `{bookings}`, `{analytics,recentBookings}`, …) | Pre-standardisation surface | All now `{ data, meta }`; empty `PATCH` returns `400` instead of `200 {updated:false}` |
| H8 | The dashboard's unread badge could never be cleared | No mark-as-read endpoint existed anywhere | `POST /partner/notifications/:id/read` and `/read-all`, both venue-scoped (foreign id → `404`) |

### Medium

| # | Symptom | Fix |
|---|---|---|
| M1 | `activity.kind` check constraint rejected `'approval'`, so approvals could not be recorded | Constraint widened in `schema.sql` |
| M2 | `verified` meant different things in different responses (`partnership_status` only vs. `is_partner && status`) | One predicate everywhere: `is_partner && partnership_status === 'verified'`, exposed as `restaurant.verified` |
| M3 | Nothing on the partner side could be exercised from the seed: no branches, tables, menu, deals or payouts, and every venue was unverified | Seeded a verified fixture (8 tables / 60 covers, 2 menu sections + 4 items, an active `SUNSET20` deal, one paid payout) and an unverified fixture that opts into host approval |
| M4 | The integration suite could not boot on a peer-auth Postgres host | Test harness now understands unix-socket URLs (`?host=/var/run/postgresql`) and defaults the user to the OS account |
| M5 | Staff invitation accept URL (`/staff/invites/:restaurantId/accept`) did not match the invite contract | Normalised to `/:restaurantId/staff/accept` |
| M6 | The partner contract suite existed nowhere in CI; CI only ran a hand-rolled curl smoke | `server-ci.yml` now runs `npm run test:integration`; the smoke's host-403 assertion was retargeted to the seeded *unverified* venue (the Rooftop fixture is now verified) |

**Preserved deliberately:** the Customer App's API surface (auth, discovery,
events, bookings, payments/refunds, chat, social, trust & safety) was not
changed except for the two intentional tightenings H4 and H5, both of which only
refuse requests that were already invalid.

---

## 3. Shared backend & database readiness

37 tables, no new database, no second backend. Everything below is reachable
from both clients.

| Shared module | Tables | Partner API | Customer API | State |
|---|---|---|---|---|
| Users, roles, auth | `users`, `auth_tokens`, `otp_codes`, `email_change_challenges` | `/auth/*`, `/users/me/*` | same | working |
| Restaurants, branches, locations | `restaurants`, `restaurant_branches`, `supported_cities` | `/partner/restaurants`, `…/branches` | `/restaurants`, `/cities` | working (newly wired) |
| Hours & availability | `restaurant_branches.opening_hours`, `timezone` | `…/branches/:id/hours` | `/restaurants/:id/availability` | working |
| Menu & pricing | `restaurant_menu_sections`, `restaurant_menu_items`, `menu_items`, `special_menus` | `…/menu/*`, `/partner/menus` | `/restaurants/:id/menu` | working |
| Table reservations | `restaurant_tables`, `table_reservations` | `…/tables`, `…/reservations` | `/restaurants/:id/reservations`, `/users/me/reservations` | working, concurrency-safe |
| Dining events & hosts | `dinner_events` | `/partner/events`, `…/event-requests` | `/events/*` | working |
| Event approvals | `dinner_events.status/restaurant_approved_*`, `notifications` | `…/event-requests/:id/approve|decline` | hidden until approved | new |
| Deals & promotions | `restaurant_deals`, `promo_codes` | `…/deals` | `/offers`, `/promo-codes` | new (deals) / working (promo) |
| Payments, refunds | `bookings`, `refunds`, `stripe_events` | read-only via earnings | `/bookings/*`, Stripe webhook | working |
| Earnings & payouts | `payouts`, `withdrawals`, `restaurant_payouts` | `…/earnings`, `…/payouts`, `/partner/analytics` | `/hosts/:id/wallet` | working (ledger only) |
| Reviews, ratings | `reviews` | — (see §7) | `/reviews`, `/events/:id/reviews` | working |
| Notifications | `notifications`, `activity`, `audit_log` | `/partner/notifications` (+ read-state) | `/notifications` | working |

Schema changes were additive and replay-safe (`CREATE TABLE IF NOT EXISTS`, one
`ALTER … DROP/ADD CONSTRAINT` for `activity.kind`). `npm run db:setup` was run
end-to-end on a scratch database to confirm the seed still applies.

---

## 4. Partner App integration readiness

| # | Required capability | Endpoints | State |
|---|---|---|---|
| 1 | Registration & verification | `POST /partner/restaurants`, `GET /partner/verification/requests`, `POST …/:requestId/review`, `POST …/:id/verification` | ready |
| 2 | Profile & branch management | `GET/PATCH /partner/restaurants/:id`, `…/branches` CRUD, `…/branches/:id/hours` | ready |
| 3 | Menu & pricing | `…/menu`, `…/menu/sections`, `…/menu/items`, `…/menu/availability` | ready |
| 4 | Table availability & reservations | `…/tables` CRUD, `…/availability`, `…/reservations` | ready |
| 5 | Booking confirm / cancel / check-in | `POST …/reservations/:id/:action`, `POST /partner/bookings/:id/checkin` | ready |
| 6 | Host event requests & approvals | `…/event-requests`, `…/approve`, `…/decline` | ready |
| 7 | Dining events & capacity | `/partner/events` (create/update/list), seat counters on the shared event row | ready |
| 8 | Deals & promotions | `…/deals` CRUD + lifecycle, verified-only gate | ready |
| 9 | Earnings & payout reporting | `…/earnings`, `…/payouts`, `/partner/analytics` | ready (reporting; disbursement not automated) |
| 10 | Notifications & dashboard | `…/dashboard`, `/partner/notifications`, read-state | ready |

**Cross-app consistency** is structural, not synchronised by a job: both apps read
and write the same rows. Proven in the suite — a desk confirmation in the Partner
API appears on the diner's `GET /users/me/reservations`; a partner 86-list entry
removes the item from the public menu; a venue approval makes a host event appear
in the diner feed and become bookable.

---

## 5. Security & API standardization

**RBAC** — platform role (`user`, `host`, `influencer`, `partner_admin`,
`restaurant_owner`, `restaurant_staff`, `super_admin`) plus a per-venue ladder
`staff (1) < manager (2) < owner (3)`. `restaurants.owner_id` counts as an
implicit owner so legacy accounts keep working.

**Restaurant-level isolation** — every partner handler resolves the caller's
membership for the venue in the path via `requireVenueRole`. `404` (unknown
venue) and `403` (someone else's venue) stay distinguishable, so ids cannot be
enumerated. Aggregates use `scopedRestaurantIds`, never a client-supplied id list.

**Tokens** — opaque 256-bit secrets, stored `sha256`-hashed; `signout`,
`logout-all`, per-token expiry. No database credential, Stripe secret or admin
token is readable from either mobile app; the apps only ever hold their own token.

**Input validation** — Zod on every write, pagination/`partySize`/date formats
validated on reads, `limit` capped at 200.

**Duplicate & overbooking prevention** — reservation creation runs in a
transaction that locks the venue row (`FOR UPDATE`) before the table and cover
checks, and the reference is retried on the (astronomically unlikely) unique
clash. Proof: 5 parallel party-2 requests against 2 remaining seats → exactly one
`201`, four `409`, `held == capacity` (T8).

**Response contract** — `{ data, meta }` for lists, `{ data: {resource} }` for
singles, `{ error, issues? }` for failures. Status codes: `400` invalid,
`401` unauthenticated, `403` wrong actor, `404` unknown/unreachable,
`409` stale state or clash, `422` semantically unknown reference.

**Payments** — card capture, refunds and webhook settlement all run server-side
against Stripe (test key in `.env`; `STRIPE_WEBHOOK_SECRET` required for real
settlement). Refund bookkeeping is transactional and idempotent — the existing
money suite covers double-cancel, promo-discounted refunds, accrual rollback and
withdrawal limits. Commission is server-configured and echoed to clients; it is
never a client input.

---

## 6. Integration test results

`cd server && ITEST_ADMIN_DATABASE_URL="postgresql:///postgres?host=/var/run/postgresql" npm test`

```
tests 58 · pass 58 · fail 0
```

| Suite | Tests | Covers |
|---|---|---|
| `partner.integration.test.ts` | 15 | authz, venue isolation, registration + verification queue, staff ladder, menu, tables + reservations + customer availability, concurrency, host approvals (approve + decline + default policy), deals, earnings, dashboard, envelope, notifications |
| `money.integration.test.ts` | 18 | accrual, refunds, double-cancel, promo refunds, withdrawal limits, concurrency, rollback, configurable commission |
| `payments.integration.test.ts` | 12 | mock checkout, webhook signatures, replay, amount mismatch, failure, approval-gated capture, refund via webhook, stale holds, 100 % promo |
| `safety.integration.test.ts` | 8 | blocks, reports, feedback, moderation, regressions |
| `account.integration.test.ts` | 5 | password/email change, settings PATCH, logout-all, account deletion |

Each file boots the real Express API as a child process against its **own
freshly-seeded database**, so nothing is mocked at the HTTP layer.

Partner-suite specifics worth calling out: authorization is checked across nine
paths with a diner token; a partner reading a foreign venue gets `403` and a
nonexistent one `404`; a refused write is asserted to have created no row; the
verification queue's shadowing regression has its own assertion; an approve
cannot be replayed (`409`) and writes exactly one `activity` row.

### 6.1 What the suite does *not* prove

- No device/emulator run of the Customer App against this API (the Flutter tests
  use fakes, not HTTP).
- No load, latency or soak testing; rate limits are exercised only by unit paths.
- No Stripe live-mode verification (`sk_test_…` + a locally generated webhook
  secret).

### 6.2 Customer App test status

`flutter analyze` → clean. `flutter test` → **979 pass / 0 fail** (899 pass / 55
fail when this audit was written).

The 55 failures were not uniform — triaged by their first exception line:

| Class | Cases | Cause | Resolution |
|---|---|---|---|
| Framework assertion, not layout | 45 | `ReportSheet`, `ChangeEmailSheet` and `ChangePasswordSheet` were pumped bare as `MaterialApp.home`, so `TextField` / `RadioListTile` threw `No Material widget found` before any layout ran | Those three matrices were dropped from `layout_overflow_extended_test.dart`; the same 5 widths × 3 scales plus keyboard-insert cases already run through their real `show*Sheet()` hosts in `layout_overflow_sheets_test.dart` |
| Vertical overflow | 6 | Non-scrollable `Column` inside a scroll-controlled sheet host, overflowing on the bottom at 2.0x and with the keyboard up (`EditProfileSheet`, `BookingCheckInSheet`) | Both sheets now scroll (`SingleChildScrollView`) |
| Horizontal overflow | 4 | Non-flex children in a `Row` (`BookingConfirmedScreen` pass badge, `MyTablesScreen` price) | Badge wrapped in `Flexible`; My Tables row rebalanced to `Expanded(flex: 3)` + `Flexible(FittedBox(scaleDown))` |

A further defect the matrix never exercised was found while fixing these: the
`_PassPreviewCard` branch of `BookingConfirmedScreen` — the screen a guest sees
*with* a booking, not the empty-state fallback — overflowed at every width from
320 to 600 px, including 1.0x text scale. Both of its non-flex `Row` children
were fixed and a `BookingConfirmedScreen (pass card)` matrix was added, growing
the suite by 15 cases.

---

## 7. Missing functionality & dependencies

Verified absent (searched the source, not assumed):

| Gap | Impact on the Partner App | Effort |
|---|---|---|
| No partner-facing **reviews** read (reviews are event-scoped only) | a venue cannot see its own ratings or reply | small (read + reply endpoints) |
| No venue-initiated **refund** (guest cancel / host decline only) | a desk cannot comp or refund a ticket from the app | medium (needs a policy decision + gateway call) |
| **Payouts are ledger-only** — no Stripe transfer, no commission invoice | earnings are reported, money is not disbursed | large (Stripe Connect onboarding) |
| No **media upload** (image URLs only) | menu/cover photos must be hosted elsewhere | medium |
| No **push notifications** (in-app `notifications` rows only) | the Partner App must poll; no door-bell alert | medium (FCM/APNs + device tokens) |
| No **realtime channel** for partner screens | dashboard is pull-only | small–medium (the API already runs a WebSocket server consumer-side) |
| Verification review needs a `super_admin` and there is no admin console | onboarding is API/psql-driven | medium |
| No per-client API versioning | future breaking change hits both apps at once | small |

Dependencies: the backend needs only PostgreSQL ≥ 13 (uses `gen_random_uuid`,
`FILTER`, `make_interval`) and Node 24; no new packages were added.

---

## 8. Remaining blockers before this is "production ready"

1. ~~55 failing Flutter layout tests~~ **Resolved**: `flutter test` is 979 pass /
   0 fail (§6.2). The defects behind it were real at 2.0x text scale, so this
   closed a user-visible bug as well as a red CI signal.
2. **No end-to-end device test** of either app against the deployed API. The
   contract suite proves the server; the integration of the *clients* is unproven.
3. **Money movement is incomplete**: card capture/refund is wired to Stripe (test
   keys), but venue payouts and commission invoicing are ledger entries only.
   `STRIPE_WEBHOOK_SECRET` must be a real endpoint secret for live settlement.
4. **Deals are not yet redeemable by the Customer App.** The partner side can
   publish them; `bookings` still applies `promo_codes`, not `restaurant_deals`.
   Until that wire exists, a deal is a marketing record, not a discount.
5. **No push channel**, so "incoming booking" and "event request" alerts depend on
   polling the dashboard.
6. Partner API has no versioning and no per-client rate limit (one global limiter).

### Recommended next steps (in order)

1. ~~Fix the six widgets behind the 55 layout failures~~ **Done** (§6.2).
2. Wire deal redemption into `POST /events/:id/bookings` (validate code → adjust
   `total_amount` → record redemption), so published deals actually discount.
3. Add partner review read/reply endpoints.
4. Device smoke: run the Customer App against the local API (book → desk confirm →
   guest sees confirmation) and the same flow from a Partner App test client.
5. Decide payout execution (Stripe Connect) and implement venue-initiated refunds
   with the same ledger discipline as the existing refund path.
6. Add a second CI job for `flutter analyze` + `flutter test` so the UI suite stops
   drifting.

---

## 9. Reproducing this verification

```bash
# backend
cd server
npx tsc --noEmit
ITEST_ADMIN_DATABASE_URL="postgresql:///postgres?host=/var/run/postgresql" npm test

# live-server smoke used to reconcile the CI assertions with the new seed
bash .qa/ci_smoke_check.sh

# customer app
cd ..
flutter analyze
flutter test
```

`ITEST_ADMIN_DATABASE_URL` is only needed when the app role cannot `CREATE
DATABASE` (each suite builds its own throwaway database). In CI, where
`POSTGRES_USER` is a superuser, `npm test` works unchanged.

---

## 10. Files changed in this pass

```
server/src/server.ts                     mount the orphaned routers (C1)
server/src/routes/partner_ops.ts         new: dashboard, approvals, deals, earnings, payouts (C3)
server/src/routes/partner_venues.ts      verification router split (C2), verified flag (M2), list gate (C6)
server/src/routes/partner.ts             membership gate/scoping (H1), legacy deleted (H2),
                                         host_id + confirmed status (C4), provided-key SET list (C5),
                                         { data, meta } envelope (H7), notification read-state (H8)
server/src/routes/partner_menu.ts        (wired; unchanged)
server/src/routes/partner_tables.ts      (wired; unchanged)
server/src/routes/reservations.ts        customer availability/bookings (wired; unchanged)
server/src/reservations.ts               branch isolation (H5)
server/src/routes/events.ts              approval policy + non-published visibility (H3, H4)
server/src/routes/bookings.ts            refuse non-published events (H4)
server/src/pricing.ts                    commission default (H6)
server/src/access.ts                     (new in this work: membership model)
server/src/api.ts                        (new in this work: envelope helpers)
server/src/schema.sql                    activity kind 'approval' (M1)
server/src/seed.ts                       partner fixtures (M3)
server/src/tests/util.ts                 socket-aware bootstrap, no pinned commission (M4, H6)
server/src/tests/partner.integration.test.ts  new: 15-test contract suite
server/.qa/ci_smoke_check.sh             new: live-server verification script
server/docs/PARTNER_API.md               new: Partner App API documentation
.github/workflows/server-ci.yml          run the integration suite (M6)
```
