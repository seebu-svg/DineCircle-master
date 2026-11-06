# DineCircle — Full Project Audit, MVP Scope & Launch Decision Report

**Audit Date:** 2026-10-26  
**Auditor Role:** Senior Product Manager / CTO / Software Architect / QA Lead  
**Methodology:** Full source inspection (server + Flutter + PostgreSQL schema), automated test execution, code-path tracing, and business-logic analysis. No features were implemented or modified during this audit.

---

## 1. Executive Summary

DineCircle is a **social dining platform** connecting diners with hosts who organize curated dinner events at partner restaurants. After full source inspection, the platform's **Dining Events** journey is functionally complete end-to-end (discovery → booking → attendance → review → host earnings) with real PostgreSQL persistence, transactional booking, and server-side financial logic. The P1 Account Management and P2 Safety & Trust modules are fully shipped and tested.

However, **standard table reservations** ("Book a Table at Restaurant X for 2 people at 8pm") **do not exist** in any form. The entire booking system is built around hosted dinner events. The "Deals & Offers" product concept has a backend read endpoint but no Flutter UI or booking integration. The restaurant partner app has a complete role-gated API but **zero client application**.

**Technical verification:** All gates pass — `flutter analyze` (0 issues), `flutter test` (110 pass), `npm run typecheck` (clean), `npm run test:integration` (31 pass). The codebase is production-quality in its architecture but remains a pre-revenue prototype without payment infrastructure.

**Recommendation:** Launch with **Option A — Dining Events First** (the only fully functional journey), deferred until a payment gateway is integrated. The restaurant reservation product line requires a greenfield subsystem and should be a separate post-launch initiative.

---

## 2. Product Vision

| Element | Current State |
|---|---|
| **Mission** | Make dining more than eating out — discover, book, and connect through food |
| **Target Users** | Diners (discover/book), Hosts (create/manage events), Restaurant Partners (offer venues) |
| **Core Value** | Curated social dining experiences at partner restaurants |
| **Business Model** | Platform commission (configurable, default 10%) on event seat sales |
| **Account Model** | Single unified account; Personal → Professional (host) self-promotion |

### Proposed Core Products vs Reality

| Product | Exists? | Status |
|---|---|---|
| **Book a Table** (standard reservation) | ⬜ No | Not implemented anywhere — no schema, no routes, no UI |
| **Deals & Offers** (packages, discounts) | 🟡 Partial | `special_menus` table + `GET /api/offers` read endpoint; no booking flow, no Flutter screen reachable |
| **Dining Events** (hosted dinners) | ✅ Yes | Complete end-to-end journey with real transactions |

---

## 3. Current Technical Architecture

### System Components

```
Flutter Mobile App (Dart, 107 files, ~30K LOC)
├── State: flutter_riverpod (FutureProvider, AsyncNotifier)
├── HTTP: Dio (bearer interceptor, error mapping, retry, 401 hook)
├── Storage: flutter_secure_storage (auth token)
├── UI: Material 3, dark theme, google_fonts (Inter)
├── Navigation: 5-tab IndexedShell → pushed screens (Navigator)
└── Platform: Android primary, iOS/Web targets exist

Express 5 API (TypeScript ESM, tsx runtime, Node 24)
├── 13 route modules, ~84 handlers, 81 effective endpoints
├── Middleware: helmet → CORS → rate-limit → auth → audit → router
├── Validation: Zod 4 (all request bodies)
├── Realtime: Socket.IO (server-side complete, NO client)
├── DB Access: pg Pool, parameterized SQL, manual transactions
└── Auth: scrypt passwords, SHA-256 hashed bearer tokens, 30-day TTL

PostgreSQL 16
├── 22 tables (users, restaurants, dinner_events, menu_items, bookings,
│   refunds, payouts, withdrawals, collaboration_invites, reviews, follows,
│   venue_follows, saved_events, activity, chat_messages, special_menus,
│   notifications, otp_codes, email_change_challenges, promo_codes,
│   auth_tokens, user_blocks, reports, feedback, audit_log)
├── 30 indexes (FK lookups, composite queries, partial unique for report dedup)
├── Constraints: CHECK enums, UNIQUE, FK with ON DELETE CASCADE/SET NULL
└── Idempotent schema.sql (re-runnable CREATE IF NOT EXISTS + ALTER ADD)

Deployment
├── Docker Compose (Postgres 16 + API container)
├── GitHub Actions CI (typecheck + schema/seed + curl smoke)
├── Debug-signed APK (Android emulator testing)
└── No production VPS deployment yet (HOSTINGER mentioned in NEXT_STEPS)
```

