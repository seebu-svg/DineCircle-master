# DineCircle Phase 2 implementation report

Date: 2026-11-03. Outcome: **Partially complete; release readiness remains blocked.**

This phase implemented local security repairs and regression tests. It did not deploy, apply schema, run seeds, alter customer accounts, or change production data. No migrations were created. No frontend files were modified. The installed schema, Supabase project, and full endpoint behavior have not been verified.

## A. Verified architecture and runtime boundaries

- Customer Flutter source: `DineCircle-master/lib`; Partner Flutter source: `partnerapp/lib`.
- Shared Express 5 service: `DineCircle-master/server/src/server.ts`. The backend is embedded in the Customer project; no second backend was introduced.
- Both client configurations append `/api` to an API root; development defaults to localhost:4000. Customer production defaults to api.dinecircle.com; Partner defaults to localhost unless `API_BASE_URL` is explicitly supplied. Deployment configuration must point both builds to the same service; actual deployed targets were not accessible.
- PostgreSQL access is `pg.Pool` in `src/db.ts`, using `DATABASE_URL` through `database_config.ts`. Default pool maximum is 10, idle timeout 30 seconds, connection timeout 30 seconds; remote TLS uses certificate verification when configured, and production requires TLS. Pool clients are released in `finally`. Retry covers connection acquisition only, not submitted SQL. Transactions commit or roll back and release the client. A statement timeout is not configured; no pool-exhaustion incident or query-timeout defect was reproduced.
- Available `.env` points to local PostgreSQL, not Supabase. Only configuration classification and variable names were printed; credential values were not included in this report. No Supabase connector was available, and no separate Supabase project credentials were found in the backend configuration inspected.
- Identity is custom: `users.id` UUID, scrypt password hashes, random `dc_` bearer secrets, SHA-256 token digests in `auth_tokens`, 30-day expiration. Both apps use `/auth/login` and `/auth/me`. There is no JWT issuer/audience/refresh contract and no evidence of Supabase Auth in these flows. A Supabase-hosted PostgreSQL database can host these application tables without making Supabase Auth the identity provider.
- `/auth/signup` supports customer registration; the Partner uses existing email/password accounts. Phone-only `/signin` is disabled for production. OTP delivery is not wired to an SMS provider; production email-change delivery is also incomplete. Do not enable OTP in production by configuration alone.
- Helmet, CORS, JSON body limit, API/auth rate limiters, bearer middleware, and authenticated write audit middleware precede protected routes. Authentication checks token expiration and now rejects deleted users. Roles are resolved from the database, never accepted from request-body claims.
- REST tenant checks use `access.ts`: owners have implicit membership, staff must have `status='active'`, manager/owner ranks restrict writes, and only `super_admin` has platform-wide venue access. The backend is designed for owner/privileged database access, so Express permission checks matter independently of RLS.
- Socket.IO is attached to the same HTTP server. Existing event/conversation messaging is retained. Notifications and menus are generally fetched/refreshed through REST. Several booking/event/restaurant emission helpers have no route callers; realtime synchronization of these surfaces is not established merely by their existence.
- API startup checks connectivity; schema/seed operations are separate scripts, not automatically executed by the API. `database/security_hardening.sql` is an old reference with inaccurate boot-path comments; it was not executed and must not be treated as deployed policy evidence.

## B. Database verification

**Live database inspection: Blocked.** A bounded read-only metadata probe failed at connection establishment with `EPERM`. A Unix-socket `psql SELECT 1` also failed with `Operation not permitted`. No SQL reached the configured server. No actual table count, Supabase project identity, installed migrations, RLS policy, Storage policy, function, trigger, constraint, or database privilege was verified.

The repository schema declares **41 application tables**, not proof of the previously reported approximately 79 deployed tables:

