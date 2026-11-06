---
kind: error_handling
name: 'Cross-Tier Error Handling: ApiException / ApiError with Centralized Mapping and Global Handlers'
category: error_handling
scope:
    - '**'
source_files:
    - lib/api/api_exception.dart
    - lib/api/api_client.dart
    - lib/app_shell.dart
    - server/src/context.ts
    - server/src/server.ts
    - server/src/reservations.ts
---

## Overview

DineCircle uses a two-tier error model that keeps the Flutter client and the Node/TypeScript server decoupled from their underlying transport layers:

- **Flutter (client)**: `ApiException` + `ApiErrorKind` in `lib/api/api_exception.dart`, produced by `ApiClient` (`lib/api/api_client.dart`) which wraps Dio.
- **Node/TypeScript (server)**: `ApiError` class in `server/src/context.ts`, thrown by route handlers and middleware, caught by a global Express error handler in `server/src/server.ts`.

The two sides communicate over HTTP using a uniform JSON shape `{ error: string }` (with optional `issues` for Zod validation), so screens never need to know about Dio or Express internals.

## Client-side architecture

### Types

`lib/api/api_exception.dart` defines:

```dart
enum ApiErrorKind {
  network, timeout, unauthorized, forbidden,
  notFound, validation, conflict, server, unknown,
}
class ApiException implements Exception {
  const ApiException(this.kind, {this.message = 'Something went wrong. Please try again.', this.statusCode, this.cause});
  bool get isTransient => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;
  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;
}
```

The enum provides coarse-grained categories the UI can react to uniformly; `isTransient` drives retry logic, `isUnauthorized` drives re-auth flows.

### Transport mapping

`ApiClient._send()` catches `DioException` and delegates to `_map()`, which switches on `DioExceptionType`:

| Dio type | Mapped kind | Message |
|---|---|---|
| `connectionTimeout` / `sendTimeout` / `receiveTimeout` | `timeout` | "The server took too long to respond." |
| `connectionError` / `unknown` | `network` | "No connection. Check your network and try again." |
| `badResponse` | status-code-based via `_fromResponse()` | extracted from response body `data['error']` or fallback |
| `cancel` / default | `unknown` | — |

HTTP status codes are mapped in `_fromResponse()`:

- 401 → `unauthorized`, 403 → `forbidden`, 404 → `notFound`, 409 → `conflict`, 400/422 → `validation`, ≥500 → `server`, else → `unknown`.

Idempotent GETs (`getJson`) pass `retryOnTransient: true`; if the first attempt yields a transient error, `_send()` retries once before rethrowing.

When an error is `isUnauthorized`, `ApiClient` invokes its `onUnauthorized` callback so the session layer can clear state.

### Presentation

Screens catch `ApiException` explicitly and display `e.message`; a broad `catch (_) {}` handles unexpected failures with a generic message. Example in `lib/app_shell.dart` (`_promote`):

```dart
try { await ref.read(sessionControllerProvider.notifier).promoteToHost(); }
on ApiException catch (e) { setState(() => _error = e.message); }
catch (_) { setState(() => _error = 'Could not upgrade to host. Please try again.'); }
```

State errors in providers use Dart's built-in `StateError` (e.g. `throw StateError('Sign in to respond to invitations.')` in `host_studio_controller.dart`) for preconditions that should be bugs rather than user-facing errors.

## Server-side architecture

### Error type

`server/src/context.ts` defines:

```typescript
class ApiError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}
export const notFound = (what: string) => new ApiError(404, `${what} not found`);
export const forbidden = (why: string) => new ApiError(403, why);
export const unauthorized = () => new ApiError(401, 'Sign in to continue');
```

Route handlers throw `new ApiError(statusCode, message)` directly (see `reservations.ts`, `auth.ts`, `bookings.ts`). Validation failures also use `ApiError` with 409/422 status codes.

### Middleware

- `requireAuth` (`context.ts`): extracts `Authorization: Bearer <token>`, looks it up in `auth_tokens`, attaches `req.userId` / `req.userRole`, and throws `unauthorized()` if missing/expired.
- `requireRole(...roles)` (`context.ts`): factory returning a middleware that calls `next(forbidden('Insufficient permissions'))` when the current role is not in the allowed set.
- `auditLog` (`security.ts`): logs authenticated mutating requests.
- `apiRateLimiter`, `authRateLimiter` (`security.ts`): rate-limiting wrappers applied at router mount points.

### Global error handler

`server/src/server.ts` registers a single Express error-handling middleware after all routes:

```typescript
app.use((error, _req, res, _next) => {
  if (error instanceof ApiError) {
    res.status(error.status).json({ error: error.message });
    return;
  }
  if (error instanceof ZodError) {
    res.status(400).json({ error: 'Invalid request body', issues: error.issues });
    return;
  }
  console.error('Unhandled error:', error);
  res.status(500).json({ error: 'Internal server error' });
});
```

This is the only place where `res.status(...)` is set for error responses — route handlers must throw `ApiError` rather than call `res.json` themselves.

### Boot-time failure handling

Startup code in `server.ts` treats database connectivity and payment-gateway configuration as fatal: `waitForDatabase()` retries 15 times then `process.exit(1)`, and `initPayments()` is wrapped in try/catch that logs and exits on failure. This prevents the server from running in a degraded state.

## Cross-cutting conventions

1. **Never leak raw transport errors**: The client never exposes `DioException` to screens; the server never returns raw stack traces. All user-visible messages go through `ApiException.message` / `ApiError.message`.
2. **Coarse-grained kinds on the client**: Screens branch on `ApiErrorKind` (or `isTransient` / `isUnauthorized`) rather than HTTP status codes.
3. **Uniform JSON envelope**: Both sides agree on `{ error: string }` (server adds `issues` for Zod validation).
4. **Centralized error conversion**: Dio → `ApiException` happens only in `ApiClient._map()`; Express → HTTP response happens only in the global error handler in `server.ts`.
5. **Transient vs non-transient**: Network/timeout errors are retried automatically for GETs; other kinds propagate to the caller.
6. **401 triggers session teardown**: `ApiClient.onUnauthorized` is wired into the session provider so invalid tokens clear state across the app.
7. **Fatal boot errors exit the process**: Database unavailability and bad payment config cause `process.exit(1)` rather than being swallowed.
8. **Precondition violations use `StateError`** in providers (e.g. requiring sign-in before acting), signaling programming errors rather than recoverable user errors.