### External Dependencies

| Service | Required | Status |
|---|---|---|
| Payment Gateway (Stripe) | Yes for revenue | ⬜ Not integrated |
| Push Notifications (FCM/APNs) | High priority | ⬜ Not integrated |
| Maps SDK (Google Maps) | Medium | 🟡 Package exists, unused |
| Media Storage (S3/GCS) | Medium | ⬜ Not integrated |
| Email Service (SendGrid/etc.) | For verification | ⬜ Not integrated (dev codes) |
| SMS Provider (Twilio) | Low (OTP dormant) | ⬜ Not integrated |

---

## 4. Actual Development Status

### Feature Inventory

| Feature | Status | Flutter | Backend | Database | Evidence | Launch Relevance |
|---|---|---|---|---|---|---|
| **Registration/Login (email+password)** | Complete | ✅ Working | ✅ Working | ✅ `users`, `auth_tokens` | AuthScreen, `/auth/signup`, `/auth/login` | Essential |
| **Session Restore** | Complete | ✅ Working | ✅ Working | ✅ Token lookup | `sessionControllerProvider`, `/auth/me` | Essential |
| **Profile Management** | Complete | ✅ Working | ✅ Working | ✅ `users` columns | ProfileScreen, `PATCH /users/me` | Essential |
| **Personal → Professional Switch** | Complete | ✅ Working | ✅ Working | ✅ `role` column | `_BecomeHostSheet`, `POST /users/me/host` | Essential |
| **Password Change** | Complete | ✅ Working | ✅ Working | ✅ Scrypt re-hash | ChangePasswordSheet, `POST /auth/change-password` | Important |
| **Email Change (verified)** | Complete | ✅ Working | ✅ Working | ✅ `email_change_challenges` | ChangeEmailSheet, 2-step | Important |
| **Privacy Settings** | Complete | ✅ Working | ✅ Working | ✅ Boolean columns | PrivacySettingsScreen, `PATCH /users/me` | Important |
| **Food Preferences** | Complete | ✅ Working | ✅ Working | ✅ `dietary[]`, `allergies[]` | FoodPreferencesScreen | Nice-to-have |
| **Location Settings** | Partial | ⚠️ City list from MockData | ✅ Working | ✅ `city` column | LocationSettingsScreen | Nice-to-have |
| **Account Deletion** | Complete | ✅ Working | ✅ Working | ✅ Soft-delete anonymise | SettingsScreen, `DELETE /users/me` | Essential |
| **Logout All Devices** | Complete | ✅ Working | ✅ Working | ✅ `auth_tokens` purge | SettingsScreen, `POST /auth/logout-all` | Important |
| **Restaurant Discovery (list)** | Complete | ✅ Live | ✅ Working | ✅ `restaurants` table | ExploreScreen, `GET /restaurants` | Essential |
| **Restaurant Detail** | Complete | ✅ Live | ✅ Working | ✅ | RestaurantDetailScreen | Essential |
| **Restaurant Search/Filters** | Complete | ✅ Live | ✅ Working | ✅ ILIKE + params | ExploreScreen, city/category/price | Essential |
| **Venue Follow** | Complete | ✅ Working | ✅ Working | ✅ `venue_follows` | RestaurantDetail follow button | Nice-to-have |
| **Standard Table Reservation** | Missing | ⬜ No UI | ⬜ No endpoint | ⬜ No schema | Does not exist anywhere | Core product (proposed) |
| **Event Discovery (feed)** | Complete | ✅ Live | ✅ Working | ✅ `dinner_events` | HomeScreen, ExploreScreen, `GET /events` | Essential |
| **Event Detail** | Complete | ✅ Live | ✅ Working | ✅ | DinnerDetailScreen, `GET /events/:id` | Essential |
| **Event Booking (seat)** | Complete | ✅ Live | ✅ Transactional | ✅ `bookings`, FOR UPDATE | CheckoutScreen, `POST /events/:id/bookings` | Essential |
| **Booking History** | Complete | ✅ Live | ✅ Working | ✅ | BookingsScreen, `GET /bookings` | Essential |
| **Booking Cancellation** | Complete | ✅ Live | ✅ Working | ✅ Refund + seat release | BookingsScreen cancel, `DELETE /bookings/:id` | Essential |
| **Check-in** | Complete | ✅ Live | ✅ Working | ✅ `checked_in` flag | QR pass view + partner route | Essential |
| **Digital Pass / QR** | Partial | ⚠️ Decorative QR | ✅ `reference` real | ✅ | BookingConfirmedScreen, `qr_flutter` | Important |
| **Promo Code Validation** | Complete | ✅ Live | ✅ Server-side | ✅ `promo_codes` | CheckoutScreen, pricing.ts | Nice-to-have |
| **Event Creation (wizard)** | Complete | ✅ Live | ✅ Working | ✅ | CreateDinnerScreen, `POST /events` | Essential (host) |
| **Draft/Publish Lifecycle** | Complete | ✅ | ✅ Working | ✅ `status` enum | events.ts status filters | Essential (host) |
| **Guest Management** | Complete | ✅ Live | ✅ Working | ✅ `bookings WHERE event_id` | EventManageScreen | Essential (host) |
| **Approve/Decline Bookings** | Complete | ✅ Live | ✅ Working | ✅ Transaction | EventManageScreen approve/decline | Essential (host) |
| **Host Analytics** | Complete | ✅ Live | ✅ Working | ✅ | AnalyticsScreen, `GET /hosts/:id/performance` | Important (host) |
| **Earnings Wallet** | Complete | ⚠️ Simulated money | ✅ Ledger correct | ✅ `payouts`, `withdrawals` | WalletScreen, `GET /hosts/:id/wallet` | Essential (host) |
| **Withdrawals** | Complete | ⚠️ No real payout | ✅ Advisory-locked | ✅ `withdrawals` | WalletScreen, `POST /hosts/:id/withdrawals` | Essential (host) |
| **Collaboration Invites** | Complete | ✅ Live | ✅ Working | ✅ `collaboration_invites` | HostDashboard | Nice-to-have |
| **Follow/Unfollow** | Complete | ✅ Live | ✅ Working | ✅ `follows` | UserProfileScreen | Nice-to-have |
| **Event Chat (group)** | Complete | ✅ REST polling | ✅ Working | ✅ `chat_messages` | ChatDetailScreen | Important |
| **Real-time Chat (Socket.IO)** | Partial | ⬜ No client | ✅ Server complete | — | server.ts Socket setup | Nice-to-have |
| **Notifications/Activity** | Complete | ✅ Live | ✅ Working | ✅ `activity` | NotificationsScreen, `GET /activity` | Important |
| **Push Notifications** | Missing | ⬜ No FCM | ⬜ No delivery | — | Not implemented | Important |
| **Reviews & Ratings** | Complete | ✅ Live | ✅ Working | ✅ `reviews` | DinnerDetailScreen review composer | Important |
| **Block Users** | Complete | ✅ Live | ✅ Enforced | ✅ `user_blocks` | Safety screens, P2 | Important |
| **Report Content** | Complete | ✅ Live | ✅ Working | ✅ `reports` | ReportSheet, P2 | Important |
| **Send Feedback** | Complete | ✅ Live | ✅ Working | ✅ `feedback` | FeedbackFormScreen, P2 | Important |
| **Offers/Deals Feed** | Partial | ⬜ Screen orphaned | ✅ Read endpoint | ✅ `special_menus` | OffersScreen (unreachable) | Important (proposed) |
| **Offer Booking** | Missing | ⬜ | ⬜ No offer-specific flow | ⬜ | — | Essential (proposed) |
| **Payment Gateway** | Missing | ⬜ Placeholder label | ⬜ All simulated | ⬜ No charges | `payment_label` is cosmetic | P0 Blocker |
| **Real Refunds** | Missing | ⬜ | ⬜ All `gateway_status='simulated'` | ✅ `refunds` table correct | No provider called | P0 Blocker |
| **Media Upload** | Missing | ⬜ Local assets only | ⬜ No endpoint | ⬜ | — | Important |
| **Maps/Directions** | Partial | ⚠️ Package exists | ✅ lat/lng stored | ✅ | MapScreen orphaned, lat/lng in events | Nice-to-have |
| **Admin Console** | Missing | ⬜ No client | 🟡 Role gates exist | ✅ `super_admin` | Partner/report admin routes | Important |
| **Partner Restaurant App** | Missing | ⬜ Zero client | ✅ Complete API | ✅ 536-line partner.ts | Separate app needed | Essential (B2B) |
| **Legal Pages (ToS/Privacy)** | Missing | ⬜ | ⬜ | — | No terms endpoint or screen | P1 Required |
| **CI/CD** | Complete | ✅ | ✅ GitHub Actions | — | server-ci.yml (typecheck + smoke) | Important |
| **Integration Tests** | Complete | — | ✅ 31 tests | ✅ Isolated DB | money + account + safety suites | Essential |
| **Widget Tests** | Complete | ✅ 110 tests | — | — | `flutter test` | Important |