`users`, `user_avatars`, `restaurants`, `dinner_events`, `menu_items`, `bookings`, `refunds`, `stripe_events`, `payouts`, `withdrawals`, `collaboration_invites`, `reviews`, `follows`, `venue_follows`, `saved_events`, `activity`, `chat_messages`, `conversations`, `conversation_participants`, `message_read_receipts`, `special_menus`, `notifications`, `otp_codes`, `email_change_challenges`, `promo_codes`, `auth_tokens`, `user_blocks`, `reports`, `feedback`, `audit_log`, `supported_cities`, `saved_locations`, `restaurant_staff`, `restaurant_branches`, `restaurant_menu_sections`, `restaurant_menu_items`, `restaurant_tables`, `table_reservations`, `partner_verification_requests`, `restaurant_deals`, `restaurant_payouts`.

Source-level relationships and constraints inspected:

| Structure | Declared evidence in `src/schema.sql` | Live status |
|---|---|---|
| Restaurant owner | `restaurants.owner_id` references `users`, delete sets null | Blocked |
| Membership | Composite primary key `(user_id, restaurant_id)`; user/restaurant FKs; roles owner/manager/staff; statuses invited/active/revoked | Blocked |
| Branches | Restaurant FK; branch state and opening-hours columns; branch lookup indexes | Blocked |
| Digital menu | Restaurant/section relationships, numeric prices, ordering, active/available flags, menu lookup indexes | Blocked |
| Deals | Restaurant FK; allowed kind/status checks; nonnegative value; `ends_at > starts_at`; restaurant/status/end-date index | Blocked |
| Reservations | Restaurant/table/user relationships; indexed restaurant/time, user/time, restaurant/status | Blocked |
| Sessions | Hashed token lookup and expiration; user lookup index | Blocked |
| Messages | Conversation participation and receipt uniqueness `(message_id,user_id)` | Blocked |

`schema.ts` explicitly enables RLS on the 41 declared application tables and revokes PUBLIC table privileges when that setup script is run. It does not prove that setup ran, that Supabase `anon`/`authenticated` lack explicit grants, or that owners are subject to policies. The actual role, ownership, BYPASSRLS/FORCE RLS, SELECT/INSERT/UPDATE/DELETE policies, storage policies, security-definer functions, and default privileges must be inspected on the real project.

No schema defect was verified against an installed database, so no migration or rollback script is justified. The remaining database work is a read-only catalog export followed by tests against a disposable database with the actual schema and role configuration. Never run the reference security script or schema setup against production as an audit shortcut.

## C. API verification and cross-app flows

See [PHASE2_API_MATRIX.md](PHASE2_API_MATRIX.md) for method/path, handler line, consumer, access gate, and verification status. Entries distinguish source tracing and mocked tests from blocked database execution. Other source routes were discovered but not certified as working.

| Flow | Source trace and contracts | Verified limit |
|---|---|---|
| Profile | Partner `venue_repository.dart` → `/partner/restaurants/:id` → `restaurants`; Customer `restaurants_repository.dart` → `/restaurants/:id` | Both read/write the same table; visibility/field round trip requires DB |
| Digital menu | Partner `menu_repository.dart` → sections/items/availability routes → restaurant menu tables; Customer `public_menu_repository.dart` → `/public/menu/:id` | Public sections filter active; items filter available; numeric prices and camelCase mapping traced; actual persistence blocked |
| Packages/offers | Partner `/partner/menus` → `special_menus`; Customer `/offers` → active `special_menus` and `promo_codes` | Shared package flow exists in source; round trip blocked |
| Restaurant promotions | Partner `/partner/restaurants/:id/deals` → `restaurant_deals` | Customer `/offers` does not query this table. Dates/status are not propagated into the customer feed. Integration gap remains; no duplicate endpoint/table or new deal UI was added |
| QR | Customer scanner accepts restaurant UUID, `dinecircle://menu/<uuid>`, or HTTPS `/menu/<uuid>` → public menu lookup | Stable restaurant identifier contract exists; redirect hosting, branch mapping, scan analytics and device camera flow not verified |
| Reservations | Customer availability/create/list/cancel routes and Partner reservation routes share `table_reservations` and `src/reservations.ts` | Source uses transactions, row locks, capacity checks and explicit state transitions. Duplicate/concurrent booking behavior requires real DB tests |
| Experiences | Partner event requests approve/decline, host publish gates, partner events/bookings/check-in share dinner events/bookings | Source routes and existing integration cases located; end-to-end approval/check-in blocked |

