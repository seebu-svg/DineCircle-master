# DineCircle — NEXT_STEPS

Last updated: **2026-10-26** — after the **P1 authentication & account
management** delivery (§8), which followed the **P0 financial audit** (BUG-02
cancellation & refund bookkeeping, BUG-03 host earnings accrual).

This file records what was verified, what changed, and the concrete work that
remains before real money can move through the platform. The authoritative
product/status doc is [README.md](README.md); this file is the action list.

---

## 1. Status of the two P0 bugs — RESOLVED (simulated ledger)

Both bugs are fixed and **proven by a PostgreSQL integration suite**, not just
source inspection. The money path remains **fully simulated** by design (see §5).

| Bug | Symptom | Root cause | Fix | Proof |
|---|---|---|---|---|
| **BUG-02** | Guest cancel flipped `status='cancelled'` but left `payment_status='paid'`; no refund trail | No `refunds` ledger; payment status not written to match the refund lifecycle; refund amount/policy not captured | Cancel + host-decline now run in **one transaction**: flip `payment_status → 'refunded'`, release seats once, refuse duplicate cancel/check-in, and insert an immutable `refunds` row (amount, reason, status, policy snapshot, `gateway_status='simulated'`) | T2, T3, T4, T5, T7, T11, T13 |
| **BUG-03** | Live bookings produced no earnings; wallet relied on seeded payout data | No accrual hook on check-in; payout was not recomputed from captured seats; fixed 10% commission | `syncPayout()` re-computes the event `payouts` row **from scratch** on every check-in/cancel from captured seats (idempotent, never double-counts); commission is now a **configurable** `PLATFORM_COMMISSION_RATE`; advisory locks serialise accrual vs withdrawal | T1, T6, T8, T10b, T14 |

### Verification results (all green)
- `npm run typecheck` (server) → **clean**
- Money-path integration suite → **15 / 15 pass** (re-run twice, stable)
  ```bash
  cd server
  DATABASE_URL="postgresql://<user>@localhost:5432/dinecircle" npm run test:integration
  ```
- `flutter analyze` → **0 issues**
- `flutter test` → **97 / 97 pass**
- Direct PostgreSQL assertions → the `refunds` table (columns, CHECK enum
  constraints on `reason`/`status`/`gateway_status`, and `idx_refunds_booking` /
  `idx_refunds_event`) is present in the dev `dinecircle` database.

---

## 2. Files & schema changed in this pass

- [server/src/schema.sql](server/src/schema.sql) — new **`refunds`** ledger table
  + two indexes. Idempotent (`CREATE TABLE IF NOT EXISTS`); re-run schema setup
  on any existing database.
- [server/src/pricing.ts](server/src/pricing.ts) — commission now read from
  `PLATFORM_COMMISSION_RATE`; added `recordRefund()`; `syncPayout()` takes a
  host-keyed `pg_advisory_xact_lock`.
- [server/src/routes/bookings.ts](server/src/routes/bookings.ts) — cancel &
  decline wired to `recordRefund()` inside the existing transaction; enriched
  refund object in the API response; guard so a cancelled/completed booking
  cannot be checked in or double-cancelled.
- [server/src/routes/events.ts](server/src/routes/events.ts) — `DELETE /events/:id`
  refuses (409) when the event has captured payments or accrued earnings, so the
  financial trail is never destroyed by a `ON DELETE CASCADE`.
- [server/src/routes/hosts.ts](server/src/routes/hosts.ts) — withdrawal runs in
  one transaction with `FOR UPDATE` (on the user row) **and** a host-keyed
  advisory lock matching `syncPayout` (this replaced an invalid
  `FOR SHARE UPDATE EXCLUSIVE` clause that was throwing 500s); balance read
  shares the transaction client.
- [server/src/security.ts](server/src/security.ts) — rate limits are
  env-configurable (`API_RATE_LIMIT_MAX`, `AUTH_RATE_LIMIT_MAX`).
- [server/src/tests/util.ts](server/src/tests/util.ts) +
  [server/src/tests/money.integration.test.ts](server/src/tests/money.integration.test.ts)
  — new isolated-DB integration harness + 15 money tests.
- [server/.env.example](server/.env.example), [server/package.json](server/package.json)
  — money-path config docs and `test` / `test:integration` scripts.

---

## 3. Financial model, statuses & commission logic

**Booking `status`**: `pending` → `confirmed` → `completed`; `cancelled` is
terminal. A `pending` (approval-gated) hold is captured to `confirmed` on host
approve, or reversed to `cancelled` on decline.

**Booking `payment_status`**: `unauthorized/authorized → paid → refunded`
(`failed` reserved). Meaning of each money move:

| Transition | Trigger | `refunds` row written | Money semantics |
|---|---|---|---|
| `authorized → paid` | booking created (instant) or host **approve** | no | capture (simulated) |
| `paid → refunded` | guest **cancel** of a captured booking | yes, `status='refunded'`, amount = captured total | refund booked (simulated) |
| `authorized → refunded` | host **decline** of an uncaptured hold | yes, `status='released'`, amount = `0` | release, moves no money |

**Commission (server-side, single source of truth in `pricing.ts`):**
- `gross = SUM(captured seats' total_amount)` where `payment_status='paid'` and
  `status IN ('confirmed','completed')`.
- `commission = ROUND(gross * PLATFORM_COMMISSION_RATE, 2)` (default `0.10`,
  configurable via env; validated to `[0, 1)`).
- `net = gross − commission` — this is the host's accrued earning.

**Payout / wallet semantics:**
- One `payouts` row per event, keyed `UNIQUE(event_id)`, recomputed (never
  incremented) on each accrual/refund so it converges and cannot drift.
- Host `available` balance = `SUM(payouts.gross − commission) − SUM(withdrawals)`
  clamped at 0; over-balance withdrawals are rejected (400).
- `payouts.status` stays **`scheduled`** for all simulated accruals; there is no
  code path that marks real money as paid.

**Architecture (approved earnings-wallet model — kept, no change needed):**
- **Diners**: no stored-money wallet, deposit or transfer (confirmed).
- **Hosts/Influencers**: earnings ledger (`payouts`) + `withdrawals` payout
  history — matches the model. The existing `payouts` table is a per-event
  earnings aggregate (a ledger line), not a cash-payout record, so it stays as-is.
- **Restaurant partners**: settlement/analytics endpoints exist and are role-gated.
- **DineCircle**: platform commission is derived server-side, never client-set.

A separate double-entry ledger is **not** required at this stage; `bookings` +
`refunds` + `payouts` + `withdrawals` give an auditable trail. Revisit only when
a real gateway introduces provider fees, partial refunds and chargebacks.

---

## 4. Concurrency & integrity guarantees now in force

- Seat allocation and check-in use `SELECT ... FOR UPDATE` on the event row.
- Cancellation, decline, check-in, refund recording and payout re-sync share one
  `withTransaction` (BEGIN/COMMIT/ROLLBACK). T11 proves a mid-transaction failure
  rolls the booking, seats and refund back with no partial writes.
- Accrual and withdrawal both take `pg_advisory_xact_lock(hashtextextended(host_id, 7))`
  so an accrual can never race a balance-check/withdrawal pair; `FOR UPDATE` on
  the user row additionally serialises concurrent withdrawals (T10b: two parallel
  full-balance withdrawals → exactly one `201`, one `400`, one row).
- Duplicate refund / duplicate seat release is impossible (status guard + the
  aggregate recompute).

---

## 5. Remaining limitations (all payments are SIMULATED)

These are **intentional**, not defects, and are the gate on any real launch:

1. **No payment provider.** `payment_label` is cosmetic; the checkout "card" is
   a constant string; `refunds.gateway_status` is always `'simulated'`.
2. **No real cash movement.** Nothing is charged, refunded, settled or paid out.
   Host "withdrawals" are ledger requests only; the `requested → completed`
   payout lifecycle is manual and unbacked by a transfer.
3. **Refund amount = full captured total.** The cancellation *policy* is recorded
   as a snapshot for audit, but there is no policy-driven partial-refund
   calculation yet (no "non-refundable within 24h" enforcement).
4. **No webhooks / idempotency keys**, so provider-side retries and asynchronous
   confirmations are not modelled.
5. **No device-runtime verification** — claims come from source + suites + CI.

---

## 6. Blockers to clear before real payment-gateway integration

Do **not** connect a gateway until every item here is addressed; the current
schema is deliberately built to support it, but the code does not yet exercise it:

- [ ] **Gateway selection & secrets** — uncomment/implement Stripe (or
      equivalent) keys in [server/.env.example](server/.env.example); never commit
      real keys.
- [ ] **PaymentIntent creation + confirmation** — replace the cosmetic
      `payment_label` capture with a real authorization → capture flow; set
      `payment_status` only from provider outcomes.
- [ ] **Webhook receiver** with signature verification + idempotency; drive
      `authorized/paid/refunded/failed` transitions from events, not from the client.
- [ ] **Refund lifecycle** — move `refunds.gateway_status` through
      `pending_gateway → confirmed` only on provider confirmation; a `simulated`
      row must never be reported as real money returned.
- [ ] **Policy-driven refund amounts** — compute partial / non-refundable amounts
      from the event's cancellation policy at refund time (schema already stores
      the policy snapshot).
- [ ] **Payout execution** — back host `withdrawals` with a real transfer
      (Stripe Connect / Mass Payouts) and reconcile `payouts.status`; keep the
      earned-balance vs cash-available separation intact.
- [ ] **Currency & rounding** — everything is a single implied USD today; decide
      multi-currency before gateway wiring (`numeric(10,2)` limits apply).