### Mock Data Dependencies (remaining)

| Screen | What's Mocked | Impact |
|---|---|---|
| CreateDinner | Dropdown options (cuisines, dress codes, dietary, policies) | Low — cosmetic option lists, submission is real |
| PreferencesScreen | Interest tags list | Low — onboarding only, values written to API |
| FoodPreferences | Available options array | Low — selection writes real PATCH |
| LocationSettings | City list (static) | Medium — no geocoding, just city text |
| LocationScreen (picker) | Recent locations, city list | Medium — GPS not wired to search |
| Orphaned screens | Full mock datasets | None — unreachable in production |

---

## 5. User Journey Assessment

### Journey 1 — Diner (Dining Events)

```
Register → Browse Events → Select Event → Checkout (pick seats) → 
Receive Booking → View Digital Pass → Attend (host checks in) → Review
```

**Status: ✅ COMPLETE** — Every step reaches PostgreSQL, renders live data, and has automated test coverage.

| Step | Evidence |
|---|---|
| Register | `POST /auth/signup` → users row, `auth_tokens` row |
| Browse | `GET /events` → audience-gated feed, filters, ILIKE search |
| Select | `GET /events/:id` → detail, menu, host, venue, reviews |
| Checkout | `POST /events/:id/bookings` → transaction, seat lock, server pricing |
| Confirmation | Booking row + reference; BookingConfirmedScreen renders it |
| Pass | Decorative QR (seeded from real reference ID) |
| Check-in | `POST /bookings/:id/checkin` → `checked_in=true` |
| Review | `POST /events/:id/reviews` → gated to completed bookings |

