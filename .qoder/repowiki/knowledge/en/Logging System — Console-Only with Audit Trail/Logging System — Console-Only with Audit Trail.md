---
kind: logging_system
name: Logging System — Console-Only with Audit Trail
category: logging_system
scope:
    - '**'
source_files:
    - server/src/server.ts
    - server/src/security.ts
    - server/src/schema.sql
    - lib/services/stripe_payments.dart
---

## What system/approach is used

The DineCircle monorepo has **no dedicated logging framework** on either side:

- **Express/TypeScript backend**: uses plain `console.log` / `console.error` for process lifecycle, startup diagnostics, and error reporting. There is no Winston, Pino, Bunyan, debug, or similar logger installed.
- **Flutter client**: uses `debugPrint` (from `dart:developer`) in one place (`lib/services/stripe_payments.dart`) and otherwise relies on `debugShowCheckedModeBanner: false` plus standard Dart print/debug facilities. No structured log library is imported.

The only "structured" output is the **audit trail**, which persists selected request mutations into a PostgreSQL `audit_log` table via an Express middleware.

## Key files and packages

- `server/src/server.ts` — bootstraps Express, defines the per-request console logger, wires the audit middleware, handles uncaught errors, and emits process-level logs.
- `server/src/security.ts` — implements `auditLog` middleware and `redactForAudit`, which redacts sensitive keys before persisting request bodies.
- `server/src/schema.sql` — defines the `audit_log` table schema referenced by the middleware.
- `lib/services/stripe_payments.dart` — sole use of `debugPrint` in the Flutter app.

No other files import a logging package; the grep across `.ts`/`.js`/`.dart` returned only `console.log`/`console.error` and `debugPrint` usages.

## Architecture and conventions

### Backend (Express)

1. **Per-request access log** — a local `requestLog` middleware in `server.ts` measures each request with `process.hrtime.bigint()` and writes a single line to stdout:
   ```
   METHOD path → status durationMs
   ```
   The comment explicitly states the intent: "No external dependency; keeps ops output tidy and greppable."

2. **Startup / lifecycle logs** — `waitForDatabase` prints readiness and retry progress; the server prints its listening port; SIGINT/SIGTERM handlers print a shutdown message before closing Socket.io and the DB pool.

3. **Error handling** — the global Express error handler calls `console.error('Unhandled error:', error)` for unexpected exceptions, then returns a generic 500 JSON response.

4. **Audit logging (persistent)** — `auditLog` middleware in `security.ts` intercepts POST/PUT/PATCH/DELETE requests after the response finishes, inserts a row into `audit_log` with fields `user_id`, `action`, `resource`, `resource_id`, `changes`, `status_code`, `ip_address`, `user_agent`. Sensitive body keys (`password`, `currentPassword`, `newPassword`, `code`, `otp`, `token`, `accessToken`, `refreshToken`) are replaced with `[redacted]` by `redactForAudit` before serialization.

5. **Fire-and-forget persistence** — the audit insert is `.catch(console.error(...))` so a failed audit write cannot break the request. This is documented as a fire-and-forget pattern in the middleware source.

6. **Rate limiter responses** — `express-rate-limit` instances emit their own human-readable JSON error messages (e.g. `Too many authentication attempts — please wait`). These are not routed through a logger.

### Flutter client

- `lib/main.dart` disables the debug banner (`debugShowCheckedModeBanner: false`).
- `lib/services/stripe_payments.dart` uses `debugPrint('PaymentSheet did not complete: $error')` for Stripe flow diagnostics.
- No centralized logger class, no log levels, no sinks, no file/network transport.

## Conventions and constraints

Observed patterns (descriptive):

- All backend operational output goes to stdout/stderr via `console.log` / `console.error`; no abstraction layer exists around it.
- Request-scoped info (method, URL, status, latency) is emitted once per request by the `requestLog` middleware.
- Persistent audit records are written only for mutating HTTP methods (POST/PUT/PATCH/DELETE) and only for authenticated routes (the middleware is mounted after `requireAuth`).
- Sensitive request-body fields are redacted before being stored in `audit_log.changes`.
- Audit failures do not fail the originating request (fire-and-forget).
- Database connection failures at startup cause the process to exit with code 1 after printing via `console.error`.
- Payment gateway initialization failure also exits the process at boot, preventing runtime misconfiguration from going unnoticed.

Rules enforced by the implementation:

- The audit log table columns (`user_id`, `action`, `resource`, `resource_id`, `changes`, `status_code`, `ip_address`, `user_agent`) are defined in `server/src/schema.sql` and referenced verbatim by the INSERT in `security.ts`; changing them requires updating both locations.
- The set of redacted keys (`REDACTED_KEYS`) is a `Set<string>` in `security.ts`; adding a new secret type requires editing that literal set.
- Rate limiters are configured via environment variables (`API_RATE_LIMIT_MAX`, `AUTH_RATE_LIMIT_MAX`, `REPORT_RATE_LIMIT_MAX`, `FEEDBACK_RATE_LIMIT_MAX`) read through `envLimit`, which accepts only positive integers — zero is treated as invalid and falls back to the default.
- The per-request logger format `${req.method} ${req.originalUrl} → ${res.statusCode} ${ms.toFixed(1)}ms` is hardcoded in `server.ts`; consumers should not parse it without accounting for this exact shape.