Both apps use the same opaque identity contract and user UUIDs in source. Actual valid-login, logout, password/email change, expired-token, and cross-app response-model behavior against the running service is not certified. Unit tests exercise real authentication middleware with database responses stubbed.

## D. Verified security defects and remediation

The references below identify final code. Root causes were observed in original source, not inferred from prior audit assumptions. Severity is based on capability, not evidence of exploitation.

| ID | Severity / root cause / impact | Repair and evidence |
|---|---|---|
| P2-SEC-01 | Critical: Socket.IO `canAccessRestaurant` and `canAccessEvent` unconditionally allowed `partner_admin` for arbitrary tenants | `socket_security.ts:19` / `:23` reuse live venue membership; only platform super admin has global scope. Staff and owner access retained. Cross-tenant and valid-member unit cases |
| P2-SEC-02 | Critical: `hosts.ts` shared `assertHostAccess` treated any `partner_admin` as a platform operator, exposing unrelated hosts' private financial/business routes | `routes/hosts.ts:50` allows self or super admin. Helper regression covers denied unrelated partner, allowed self/admin. No payment processing or ledger business logic changed |
| P2-SEC-03 | High: Socket connection cached identity/role indefinitely; joined rooms could outlive session revocation, role changes or removed membership | `socket_security.ts:50` revalidates each operation; `:77` and `server.ts` delivery helper revalidate each outgoing room recipient and evict unauthorized recipients. No stale-session response data is intentionally broadcast without this gate |
| P2-SEC-04 | High: Async Socket.IO handlers had no payload validation or catch boundary; malformed IDs/objects/database failures could reject unhandled and terminate the API | Auth handshake middleware plus `socketHandler` validates payloads, bounds message/read batches and catches failures with safe errors. Invalid token types rejected before DB |
| P2-SEC-05 | High: Staff acceptance SELECT then unconditional UPDATE could reactivate a concurrently revoked invite | `routes/partner_venues.ts:658` performs conditional UPDATE only from invited; active acceptance remains idempotent; revoked gets 409. Three real-handler tests with stubbed DB. Concurrent PostgreSQL proof blocked |
| P2-SEC-06 | High: Default unrestricted `trust proxy=true` allowed attacker-controlled forwarding headers to select rate-limit IPs on directly reachable deployments | `security.ts:159` / `server.ts:46` default false; explicit true trusts one hop; explicit IP/subnet/hop configuration supported. Unit test covers defaults/options; `.env.example` documents configuration |
| P2-SEC-07 | High: Read receipts accepted arbitrary message UUIDs after checking only the supplied conversation, permitting cross-conversation writes | `socket_security.ts` final helper scopes one parameterized INSERT to the authorized conversation and returns only matched IDs for broadcast. Batches capped at 100; query/return-shape test |
| P2-SEC-08 | Defense in depth: bearer lookup did not explicitly exclude soft-deleted users | `context.ts` and socket lookup add `NOT u.is_deleted`; normal deletion already revokes sessions, so no standalone takeover is claimed. Authentication query regression |

Remaining security verification is substantial: actual database grants/RLS, all remaining route-level permission paths, HTTP/socket transport behavior, and concurrent authorization changes need staging execution. Query-then-act authorization has ordinary race windows; these changes are not a formal concurrency proof. A revoked socket is disconnected on its next authenticated operation; unauthorized room recipients are evicted at delivery. An idle connection may stay open without receiving private room data. Per-recipient authorization adds DB work proportional to recipients; measure under staging load before broad realtime expansion.

## E. Code change record and compatibility