### Journey 1b — Diner (Standard Table Reservation)

**Status: ⬜ DOES NOT EXIST**

The entire reservation system for "book a table at restaurant X for date/time/party-size" has no implementation. The `bookings` table FKs to `dinner_events`, not to restaurants directly. The restaurant `accepting_bookings` boolean is stored but has no reservation endpoint.

### Journey 1c — Diner (Offers/Deals)

**Status: ⬜ NOT VERIFIED (orphaned)**

`GET /api/offers` returns active `special_menus` but:
- OffersScreen is never navigated to
- No offer-specific booking flow exists
- No redemption tracking
- No coupling to `bookings` table

### Journey 2 — Professional Host

```
Register → Promote to Host → Select Restaurant → Create Event (6-step wizard) → 
Publish → Receive Booking Requests → Manage Guests (approve/decline) → 
Complete Event → View Earnings → Withdraw
```

**Status: ✅ COMPLETE (simulated money)**

| Step | Evidence |
|---|---|
| Promote | `POST /users/me/host` |
| Create | `POST /events` (host-gated), full wizard |
| Publish | `status` transitions: draft → confirmed → live → completed |
| Guests | `GET /bookings?eventId=` (host-checked) |
| Approve/Decline | `POST /bookings/:id/approve` or `/decline` |
| Earnings | `GET /hosts/:id/performance`, `GET /hosts/:id/wallet` |
| Withdraw | `POST /hosts/:id/withdrawals` (advisory-locked) |
| Reviews | Guests post reviews gated to completed bookings |

### Journey 3 — Restaurant Partner

```
Restaurant Listed → Offer/Availability Configured → Receive Event/Booking → 
Confirm → Serve → Track Revenue
```

**Status: ⬜ NOT VERIFIED — No Partner Client Exists**

