---
kind: error_handling
name: 'Cross-Platform Error Handling: ApiError + ApiException with Centralized Mapping'
category: error_handling
scope:
    - '**'
source_files:
    - server/src/context.ts
    - server/src/server.ts
    - lib/api/api_exception.dart
    - lib/api/api_client.dart
---

## Overview

The DineCircle monorepo defines two parallel error-handling systems — one for the Express/TypeScript API server and one for the Flutter/Dart client — that communicate over a shared JSON contract `{ error: string }`.

| Layer | Mechanism | Purpose |
|---|---|---|
| Express API | `ApiError extends Error` (server/src/context.ts) | Domain-level HTTP errors (401/403/404/409/422/500) thrown from route handlers |
| Express global handler | `app.use((error, req, res, next) => ...)` (server/src/server.ts) | Converts `ApiError` → JSON response; maps `ZodError` to 400; catches everything else as 500 |
| Flutter client | `ApiException` + `ApiErrorKind` enum (lib/api/api_exception.dart) | Coarse-grained failure categories (`network`, `timeout`, `unauthorized`, `forbidden`, `notFound`, `validation`, `conflict`, `server`, `unknown`) |
| Dio wrapper | `ApiClient._map()` (lib/api/api_client.dart) | Translates `DioException` types and HTTP status codes into `ApiException` instances |

## Server-side conventions

### `ApiError` and helpers
`server/src/context.ts` defines:

```ts
class ApiError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}
export const notFound = (what: string): ApiError => new ApiError(404, `${what} not found`);
export const forbidden = (why: string): ApiError => new ApiError(403, why);
export const unauthorized = (): ApiError => new ApiError(401, 'Sign in to continue');
```

Route handlers throw these instead of raw strings or `new Error(...)`. Examples observed across `routes/auth.ts`, `routes/bookings.ts`, etc. include `throw new ApiError(401, ...)`, `throw new ApiError(409, ...)`, `throw new ApiError(422, ...)`, `throw new ApiError(500, ...)`. The `requireAuth` middleware throws `unauthorized()` when no token is present or the session is invalid, and `requireRole(...)` throws `forbidden('Insufficient permissions')` when the user's role is missing or not in the allowed set.

### Global error middleware
`server/src/server.ts` registers a single Express error handler after all routes:

```ts
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

This enforces a uniform response shape `{ error: string }` (with an optional `issues` array for validation errors) and ensures unhandled exceptions never leak stack traces to clients.

### Startup failures
Database connectivity and payment-gateway configuration are treated as fatal boot-time errors: `waitForDatabase()` retries up to 15 times then calls `process.exit(1)`, and `initPayments()` failures also exit the process rather than running without payments.

### WebSocket errors
Unauthenticated sockets are disconnected via `socket.disconnect(true)`. Authorization failures inside event/chat handlers emit a typed socket event: `socket.emit('error', { message: 'Not authorised to join this event' })`.

## Client-side conventions

### `ApiException` and `ApiErrorKind`
`lib/api/api_exception.dart` defines a single exception type used by every repository/provider:

```dart
enum ApiErrorKind {
  network, timeout, unauthorized, forbidden, notFound, validation, conflict, server, unknown,
}
class ApiException implements Exception {
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final Object? cause;
  bool get isTransient => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;
  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;
}
```

The class comment documents its purpose: "Repositories and providers throw/catch this instead of raw `DioException`s so screens can present a consistent message and drive the offline / re-auth UX without knowing about the HTTP stack."

### Dio mapping
`lib/api/api_client.dart` centralizes all transport-to-domain translation:

- Connection/send/receive timeouts → `ApiErrorKind.timeout`
- Connection errors / unknown → `ApiErrorKind.network`
- Status 401 → `unauthorized`; 403 → `forbidden`; 404 → `notFound`; 409 → `conflict`; 400/422 → `validation`; ≥500 → `server`
- Response bodies matching `{ error: string }` (the server's `ApiError` shape) are surfaced as the `message` field.
- Idempotent GET requests automatically retry once on transient failures (`retryOnTransient: true` is passed from `getJson`).
- On `isUnauthorized`, the client invokes `onUnauthorized?.call()` so the session layer can clear tokens.

### UI handling
Screens catch `ApiException` directly. For example, `lib/app_shell.dart` has a top-level `try/catch` around navigation that catches `ApiException` separately from generic `catch (_)`, allowing it to display a user-facing message while swallowing unexpected errors.

## Cross-cutting rules observed

1. **Server domain errors use `ApiError`** — route handlers construct them via `new ApiError(status, message)` or the `notFound`/`forbidden`/`unauthorized` helpers in `context.ts`. Raw `throw new Error(...)` is reserved for internal/fatal conditions (e.g., Stripe webhook secret misconfiguration, simulated gateway invariants).
2. **All Express errors flow through the single global handler** — no route handler writes `res.status(...).json(...)` directly for error cases; they throw and let the middleware serialize.
3. **Validation errors use Zod** — `ZodError` is caught alongside `ApiError` in the global handler and returned as `{ error: 'Invalid request body', issues: [...] }`.
4. **Client code never sees `DioException`** — repositories/providers catch `DioException` inside `ApiClient` and rethrow `ApiException`; callers only know about `ApiErrorKind`.
5. **Transient vs. permanent failures are distinguished** — `ApiException.isTransient` drives automatic retry logic for GETs and lets the UI choose between a retry prompt and a hard error state.
6. **401 triggers session teardown** — both sides treat 401 specially: the server's `requireAuth` throws `unauthorized()`, and the client's `ApiClient` invokes `onUnauthorized` to clear the current bearer token.
7. **WebSocket authorization uses explicit `socket.emit('error', ...)`** rather than throwing, since Socket.IO does not use Express middleware.