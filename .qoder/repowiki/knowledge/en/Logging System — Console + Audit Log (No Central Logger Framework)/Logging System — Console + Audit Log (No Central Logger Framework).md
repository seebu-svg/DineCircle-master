---
kind: logging_system
name: Logging System — Console + Audit Log (No Central Logger Framework)
category: logging_system
scope:
    - '**'
source_files:
    - server/src/server.ts
    - server/src/security.ts
    - server/src/schema.ts
    - server/src/db.ts
    - server/src/payments.ts
    - server/src/routes/auth.ts
    - server/src/routes/bookings.ts
    - server/src/routes/stripe_webhook.ts
    - lib/services/stripe_payments.dart
---

## What system/approach is used

The DineCircle repository has **no centralized logging framework** on either side.

- **Server (Node/Express, TypeScript):** Logging is done with bare `console.log` / `console.error` / `console.warn`. There is no `log4js`, `winston`, `pino`, `bunyan`, `debug`, or `morgan` dependency in `server/package.json`. The only structured output is an ad-hoc HTTP request logger (`requestLog`) and a database-backed audit trail (`audit_log`).
- **Flutter client (Dart):** There is no dedicated logger package. The only Dart-side log call found is a single `debugPrint(...)` in `lib/services/stripe_payments.dart`; everything else uses no explicit logging.

## Key files and packages

- `server/src/server.ts` — bootstraps Express, defines the inline `requestLog` middleware (line 43–50), prints startup/shutdown messages via `console.log`, and logs unhandled errors via `console.error` (line 300).
- `server/src/security.ts` — implements the `auditLog` Express middleware (lines 103–147) that persists write operations to the PostgreSQL `audit_log` table; also provides `redactForAudit` (lines 88–97) which redacts sensitive keys before persisting request bodies.
- `server/src/schema.ts` — declares the `audit_log` table schema (referenced at line 32).
- `server/src/db.ts` — emits `console.error` for idle pool failures (line 8).
- `server/src/payments.ts` — uses `console.log` / `console.warn` / `console.error` for payment-gateway state transitions and sweep failures.
- `server/src/routes/auth.ts`, `routes/bookings.ts`, `routes/stripe_webhook.ts`, `routes/events.ts` — route handlers use `console.log` / `console.error` / `console.warn` directly for OTP codes, Stripe events, booking lifecycle errors, etc.
- `lib/services/stripe_payments.dart` — the only observed Dart-side log call: `debugPrint('PaymentSheet did not complete: $error')`.

## Architecture and conventions

### Server-side

1. **HTTP access logs:** A local `requestLog` middleware in `server.ts` records one line per request in the shape `METHOD path → status durationMs`, using `process.hrtime.bigint()` for millisecond precision. It is mounted globally after JSON parsing (line 95) so it covers every routed endpoint.

2. **Audit trail (structured persistence):** The `auditLog` middleware in `security.ts` is mounted after authentication (`app.use(requireAuth)` then `app.use(auditLog)`, lines 248–251 of `server.ts`). It:
   - Only captures mutating methods (`POST`, `PUT`, `PATCH`, `DELETE`).
   - Wraps `res.end` to fire-and-forget an `INSERT INTO audit_log` after the response is sent.
   - Persists fields: `user_id`, `action`, `resource`, `resource_id` (from `req.params.id`), `changes` (JSON-stringified body), `status_code`, `ip_address`, `user_agent`.
   - Redacts sensitive body keys (`password`, `currentPassword`, `newPassword`, `code`, `otp`, `token`, `accessToken`, `refreshToken`) by replacing their values with `[redacted]` while preserving the object shape.

3. **Error handling:** Unhandled exceptions flow through a single Express error handler in `server.ts` (lines 290–303) which logs them via `console.error('Unhandled error:', error)` and returns a generic 500 JSON response. Database connection failures and invalid payment gateway configuration are logged and cause the process to exit (lines 306–323).

4. **Process lifecycle:** Startup prints readiness messages (`Database connection ready`, `Payments: Stripe gateway active`, `DineCircle API ... listening on ...`); shutdown prints a signal-received message and closes Socket.io, the HTTP server, and the DB pool.

### Client-side

- No logger initialization exists in `lib/main.dart` or any provider/service file.
- The sole Dart log call is `debugPrint(...)` inside `lib/services/stripe_payments.dart`, which is a Flutter SDK convenience method that writes to the debug console during development builds.

## Conventions and constraints

- **No external logger dependency:** The server does not import or configure any logging library; all stdout output goes through Node's built-in `console` API.
- **Request access logs are human-readable, not structured JSON:** The `requestLog` middleware outputs plain text like `GET /api/events → 200 12.3ms`, chosen explicitly to keep ops output "greppable" (see the comment at line 40–42 of `server.ts`).
- **Audit log is the only structured log sink:** Write operations are persisted to the `audit_log` PostgreSQL table rather than written to disk or forwarded to an external service.
- **Redaction rule for audit entries:** Any request-body key matching `password`, `currentPassword`, `newPassword`, `code`, `otp`, `token`, `accessToken`, or `refreshToken` is replaced with `[redacted]` before being stored in `audit_log.changes`. This is enforced by the `redactForAudit` function in `security.ts` (lines 77–97).
- **Audit inserts are fire-and-forget:** The `INSERT` into `audit_log` is wrapped in `.catch(console.error(...))` so a failed audit write cannot crash the request handler (line 138–140 of `security.ts`).
- **Only authenticated mutating requests are audited:** The middleware skips non-mutating methods early (line 109) and relies on `requireAuth` being mounted first, so anonymous requests do not reach the audit writer.
- **Client-side logging is absent:** There is no logger setup, no log-level configuration, and no routing of logs from Flutter to the backend.