The server provides a complete role-gated API (`/api/partner/*`):
- Restaurant CRUD
- Event creation for restaurant
- Booking list + check-in
- Special menu management
- Analytics dashboard
- Notifications

However, there is **zero Flutter UI for this role** in this repository. The `DineCirclePartner` application is referenced in prior audit notes as a separate project but does not exist in this workspace.

---

## 6. Proposed MVP Scope

### IN SCOPE — Launch Essential

| Feature | Readiness | Gap |
|---|---|---|
| Event discovery & booking | ✅ Complete | — |
| Host event creation | ✅ Complete | — |
| Payment capture (real) | ⬜ Missing | Stripe PaymentIntents + webhooks |
| Refund execution (real) | ⬜ Missing | Gateway-driven refund lifecycle |
| Host payout execution | ⬜ Missing | Stripe Connect or mass payouts |
| Digital pass (real QR) | ⬜ Partial | QR generation library exists, content is decorative |
| Push notifications | ⬜ Missing | FCM/APNs + delivery |
| Email verification (signup) | ⬜ Missing | Mail provider + token flow |
| Legal (ToS, Privacy) | ⬜ Missing | Content + display screens |
| Production deployment | ⬜ Partial | Docker exists; VPS config pending |
| SSL/HTTPS | ⬜ Required | Not configured |
| Backup & disaster recovery | ⬜ Missing | No automated pg_dump |

### CONDITIONAL — Launch Decision Required

| Feature | Cost if included | Risk if excluded |
|---|---|---|
| Standard table reservations | High (new subsystem) | Diner product line incomplete |
| Deals & Offers | Medium (UI + booking) | Reduced discovery variety |
| Restaurant follow | Low (already exists) | Minor |
| Real-time chat | Low (client wiring only) | Chat still works via polling |
| Maps integration | Medium (SDK setup + permissions) | No navigation to venues |
| Review system | Low (already complete) | No social proof |
| Influencer tier | Low (already complete) | Reduced host motivation |

### OUT OF SCOPE — Future Releases

- Social feed / Instagram-like content
- Multi-city launch (start with one city)
- Group booking / split payments
- Loyalty program
- Multilingual support
- Offline mode / caching
- Analytics platform (Mixpanel/Amplitude)

### REMOVE OR DEFER

| Item | Recommendation | Reason |
|---|---|---|
| 5 orphaned screens | DELETE | Dead code, never reachable, creates confusion |
| MockData option lists | REPLACE with server enum | Already partially done; finish it |
| Phone/OTP path | DEFER (keep dormant) | No SMS provider, adds dead branches |
| `is_demo` flag | REMOVE after seed data cleanup | Production rows should never carry it |
| `notifications` table | DEFER | Partner-only, no consumer delivery path |
| `special_menus` (unused) | CONDITIONAL | Keep if Offers is in launch scope |

---

## 7. Launch Strategy Comparison

### Option A — Dining Events First

| Dimension | Assessment |
|---|---|
| **Already working** | 90% of the codebase — event feed, detail, booking, host studio, reviews, chat, safety |
| **Missing development** | Payment gateway (2–4 weeks), push notifications (1–2 weeks), real QR (2 days), production deploy (3 days), legal (content only) |
| **Complexity** | Low incremental — the system is designed for this journey |
| **Technical risks** | No real money testing, payment webhook race conditions (new surface) |
| **Development effort** | ~4–6 weeks to production-ready |
| **Business value** | Validates the core hypothesis: "people pay for curated dining experiences" |
| **Customer demand test** | Direct — each booking is a conversion event |
| **Partner requirement** | Need 2–5 restaurants willing to host events; currently seeded with fictional data |

### Option B — Restaurant Booking First

| Dimension | Assessment |
|---|---|
| **Already working** | Restaurant discovery (list/detail/search); auth infrastructure |
| **Missing development** | ENTIRE reservation system: availability, date-time-slot selection, party size, restaurant confirmation workflow, no-show handling, cancellation policy, table management, partner confirmation UI. Plus payment gateway. |
| **Complexity** | Very high — requires new schema, new routes, new screens, new partner workflow |
| **Technical risks** | Real-time availability (concurrent booking), restaurant timezone handling, no-show policy |
| **Development effort** | ~10–14 weeks to production-ready |
| **Business value** | Competes with OpenTable/Resaas — mature market |
| **Customer demand test** | Requires high restaurant density to be useful |
| **Partner requirement** | Need 20+ restaurants with available tables |