- [ ] **Reconciliation & dispute/chargeback handling** — new ledger states and a
      job to reconcile provider statements against `refunds`/`payouts`.
- [ ] **PCI/3-D Secure scope**, KYC for host payouts, and tax/fee line items.

---

## 7. Suggested order of work

1. Fold the money-path integration suite into CI (`npm run test:integration`
   against a disposable Postgres service) alongside the existing `curl` smoke.
2. Implement policy-driven partial refunds on top of the existing `refunds` row.
3. Integrate the gateway for **capture + refunds only** behind a feature flag; keep
   host payouts simulated until transfer reconciliation exists.
4. Add Stripe Connect payouts with a manual→automated promotion path.
5. Re-audit the ledger under the gateway and extend the integration suite with
   provider-webhook replay tests.

---

## 8. P1 Authentication & Account Management — DELIVERED (2026-10-26)

Scope: email + password is the only exposed authentication path; every
Settings row is wired to a real Express endpoint and PostgreSQL. Phone/OTP
code (routes, `otp_codes` table, repository helpers) is **kept unchanged but
dormant** — it is not surfaced anywhere in the mobile app.

### What was built

| Feature | Endpoint(s) | Notes |
|---|---|---|
| Change password | `POST /auth/change-password` | verifies current password (scrypt), re-hashes new, revokes every **other** session; caller stays signed in |
| Change email | `POST /auth/change-email` → `POST /auth/change-email/confirm` | **new verified flow**: password confirms the request and mints a 6-digit code stored **hashed** in the new `email_change_challenges` table (15-min TTL, one live challenge per user, re-request replaces). Address applies only on correct code; then other sessions are revoked. No mail provider exists, so dev builds return `devCode` (same convention as OTP); prod builds log it — swapping in a mail provider later changes no API shape |
| Privacy settings | `PATCH /users/me` | `showFollowList` / `showActivity` / `allowTagging` enforced server-side on roster/activity reads; `dmFromFollowersOnly` is **stored only** — no DM surface exists yet (event group chats are the only chat) |
| Food preferences | `PATCH /users/me` | `tastes` (≤8), `dietary` (≤12), `allergies` (≤12) |
| Location settings | `PATCH /users/me` | `city` + new free-text `homeArea` (≤80); the GPS picker screen is unchanged |
| Delete account | `DELETE /users/me` | password-confirmed; one transaction cancels the host's open events, refunds guests, releases the departing guest's seats, heals payouts, then **anonymises the row in place** — bookings/reviews/payouts keep their FKs and history (nothing cascades away) |
| Logout all devices | `POST /auth/logout-all` | deletes every `auth_tokens` row for the account, including this device |

### Flutter
- Settings rebuilt to the minimal P1 list (Personal Information, Change
  Email, Change Password, Food Preferences, Location, Privacy & Security,
  Log Out, Logout All Devices, Delete Account) — **no** `_comingSoon` stubs
  and no phone/OTP rows.
- New screens/sheets: `change_password_sheet`, `change_email_sheet`
  (two-step with dev-code banner), `food_preferences_screen`,
  `location_settings_screen`, `privacy_settings_screen` (per-toggle instant
  write, rolls back on API error).
- DTO/model/mapper layer carries the P1 fields (`email`, `homeArea`,
  `dietary`, `allergies`, four privacy booleans); `SessionController` gained
  `updateSettings`, `changePassword`, `requestEmailChange`,
  `confirmEmailChange`, `logoutAllDevices`, `deleteAccount` — with
  `_carryEmail()` because `/users/me` responses deliberately omit PII.

### Verification (all green)
- `npm run typecheck` → clean.
- `npm run test:integration` → **20 / 20**: the 15 money tests plus 5 new
  account tests ([server/src/tests/account.integration.test.ts](server/src/tests/account.integration.test.ts))
  covering password change + session revoke, the full verified email-change
  matrix (wrong password / same email / clash / wrong code / expired code /
  consume / re-confirm), partial settings writes + validation caps,
  logout-all, and delete-account settlement with booking-row preservation.
  `test:integration` now runs under `tsx` (plain `node --test` on Node 24
  cannot resolve the `./util.js` → `.ts` specifiers).
- `flutter analyze` → **0 issues**; `flutter test` → **110 / 110** (7 new
  controller lifecycle tests + 6 new settings widget tests; fakes extended).
- Dev database migrated in place: `email_change_challenges` added; all 116
  existing users, bookings, follows, host profiles and payouts preserved.

### Known limitations (documented, not defects)
- Email verification codes are **simulated delivery** (dev `devCode` /
  server log) until a mail provider is wired.
- `dmFromFollowersOnly` has no enforcement surface (no 1:1 DM endpoint yet).
- Signup still has no email verification, and there is no account lockout —
  carried over from §“security gaps”; the auth rate limiter (10/min default)
  is the only guess throttle.
