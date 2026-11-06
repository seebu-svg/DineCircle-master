# DineCircle — Partner App API

Contract for the **DineCircle Partner App** (restaurants & cafés). It talks to the
same server and the same PostgreSQL database as the Customer App, so anything a
venue changes here is visible to diners immediately (and vice versa).

- Base URL: `https://<host>/api`
- Content type: `application/json`
- All timestamps are ISO-8601 UTC; the server resolves venue-local "today" from
  the branch timezone, never from the device clock.

---

## 1. Authentication

```http
POST /api/auth/signup        { name, email, password }
POST /api/auth/login         { email, password }
```

Both return `{ token, user }`. Send the token on every request:

```http
Authorization: Bearer <token>
```

- Tokens are opaque 256-bit secrets stored **hashed** (`sha256`) in `auth_tokens`.
  The database never holds a usable token, and no mobile app ever sees a
  database credential or a gateway secret.
- `POST /api/auth/signout` revokes the current token, `POST /api/auth/logout-all`
  revokes every session for the account, `GET /api/auth/me` re-hydrates the
  caller's profile from the token.
- Partner surfaces require a partner context; a plain diner receives
  `403 { "error": "Partner access requires a restaurant account" }`.

## 2. Roles

Platform role (`users.role`): `user` · `host` · `influencer` · `partner_admin` ·
`restaurant_owner` · `restaurant_staff` · `super_admin`.

Venue role (`restaurant_staff.role`, the per-venue ladder):

| Venue role | Rank | May do |
|---|---|---|
| `staff` | 1 | read venue data, day list, check-in, reservation status changes |
| `manager` | 2 | + edit profile/branches/hours, menu, tables, deals, event approvals, earnings |
| `owner` | 3 | + manage staff |

`restaurants.owner_id` counts as an implicit `owner`, so accounts created before
`restaurant_staff` existed keep working unchanged. Every handler resolves the
caller's effective role for **the venue in the path**; there is no
"my restaurant" fallback and no venue id is trusted from the client without a
membership check.

Distinguishability is deliberate and part of the contract:

| Situation | Status |
|---|---|
| no/invalid token | `401` |
| token is a diner, or a partner reaching an unrelated venue | `403` |
| venue id does not exist | `404` |
| stale state (already reviewed, already seated, slot taken) | `409` |
| invalid body/query | `400` (or `422` for semantically unknown references) |

`super_admin` bypasses venue scoping (`scopedRestaurantIds` → `'all'`) and is the
only role that can review verification requests.

## 3. Response envelope

Every partner endpoint answers the same shape.

```jsonc
// list
{ "data": { "tables": [ ... ] }, "meta": { "page": 1, "limit": 50, "total": 12, "hasMore": false } }

// single resource
{ "data": { "restaurant": { ... } } }

// error
{ "error": "Human readable message", "issues": [ { "path": "title", "message": "..." } ] }
```

`issues` is present only for validation failures. Errors never leak SQL, stack
traces or table names.

**Pagination** — list endpoints accept `?page=` (1-based) and `?limit=` (max 200)
and return `meta.page/limit/total/hasMore`. Legacy operations routes (`/partner/events`,
`/partner/bookings`, `/partner/menus`, `/partner/notifications`) keep their
`limit`-only contract and report `meta.total` for the page they returned.

Verified convenience flag: `restaurant.verified` is `partnership_status ===
'verified' && is_partner`. It is the single predicate behind every selling gate —
use it instead of re-deriving the pair.

---

## 4. Endpoint inventory