### Option C — Combined MVP

| Dimension | Assessment |
|---|---|
| **Already working** | Events (90%) |
| **Missing development** | Events polish + entire Option B build |
| **Complexity** | Highest — two distinct booking models in one app |
| **Development effort** | ~14–18 weeks |
| **Business value** | Maximum breadth but diluted focus |
| **Risk** | Launch scope creep, both journeys half-done |

### Recommendation

**Option A (Dining Events First)** is the clear winner based on evidence:
1. It is the only journey that works end-to-end today.
2. It requires the least additional development (only payment + ops).
3. It directly tests the business hypothesis with minimal supply requirements (2–5 restaurants).
4. It is architecturally coherent — no new subsystem needed.
5. Every other product line (reservations, offers) can be added incrementally once revenue flows.

---

## 8. Critical Bugs & Risks

### P0 — Launch Blockers

| # | Finding | Impact | Fix |
|---|---|---|---|
| 1 | No payment gateway — bookings store cosmetic `payment_label`, money never moves | Platform generates zero revenue | Stripe PaymentIntents + Webhooks |
| 2 | No email verification on signup | Spam accounts, no ownership proof | Mail provider + confirmation token |
| 3 | No production HTTPS/deployment | Man-in-the-middle, browser warnings | SSL cert + production domain |
| 4 | No automated backup | Total data loss risk | Daily `pg_dump` + rotation |
| 5 | Rate limiter secrets are defaults in compose | Brute-force vulnerable | Environment-specific secrets |

### P1 — Required Before Public Launch

| # | Finding | Impact | Fix |
|---|---|---|---|
| 1 | No push notifications | Users miss bookings, cancellations, messages | FCM/APNs setup + activity webhook |
| 2 | QR pass is decorative (not scannable) | Check-in workflow requires manual lookup | Use `qr_flutter` with real ISO 2D barcode |
| 3 | Chat is 5s polling (not realtime) | Perceived as laggy, battery drain | Wire Socket.IO client |
| 4 | No account lockout | Brute-force on password | Incremental delay / lockout policy |
| 5 | Maps screen orphaned | No directions to venues | Wire existing `MapScreen` with `google_maps_flutter` |
| 6 | No legal pages | Regulatory risk | ToS + Privacy Policy screens |
| 7 | Host withdrawals have no real payout | Host trust issue | Stripe Connect or manual reconciliation |
| 8 | Home feed has `RenderFlex` overflow on narrow screens | Visual bug on small devices | Responsive pass |
| 9 | No monitoring/alerting | Silent failures go unnoticed | Sentry/error tracking + uptime monitor |

### P2 — Can Follow After Launch

| # | Finding |
|---|---|
| 1 | Offers screen orphaned — backend exists but no UI |
| 2 | Partner API complete but no dedicated restaurant app |
| 3 | Admin/moderation API exists but no console |
| 4 | `dmFromFollowersOnly` stored but no DM surface exists |
| 5 | Location picker uses static city list (no geocoding) |
| 6 | Create dinner uses MockData for dropdown options |
| 7 | Standard table reservation feature (by design — Option B) |

### P3 — Future Enhancement

| # | Finding |
|---|---|
| 1 | Recommendation engine |
| 2 | Multi-currency support |
| 3 | Offline caching |
| 4 | iOS build |
| 5 | Web client |
| 6 | Loyalty/rewards program |

---

## 9. Development Gap Analysis

### For Option A Launch (Dining Events First)

| Task | Effort | Priority |
|---|---|---|
| Stripe PaymentIntents (create + confirm + webhook) | 2–3 weeks | P0 |
| Stripe Connect for host payouts | 1–2 weeks | P0 |
| Email verification on signup | 1 week | P0 |
| Real QR generation | 2 days | P1 |
| FCM/APNs push delivery | 1 week | P1 |
| Socket.IO Flutter client | 3 days | P1 |
| Production VPS deployment | 3–5 days | P0 |
| SSL + domain + backup automation | 2 days | P0 |
| Rate-limit hardening + account lockout | 2 days | P1 |
| Legal pages (content + screens) | 2 days | P1 |
| Real QR check-in scanner (host side) | 3 days | P1 |
| Monitoring (Sentry + uptime) | 1 day | P1 |
| Remove orphaned screens / dead code | 1 day | P2 |
| Responsive fix (Home overflow) | 2 days | P2 |
| Seed data cleanup → real restaurant partners | Operational | P0 |

