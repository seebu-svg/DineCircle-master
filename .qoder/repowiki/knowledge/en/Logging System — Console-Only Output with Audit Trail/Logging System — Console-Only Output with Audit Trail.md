---
kind: logging_system
name: Logging System — Console-Only Output with Audit Trail
category: logging_system
scope:
    - '**'
source_files:
    - server/src/server.ts
    - server/src/security.ts
    - server/src/routes/auth.ts
    - server/src/routes/bookings.ts
    - server/src/routes/stripe_webhook.ts
    - server/src/payments.ts
    - lib/services/stripe_payments.dart
---

## Overview

The DineCircle monorepo has **no dedicated logging framework** on either side of the platform.

- The Express/TypeScript API (`server/src/`) uses plain `console.log` / `console.warn` / `console.error` calls directly from route handlers and utility modules, plus a single in-process request logger middleware.
- The Flutter app (`lib/`) does not import any logging package; the only diagnostic output is a single `debugPrint` call in `lib/services/stripe_payments.dart`.

There is no log-level configuration, no structured JSON formatter, no centralized logger instance, and no external sink (file, syslog, remote collector). All output goes to the process stdout/stderr.

## Server-side patterns

### Request access log
`server/src/server.ts` defines an inline `requestLog` middleware (lines 36–43) that prints one line per HTTP request:

```
METHOD path → status durationMs
```

It uses `process.hrtime.bigint()` for millisecond-precision timing and is mounted globally after `express.json()` but before rate limiters and routes.

### Boot / lifecycle logs
Startup and shutdown are logged via bare `console.log` / `console.error` in `server.ts`:
- Database readiness polling (`Database connection ready`, `Database not ready (attempt N/M) — retrying in Xms`).
- Payment gateway initialization failures (`Payment gateway configuration is invalid — exiting.`).
- Process termination hooks for `SIGINT` / `SIGTERM` (`signal received — closing server`).

### Route-level diagnostics
Route files sprinkle `console.log` / `console.warn` / `console.error` at domain boundaries:
- `routes/auth.ts`: OTP codes and SMS/mail send attempts (`[OTP] Code for ...`, `[SMS] Sending OTP to ...`, `[Mail] Change-email code for ...`).
- `routes/bookings.ts`: payment intent creation, capture, void, and check-in capture failures.
- `routes/stripe_webhook.ts`: webhook signature verification failures and processing errors.
- `payments.ts`: Stripe gateway mode selection (mock vs. live) and sweep failures.
- `schema.ts`: schema migration progress and failures.

These messages are unstructured text lines — no fields, no levels beyond the method name, no correlation IDs.

### Error handling
Unhandled exceptions flow through a single Express error handler in `server.ts` (lines 271–284) that:
- Converts `ApiError` and `ZodError` into typed JSON responses.
- Falls back to `console.error('Unhandled error:', error)` + `500 { error: 'Internal server error' }`.

### Audit trail (structured persistence)
The only structured, persisted "log" is the audit trail implemented as an Express middleware in `server/src/security.ts` (`auditLog`, lines 103–147). It:
- Triggers only on mutating methods (`POST`/`PUT`/`PATCH`/`DELETE`).
- Inserts into the `audit_log` PostgreSQL table with columns `user_id`, `action`, `resource`, `resource_id`, `changes`, `status_code`, `ip_address`, `user_agent`.
- Redacts sensitive body keys (`password`, `currentPassword`, `newPassword`, `code`, `otp`, `token`, `accessToken`, `refreshToken`) via `redactForAudit` before persisting `req.body` as JSON under `changes`.
- Is fire-and-forget: insert failures are swallowed with `console.error('Audit log insert failed:', err)` so they cannot block the request.

This is the closest thing to a structured logging subsystem in the repo — it persists operation metadata to a database rather than stdout.

## Flutter-side patterns

No logging dependency exists in `pubspec.yaml`. The only runtime diagnostic is:

```dart
debugPrint('PaymentSheet did not complete: $error');
```

in `lib/services/stripe_payments.dart`. This uses Flutter's built-in debug printer, which is stripped out in release builds.

## Conventions observed

- **Console-only output**: Every server-side log line is a `console.log` / `console.warn` / `console.error` call against `process.stdout` / `process.stderr`. There is no abstraction layer around these calls.
- **Human-readable, unstructured text**: Log lines are free-form strings intended for grepping in container logs, not machine-parseable records.
- **Domain prefixes for readability**: Messages use bracketed prefixes like `[OTP]`, `[SMS]`, `[Mail]`, `stripe webhook:` to make them greppable by subsystem.
- **Audit trail is separate from console logs**: Operational auditing is persisted to the `audit_log` table via the `auditLog` middleware; it is not written to stdout.
- **Sensitive data redaction**: The audit middleware enforces redaction of known secret-bearing keys before persistence.
- **Fire-and-forget audit inserts**: Audit log failures do not fail the request; they are logged to stderr.
- **No log level strategy**: There is no concept of DEBUG/INFO/WARN/ERROR levels; severity is implied by whether `console.log`, `console.warn`, or `console.error` is used.
- **No correlation IDs**: Requests and their downstream operations are not linked by a trace/correlation identifier across log lines.