| File | Change / issue | Compatibility |
|---|---|---|
| `src/socket_security.ts` (new) | Existing socket auth/access logic extracted, repaired, bounded and made testable; SEC-01/03/04/07/08 | Same service, token table, event names and JSON keys; accepts canonical UUID strings including legacy seed values |
| `src/server.ts` | Wire handshake authentication, listener wrappers, recipient authorization, scoped receipts and explicit proxy trust; SEC-01/03/04/06/07 | REST paths unchanged; valid socket payloads retained. Forbidden cross-tenant access intentionally rejected |
| `src/context.ts` | Exclude deleted users from session resolution; SEC-08 | Valid session responses unchanged |
| `src/routes/hosts.ts` | Remove partner_admin global host bypass; export same helper for tests; SEC-02 | Own-host and platform-admin workflows retained |
| `src/routes/partner_venues.ts` | Atomic invited→active predicate with idempotent active branch; SEC-05 | Existing successful response keys and revoked error status retained |
| `src/security.ts` | Explicit proxy trust configuration helper; SEC-06 | Direct development works; reverse-proxy operators must configure actual topology |
| `.env.example` | Explain proxy trust setting | No actual credentials changed |
| `src/tests/phase2_security.test.ts` (new) | 33 regression cases, including selected real menu/deal route denial handlers | No live database, HTTP port, external account or auth bypass introduced |
| `package.json` | Unit script includes new suite and uses Node's tsx import loader | Existing testing dependencies/framework retained; avoids tsx CLI IPC listener requirement |
| `docs/PHASE2_API_MATRIX.md`, this report, `docs/phase2-test-results/*` | Traceable verification record | Documentation only |

Build generated `dist` output using the existing build script. Git metadata is unavailable in this workspace (`not a git repository`), so a baseline diff/status and pre-existing file-change attribution could not be obtained. Listed files are the intentional source/config/document edits made in this phase.

## F. Tests and checks

Retained evidence: [phase2-test-results](phase2-test-results/).

| Command / check | Executed result |
|---|---|
| `node --import tsx src/tests/phase2_security.test.ts` | 33 passed, 0 failed; real helpers/selected handlers with stubbed database |
| `node --import tsx src/tests/database_config.test.ts` | 4 passed, 0 failed |
| `node --import tsx src/tests/db_connect.test.ts` | 3 passed, 0 failed |
| Unit-case total | **40 passed, 0 failed**; individual TAP files retained |
| `npm run test:unit` | Passed; this environment's test runner summarized 3 successful file workers rather than individual cases; not counted as another 40 cases |
| `npm run typecheck` | Passed TypeScript strict checking |
| `npm run build` | Passed production TypeScript build/schema copy |
| Original `npm run test:unit` before script adjustment | Failed to launch: tsx CLI could not listen on `/tmp/tsx-1000/*.pipe`, EPERM; loader invocation resolved this for units |
| `npm run test:integration` | Launch attempted; CLI IPC blocked by EPERM; this is not a passing suite |
| `node --import tsx --test src/tests/*.integration.test.ts` | **6 failed test-file workers, 0 passed**; all failed in bootstrap DB connection with EPERM before endpoint assertions. Blocked files: account, money, partner, payments, profile, safety |
| Partner integration alone via loader | Also failed setup with EPERM; not counted as an additional distinct suite failure |
| Read-only catalog probe / Unix-socket psql | Both blocked by EPERM; no database metadata read |
| Flutter/Dart tests and analysis | Blocked: neither executable is on PATH. Frontend source contracts were inspected; model tests not executed |
| Lint | No backend lint script configured; no lint success claimed |

No database setup/seed/drop succeeded. The integration harness creates unique disposable databases, but failed before the first statement could execute. It was not pointed at a remote or production database. No payment transaction ran; no external Stripe request was made by these unit cases.

The new tests cover unrelated tenant denials for nine menu/deal handler operations; active staff/owner/event member access; super-admin nonexistent venue denial; bad/expired/revoked session behavior; role refresh; malformed payloads and bounded receipt batches; safe async failure handling; host private access; stale-room recipient checks; scoped receipt results; invite acceptance/revocation/idempotency; and proxy configuration. They do not prove full CRUD, FK integrity, RLS, rollback, concurrency or HTTP wire contracts.

## G. Remaining backlog

### P0 — launch blockers