### 4.1 Registration & verification

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` | `/partner/restaurants` | partner | venues this account may operate (`myRole` per row) |
| `POST` | `/partner/restaurants` | any signed-in account | self-service registration → venue `pending_review`, primary branch, verification request, caller linked as `owner` |
| `GET` | `/partner/restaurants/:id` | staff | profile + `counts` (branches, tables, menu items, upcoming events, pending reservations) |
| `PATCH` | `/partner/restaurants/:id` | manager | profile, hours defaults, `acceptingBookings`, `requiresHostApproval` |
| `POST` | `/partner/restaurants/:id/verification` | manager | (re)open a verification request, e.g. after a rejection |
| `GET` | `/partner/verification/requests?status=pending` | super_admin | platform-wide review queue |
| `POST` | `/partner/verification/requests/:requestId/review` | super_admin | `{ decision: 'approved'\|'rejected', reviewerNote }`; sets `partnership_status`/`is_partner`, notifies the venue, 409 on re-review |

Registration is intentionally open to any signed-in account (a diner becomes a
`restaurant_owner`); nothing is sellable until a `super_admin` approves.

### 4.2 Staff & branches

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` | `/partner/restaurants/:id/staff` | staff | roster with roles/status |
| `POST` | `/partner/restaurants/:id/staff` | owner | invite by email + role |
| `POST` | `/partner/restaurants/:id/staff/accept` | invitee | accept an invite (invited staff are inert until they do) |
| `PATCH` | `/partner/restaurants/:id/staff/:userId` | owner | change role (staff ↔ manager; owner transfer) |
| `DELETE` | `/partner/restaurants/:id/staff/:userId` | owner | revoke membership |
| `GET` `POST` | `/partner/restaurants/:id/branches` | staff / manager | list, create (one primary at a time) |
| `PATCH` `DELETE` | `/partner/restaurants/:id/branches/:branchId` | manager | edit / remove |
| `GET` `PUT` | `/partner/restaurants/:id/branches/:branchId/hours` | staff / manager | weekly `opening_hours` + `timezone` |

