---
kind: error_handling
name: 'Cross-Tier Error Handling: ApiError (Express) + ApiException/ApiErrorKind (Flutter)'
category: error_handling
scope:
    - '**'
source_files:
    - server/src/context.ts
    - lib/api/api_exception.dart
    - lib/api/api_client.dart
    - lib/app_shell.dart
    - server/src/routes/bookings.ts
    - server/src/payments.ts
---

## Overview

The DineCircle monorepo uses a two-tier error-handling strategy that mirrors its client/server split:

- **Express backend** (`server/src`): domain-level `ApiError` with HTTP status codes, thrown from route handlers and middleware.
- **Flutter client** (`lib/api`): `ApiException` carrying an `ApiErrorKind` enum, produced by `ApiClient` from Dio transport errors and mapped HTTP responses.

There is no shared error-code library between Dart and TypeScript; each side defines its own types but agrees on HTTP status semantics (401→unauthorized, 403→forbidden, 404→notFound, 409→conflict, 400/422→validation, ≥500→server).

## Backend (Express / TypeScript)

### Core types — `server/src/context.ts`

- `class ApiError extends Error` carries a `status: number` and a message.
- Factory helpers: `notFound(what)`, `forbidden(why)`, `unauthorized()` return typed `ApiError` instances.
- `requireAuth` middleware parses the `Authorization: Bearer <token>` header, looks up the session in `auth_tokens`, attaches `req.userId` / `req.userRole`, and forwards any error via `next(error)`.
- `requireRole(...roles)` middleware returns `forbidden('Insufficient permissions')` when the current role is not in the allowed set.

Route handlers throughout `server/src/routes/*.ts` throw `new ApiError(status, message)` (e.g. `bookings.ts` throws 422 for unknown guests, 409 for already-started events, 400 for invalid promo codes). The `catch (error)` blocks in routes and services rethrow or pass them to Express's error pipeline via `next(error)`.

### Error response shape

`ApiClient._extractMessage` reads `response.data['error']` as the user-facing message, so the server should serialize errors as `{ error: string }`. Route handlers use this contract consistently.

### Other backend patterns

- `payments.ts` throws plain `new Error(...)` for configuration and simulation-mode violations (e.g. `'STRIPE_WEBHOOK_SECRET is not configured'`, `'PAYMENTS_MODE=mock is never allowed in production'`). These are internal failures rather than API errors.
- Database/query failures bubble up through `db.ts` `catch (error)` blocks and are typically caught at the route level.

## Frontend (Flutter / Dart)

### Core types — `lib/api/api_exception.dart`

- `enum ApiErrorKind`: `network`, `timeout`, `unauthorized`, `forbidden`, `notFound`, `validation`, `conflict`, `server`, `unknown`.
- `class ApiException implements Exception` holds `kind`, `message`, optional `statusCode`, and raw `cause`.
- Convenience getters: `isTransient` (network/timeout), `isUnauthorized`.

The class comment documents the design intent: repositories/providers throw/catch `ApiException` instead of raw `DioException`s so screens can present consistent messages and drive offline/re-auth UX without knowing about the HTTP stack.

### Transport layer — `lib/api/api_client.dart`

`ApiClient` wraps Dio and centralizes all error mapping:

1. Adds an interceptor that attaches `Authorization: Bearer <token>` to every request.
2. `_send` catches `DioException`, maps it via `_map`, and optionally retries GETs once when `retryOnTransient = true` and `mapped.isTransient`.
3. On 401, it invokes `onUnauthorized?.call()` so the session layer can clear itself.
4. `_map` translates Dio exception types to `ApiErrorKind`:
   - connection/send/receive timeout → `timeout`
   - connectionError/unknown → `network`
   - badResponse → delegated to `_fromResponse`
5. `_fromResponse` maps HTTP status codes to `ApiErrorKind` using a switch expression and extracts the message from `data['error']`.

### UI consumption — `lib/app_shell.dart`

Top-level navigation callbacks catch `ApiException` specifically (e.g. `} on ApiException catch (e) { ... }`) and fall back to a generic `catch (_) {}` for unexpected errors. This pattern appears in both the login flow and the booking flow, letting the shell decide what to show based on `ApiException.kind`.

Other providers document their throwing behavior in comments (e.g. `session_provider.dart`, `events_provider.dart`, `host_studio_controller.dart` state that methods "Throw [ApiException]" on failure), making the contract explicit to callers.

## Conventions Observed

- **Backend**: Domain errors are raised as `ApiError(status, message)` from route handlers; auth/authz failures go through `unauthorized()` / `forbidden()`. Internal/precondition failures may be plain `Error`.
- **Frontend**: All network-layer errors are funneled through `ApiClient`, which converts them into `ApiException(ApiErrorKind, ...)`. Callers (providers, repositories, screens) work exclusively with `ApiException`.
- **Status-to-kind mapping is centralized** in `ApiClient._fromResponse`; new HTTP statuses must be added there to get a corresponding `ApiErrorKind`.
- **Automatic retry** is opt-in per call (`retryOnTransient: true` on GETs only); POST/PATCH/DELETE do not auto-retry.
- **401 handling** triggers `onUnauthorized` callback in `ApiClient`, decoupling token invalidation from business logic.
- **UI error presentation** is done at the screen/shell boundary by matching on `ApiException.kind`, not by inspecting status codes directly.

## Key Files

- `server/src/context.ts` — `ApiError`, `requireAuth`, `requireRole`, `notFound`/`forbidden`/`unauthorized` helpers.
- `lib/api/api_exception.dart` — `ApiErrorKind` enum and `ApiException` class.
- `lib/api/api_client.dart` — Dio wrapper, error mapping, retry, 401 hook.
- `lib/app_shell.dart` — Top-level `ApiException` catching in navigation flows.