1. Supply access to the intended shared Supabase/PostgreSQL environment and a sandbox that permits database and local HTTP/socket connections. Inspect real schemas, role privileges, RLS/Storage policies and migration history through read-only metadata.
2. Execute all six integration files against disposable fixtures; verify valid email/password login, expiration/revocation, tenant separation, staff removal and role escalation, menu/deal writes, reservations, database failures and rollback. Run actual HTTP and Socket.IO tests with both app models. Current mocked checks are insufficient for a launch decision.
3. Verify deployed identity/database/API targets are shared by both builds. Correct production Partner `API_BASE_URL` through deployment configuration; default localhost is not a production endpoint.
4. Re-audit uninspected routes and actual privileged database access before certifying all tenant/private-data boundaries. Local patches close observed defects; no full security certification is claimed.

### P1 — essential MVP work requiring scope/contract decisions

- Define how existing `restaurant_deals` reach the customer app; current customer offers are dining packages/promo codes. Implement an agreed compatible contract without conflating independent records or duplicating endpoints.
- Complete staging profile/menu/package/reservation/experience round trips and check publish/unpublish, images, opening hours, cache refresh and deletion behavior.
- Verify provider-backed OTP/email delivery before exposing those production flows; currently no real delivery is implemented.
- Verify QR restaurant links on devices and hosted link resolution; establish whether branch-specific QR behavior is required.

### P2 — reliability and quality

- Measure per-recipient socket authorization overhead and pool utilization with real traffic; consider a bounded design only when evidence justifies it.
- Review statement timeout settings, legacy pagination validation, query plans/indexes, read consistency across multiple queries, and transaction failure recovery in a disposable environment.
- Correct stale security reference documentation; retain installed migration history and metadata artifacts when access is available.
- Add full transport-level tests for the new socket delivery path and configured proxy headers.

### P3 — future enhancements

Subscriptions, new payment features, advanced analytics, scan analytics, broader realtime dashboards and additional infrastructure remain out of scope. Existing finance routes were inspected only where necessary to close unauthorized private access; business features were not expanded.

## H. Phase 3 readiness

| Feature | Assessment / prerequisite |
|---|---|
| QR completion | Partial source foundation exists; stable restaurant UUID/public menu path traced. Requires successful DB/device/link tests and branch requirements |
| Restaurant/menu uploads | Not certified. Existing URL fields are not proof of upload/storage permissions. Verify Storage project/buckets/policies and agreed API upload flow |
| Missing Partner screens | Can be planned against matrix; runtime contract validation remains a prerequisite for claiming functioning screens |
| Subscriptions | Deferred; no readiness approval or implementation in Phase 2 |
| Additional analytics | Deferred; require reliable shared data, tenant verification and agreed metrics |
| Customer integration improvements | Blocked on real shared deployment and successful cross-app tests; restaurant promotion mapping remains unresolved |

**Do not proceed automatically to Phase 3 or mark the backend launch-ready.**

## Definition of Done

| Required item | Status | Evidence |
|---|---|---|
| Existing Express architecture verified | Passed | Embedded shared service, runtime/router/pool/auth source located |
| Shared Supabase structure inspected | Blocked | No Supabase configuration/project metadata; all DB connections denied |
| Core Partner endpoints matched to handlers | Passed (source only) | API matrix; runtime verification separately blocked |
| Authentication/token validation tested | Blocked overall | Middleware units pass; valid-login/session lifecycle DB tests cannot run |
| Ownership/staff permissions verified | Blocked overall | Real helper/selected handler units pass; DB fixtures/concurrency unavailable |
| Relevant RLS/privileged access audited | Blocked | Schema setup source inspected; installed roles/policies inaccessible |
| Critical cross-tenant vulnerabilities fixed | Passed locally | SEC-01/02/03/05/07 source fixes and regressions; staging confirmation blocked |
| Restaurant/menu/deal core operations tested | Blocked overall | Selected authorization cases pass; full persisted CRUD not run |
| Customer/Partner compatibility checked | Blocked overall | Static matrix traced; customer promotions gap and runtime checks outstanding |
| Verified P0 fixes repaired | Passed locally | Critical permission bypasses repaired; deployment/readiness not certified |
| Regression tests added and executed | Passed | 33 new cases; 40 total unit cases pass |
| Remaining blockers documented | Passed | Database, transport, SDK, deployment and integration gaps above |
| No working modules unnecessarily rebuilt | Passed | No second backend/database/auth provider, no frontend changes or migrations |