**Total estimated development effort: 6–8 weeks**

### Minimum Operational Requirements

1. **2–5 partner restaurants** willing to host events (currently fictional seed data)
2. **1–3 active hosts** who can create and run the first events
3. **Payment provider account** (Stripe)
4. **Email/SMS delivery account** (SendGrid / SES)
5. **VPS hosting** (Hostinger or equivalent)
6. **Legal review** of terms and privacy policy

---

## 10. Recommended Launch Roadmap

### Milestone 1: Infrastructure (Week 1–2)
- [ ] Stripe account setup + API keys
- [ ] Production VPS provisioned (Node 24 + PostgreSQL 16 + Docker + Nginx)
- [ ] SSL certificate + domain
- [ ] CI/CD → deploy pipeline (GitHub Actions → SSH deploy)
- [ ] Database backup + recovery runbook
- [ ] Error monitoring (Sentry)

**Acceptance:** Health endpoint returns `{"status":"ok"}` over HTTPS; automated backup restores to fresh instance.

### Milestone 2: Payment Integration (Week 2–4)
- [ ] Stripe PaymentIntents on booking (authorize + capture)
- [ ] Webhook receiver (payment_intent.succeeded, charge.refunded)
- [ ] Refund lifecycle: `pending_gateway → confirmed`
- [ ] Host payouts via Stripe Connect (Express or Standard)
- [ ] Withdrawal → real transfer execution

**Acceptance:** A test booking charges a Stripe test card, the host sees real earnings, and a refund reverses both.

### Milestone 3: Communication & Safety (Week 4–5)
- [ ] FCM push notification on booking/cancellation/message
- [ ] Email verification signup flow
- [ ] Account lockout after 5 failed attempts
- [ ] Real QR code on digital pass (scannable ISO)
- [ ] Legal screens (Terms + Privacy)

**Acceptance:** Cold install → signup → email verify → book → push arrives → host checks in via scanner.

### Milestone 4: Experience Polish (Week 5–6)
- [ ] Socket.IO realtime chat (replace polling)
- [ ] Maps integration (directions to venue)
- [ ] Responsive layout fix
- [ ] Remove orphaned screens and dead code
- [ ] Load test: 100 concurrent bookings without conflict

**Acceptance:** Chat updates <1s; venue shows map + directions; zero test regressions.

### Milestone 5: Beta Launch (Week 6–8)
- [ ] Seed real restaurants (2–5 partners onboarded)
- [ ] Invite 20–50 beta diners + 3–5 hosts
- [ ] Feedback channel (existing P2 Feedback system)
- [ ] Monitor error rates, booking conversion, support tickets
- [ ] Iterate on friction points

---

## 11. Decisions Required From Founder

These cannot be resolved by inspecting code:

| # | Decision | Options | Impact |
|---|---|---|---|
| 1 | **Payment provider** | Stripe / Razorpay / Local gateway (Pakistan context) | Determines integration timeline |
| 2 | **Geographic launch** | Single city (Karachi) vs multi-city | Affects partner supply density needed |
| 3 | **Restaurant supply** | Do we have real partner restaurants ready? Current DB has fictional seed data | Cannot launch without at least 2 venues |
| 4 | **Host pipeline** | Who hosts the first events? Internal team or external creators? | Determines whether beta is self-fulfilling |
| 5 | **Pricing model** | 10% commission (configurable) — is this viable for the target market? | Business viability |
| 6 | **Partner app** | Build dedicated restaurant UI or extend admin panel in main app? | Scope + timeline |
| 7 | **Table reservations** | Include in launch roadmap or defer to post-launch? | 8+ weeks additional scope |
| 8 | **Offers/Deals** | Wire existing backend or defer? | 2 weeks additional |
| 9 | **Brand/Content** | Legal terms, app store listing, marketing copy | Launch readiness |
| 10 | **iOS** | Launch Android-only or both? | Extra testing + signing |

---

## 12. Final Recommendation

**Launch with Dining Events only, in one city, with 2–5 partner restaurants and a real payment gateway.**