`opening_hours` shape (all seven weekdays optional; a missing day means "not
configured"):

```json
{ "mon": { "closed": false, "windows": [{ "open": "18:00", "close": "23:00" }] } }
```

These windows drive the customer-facing availability slots (90-minute settings,
30-minute step), interpreted in the branch `timezone`.

### 4.3 Menu & pricing

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` | `/partner/restaurants/:id/menu` | staff | sections with items, availability flags |
| `POST` | `/partner/restaurants/:id/menu/sections` | manager | create section |
| `PATCH` `DELETE` | `/partner/restaurants/:id/menu/sections/:sectionId` | manager | rename / reorder / delete |
| `POST` | `/partner/restaurants/:id/menu/items` | manager | create item (price is server-held; negative/zero rejected) |
| `PATCH` `DELETE` | `/partner/restaurants/:id/menu/items/:itemId` | manager | edit / remove |
| `POST` | `/partner/restaurants/:id/menu/availability` | manager | 86-list: mark items unavailable (idempotent, scoped to the venue) |

### 4.4 Tables, availability & reservations

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` `POST` | `/partner/restaurants/:id/tables` | staff / manager | inventory (`label`, `seats`, `isActive`) |
| `PATCH` `DELETE` | `/partner/restaurants/:id/tables/:tableId` | manager | edit / deactivate |
| `GET` | `/partner/restaurants/:id/availability?date=&partySize=` | staff | slot list with seats left |
| `GET` | `/partner/restaurants/:id/reservations?date=&status=&from=&to=` | staff | day list (dates resolved in the branch timezone) |
| `POST` | `/partner/restaurants/:id/reservations` | staff | phone-in booking (`guestName`, `partySize`, `startAt`, optional `branchId`/`tableId`/`notes`); created `pending` unless `status` is passed |
| `POST` | `/partner/restaurants/:id/reservations/:reservationId/:action` | staff | `confirm` · `seat` · `complete` · `cancel` · `no-show` |
| `GET` | `/partner/restaurants/:id/reservations/:reservationId` | staff | single reservation |

Capacity is `SUM(restaurant_tables.seats)` when the venue publishes inventory,
otherwise `restaurants.seats`. Statuses that hold covers: `pending`, `confirmed`,
`seated`. Legal transitions: `pending → confirmed|cancelled|no_show`,
`confirmed → seated|cancelled|no_show`, `seated → completed`. Anything else is a
`409`.

**Concurrency.** Creation locks the venue row first (`SELECT … FOR UPDATE`) and
then the table, so two guests racing for the last covers always resolve to one
`201` and one `409` — never two seated parties on one table. Verified in
`src/tests/partner.integration.test.ts`.

### 4.5 Customer-facing reservation routes (same backend, Customer App)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `GET` | `/restaurants/:id/availability` | public | bookable slots |
| `POST` | `/restaurants/:id/reservations` | customer | request a table (always `pending`, notifies the venue) |
| `GET` | `/users/me/reservations` | customer | own reservations, live status |
| `POST` | `/reservations/:reservationId/cancel` | customer | cancel own reservation |

A desk confirmation made in the Partner App is what the diner sees on
`GET /users/me/reservations`; there is no second source of truth.

### 4.6 Dining events & host approvals

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` | `/partner/restaurants/:id/dashboard` | staff | operational home: today's service counts/covers/capacity/occupancy, events, pending requests, deals, unread notifications, month-to-date earnings |
| `GET` | `/partner/restaurants/:id/event-requests?status=requested` | staff | host events awaiting a decision |
| `POST` | `/partner/restaurants/:id/event-requests/:eventId/approve` | manager | publish a requested event (409 unless `requested`), writes an `approval` activity for the host + venue notification |
| `POST` | `/partner/restaurants/:id/event-requests/:eventId/decline` | manager | `{ reason }` (≤500 chars), persists `decline_reason` |

Policy: a venue with `requiresHostApproval = true` intercepts host publishing —
the event is created as `requested`, which is **invisible and unbookable** to
diners (`404` on detail and booking) until approved. Venues without the flag
publish immediately (`confirmed`).

### 4.7 Venue-owned events, bookings, check-in

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `POST` | `/partner/events` | manager | create a venue event (published `confirmed`, acting operator recorded as host) |
| `PUT` | `/partner/events/:id` | manager | partial update; only the keys you send are written, empty body → `400` |
| `GET` | `/partner/events?status=` | partner | events across every venue the caller operates |
| `GET` | `/partner/bookings?eventId=&status=` | partner | ticket sales |
| `POST` | `/partner/bookings/:id/checkin` | staff | door check-in (409 if cancelled/already checked in) |
| `POST` `GET` | `/partner/menus` | partner | special/chef menus (priced per guest) |
| `GET` | `/partner/analytics` | partner | revenue, covers, fill rate, recent bookings |

### 4.8 Deals & promotions

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` | `/partner/restaurants/:id/deals?status=` | staff | list (paginated) |
| `POST` | `/partner/restaurants/:id/deals` | manager | create (`title`, `description`, `kind: percent\|fixed\|package`, `value`, `code`, `startsAt`, `endsAt`, `maxRedemptions`); venue must be **verified** (`403` otherwise) |
| `PATCH` | `/partner/restaurants/:id/deals/:dealId` | manager | edit / transition status |
| `DELETE` | `/partner/restaurants/:id/deals/:dealId` | manager | drafts are deleted; anything live is retired to `expired` |

Transitions: `draft → active|expired`, `active → paused|expired`,
`paused → active|expired`, `expired → (terminal)`. Percent deals are capped at
100, `endsAt` must be in the future and after `startsAt`. Codes are normalised to
upper case and unique per venue (`409` on clash). Deals are retired rather than
deleted so a guest holding a code gets a clear "expired" instead of a crash.

### 4.9 Earnings, payouts

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` | `/partner/restaurants/:id/earnings?from=&to=` | manager | last 30 days by default: `gross` (paid bookings), `refunds` (`status='refunded'`), `commission` (`PLATFORM_COMMISSION_RATE`, default 10%), `net`, plus `payouts.pending/paid` and `lastPaidAt` from `restaurant_payouts` |
| `GET` | `/partner/restaurants/:id/payouts` | manager | payout history (paginated) |

Commission is configuration, not a constant in the app: `PLATFORM_COMMISSION_RATE`
is env-overridable and echoed back as `earnings.commissionRate` so the app never
hardcodes a percentage. Refunds are subtracted before commission, so a cancelled
booking cannot leave commission owed on money that was returned.

### 4.10 Notifications

| Method | Path | Min role | Purpose |
|---|---|---|---|
| `GET` | `/partner/notifications?unreadOnly=true` | partner | inbox across operated venues; `meta.unread` for the badge |
| `POST` | `/partner/notifications/:notificationId/read` | partner | acknowledge one (`404` if it is not yours) |
| `POST` | `/partner/notifications/read-all` | partner | acknowledge everything in scope, returns `{ data: { updated } }` |

---

## 5. Shared data the Partner App can rely on

| Concept | Table(s) | Owned API |
|---|---|---|
| Accounts, roles, sessions | `users`, `auth_tokens` | `/auth/*`, `/users/me/*` |
| Venues, branches, hours | `restaurants`, `restaurant_branches` | `/partner/restaurants/*` |
| Membership & role ladder | `restaurant_staff` | `/partner/restaurants/:id/staff` |
| Verification | `partner_verification_requests` | `/partner/verification/*` |
| Menu | `restaurant_menu_sections`, `restaurant_menu_items` | `/partner/restaurants/:id/menu/*` |
| Tables & reservations | `restaurant_tables`, `table_reservations` | `/partner/restaurants/:id/tables|reservations`, `/restaurants/:id/reservations` |
| Dining events | `dinner_events` (+ `restaurant_approved_at/by`, `decline_reason`) | `/partner/restaurants/:id/event-requests`, `/events` |
| Deals | `restaurant_deals` | `/partner/restaurants/:id/deals` |
| Money | `bookings`, `refunds`, `payouts`, `withdrawals`, `restaurant_payouts` | `/partner/restaurants/:id/earnings|payouts` |
| Trust & comms | `reviews`, `notifications`, `activity`, `audit_log` | `/reviews`, `/partner/notifications` |

Customer-authored content (events, bookings, payments, reviews) is read through
the same tables — the Partner App must never write a customer-facing price or a
payment status directly except through the endpoints above, which own the
validation.


## Subscription & Billing

> **Important:** DineCircle does **not** collect payment in the app. There is no
> wallet, no card capture, and no in-app payment gateway. Both subscription plans
> (Monthly and Yearly) offer the same Pro features. Billing is arranged directly
> with DineCircle.

### GET /api/partner/restaurants/:restaurantId/subscription

Returns the venue's current subscription. When no row exists the response is a
synthetic default (`status: 'none'`, `plan: null`).

**Requires:** venue role (staff or above).

```json
{
  "data": {
    "subscription": {
      "id": "uuid",
      "restaurantId": "uuid",
      "plan": "monthly",
      "status": "active",
      "pricePkr": 5000,
      "periodStart": "2025-01-01T00:00:00Z",
      "periodEnd": "2025-02-01T00:00:00Z",
      "autoRenew": true,
      "cancelledAt": null,
      "createdAt": "...",
      "updatedAt": "..."
    }
  }
}
```

### PATCH /api/partner/restaurants/:restaurantId/subscription

Records the partner's plan intent. Only the venue **owner** may change the
subscription. The server sets `price_pkr` from a constant — the client can
never send a custom price.

**Requires:** venue role `owner`.

**Body:**

| Field       | Type      | Description                                        |
|-------------|-----------|----------------------------------------------------|
| `plan`      | `string`  | `'monthly'` or `'yearly'`                          |
| `autoRenew` | `boolean` | Whether the plan renews at the end of the period   |
| `status`    | `string`  | `'active'` to activate, `'cancelled'` to cancel    |

When `plan` changes, the server sets `period_start = now()` and
`period_end = now() + 1 month` (or `+ 12 months` for yearly).

**Plan prices (server-side constants):**

| Plan      | Price (PKR) |
|-----------|-------------|
| `monthly` | 5,000       |
| `yearly`  | 50,000      |

The yearly plan saves PKR 10,000 compared to paying monthly.

## 6. Local development

```bash
cd server
npm run db:setup      # schema + seed against DATABASE_URL
npm run dev           # API on :4000
npm test              # typecheck + integration suite (isolated DB per file)
```

The seed creates a partner-ready desk account
`karachi.desk+demo@example.test` / `dinecircle123` (owns 10 venues), a verified
venue with tables/menu/deal (`…aaa1`), and an unverified venue that requires host
approval (`…aaa2`).