The evidence is clear:
1. The event journey is **fully functional** end-to-end with 31 integration tests proving correctness.
2. Standard table reservations require a greenfield subsystem that does not exist and would add 10+ weeks.
3. Offers have a backend but no UI or booking flow.
4. The Partner API is complete but has zero client.
5. The social layer (follow, chat, reviews, safety) is wired and adds engagement value without additional scope.

The smallest viable launch that delivers genuine dining value:
- **Diners** browse curated dining events, book seats, attend, and review.
- **Hosts** create events at partner restaurants, manage guests, and earn commission-based revenue.
- **Restaurants** are onboarded manually (no self-serve partner app needed for 2–5 venues).
- **Money** flows through Stripe (the only missing critical piece).

This validates the core hypothesis ("people pay for social dining experiences") before expanding into adjacent product lines.

---

## Appendix A: Technical Verification Results

| Command | Result | Date |
|---|---|---|
| `flutter analyze` | 0 issues | 2026-10-26 |
| `flutter test` | 110/110 pass | 2026-10-26 |
| `npm run typecheck` (server) | Clean | 2026-10-26 |
| `npm run test:integration` | 31/31 pass | 2026-10-26 |
| — Money suite | 15 pass | 2026-10-26 |
| — Account suite | 5 pass | 2026-10-26 |
| — Safety suite | 11 pass | 2026-10-26 |
| `docker compose` (dev) | Postgres 16 healthy | Verified |
| CI workflow | typecheck + curl smoke (server-ci.yml) | Exists, not tested live |

## Appendix B: Database Table Relationships

```
users ─┬─→ dinner_events (host_id)
       ├─→ bookings (user_id) ──→ dinner_events (event_id)
       ├─→ follows (follower_id ↔ followee_id)
       ├─→ saved_events (user_id ↔ event_id)
       ├─→ activity (actor_id = recipient)
       ├─→ auth_tokens (user_id)
       ├─→ user_blocks (blocker_id → blocked_id)
       ├─→ reports (reporter_id)
       ├─→ feedback (user_id)
       ├─→ reviews (author_id → event_id)
       ├─→ withdrawals (host_id)
       └─→ collaboration_invites (host_id → restaurant_id)

restaurants ─┬─→ dinner_events (restaurant_id)
             ├─→ special_menus (restaurant_id)
             ├─→ notifications (restaurant_id)
             └─→ venue_follows (user_id ↔ restaurant_id)

dinner_events ─┬─→ menu_items (event_id)
               ├─→ bookings (event_id)
               ├─→ refunds (event_id)
               ├─→ payouts (event_id)
               ├─→ chat_messages (event_id)
               └─→ reviews (event_id)
```

## Appendix C: Endpoint Summary by Feature Area

| Area | Endpoints | Auth | Notes |
|---|---|---|---|
| Authentication | 12 routes | Mixed (public + bearer) | Signup, login, OTP (dormant), me, signout, change-password/email/phone, logout-all |
| Events | 7 routes | Bearer | Feed, detail, create, delete, cancel, by-host, by-venue |
| Bookings | 6 routes | Bearer | List, create, cancel, check-in, approve, decline |
| Restaurants | 3 routes | Bearer | List, detail, nearby (with coords) |
| Users | 12 routes | Bearer | Profile CRUD, settings, search, host-promote, tier, influencer, block/unblock/blocked |
| Hosts | 7 routes | Bearer | Summary, payouts, wallet, withdrawals, performance, trend, collaborators |
| Social | 8 routes | Bearer | Follow, unfollow, save, unsave, activity, mark-read, follow-status |
| Chat | 2 routes | Bearer | List messages, send message |
| Reviews | 2 routes | Bearer | List, post |
| Reports (P2) | 3 routes | Bearer | Submit, list mine, admin-update |
| Feedback (P2) | 2 routes | Bearer | Submit, list mine |
| Offers | 1 route | Bearer | List active deals |
| Partner | 11 routes | Bearer + role | Restaurant CRUD, events, bookings, check-in, menus, analytics, notifications |
| Socket.IO | 6 handlers | Bearer handshake | join/leave event rooms, join/leave restaurant, chat broadcast |

**Total: ~81 effective REST endpoints + Socket.IO**

---

*End of Report*
