---
kind: configuration_system
name: 'DineCircle Configuration System: Build-Time Dart Defines, Secure Storage, and Server .env'
category: configuration_system
scope:
    - '**'
source_files:
    - lib/api/app_config.dart
    - lib/providers/app_prefs_provider.dart
    - lib/providers/api_client_provider.dart
    - lib/main.dart
    - dart-defines.example.json
    - pubspec.yaml
    - server/.env.example
    - server/src/server.ts
    - server/package-lock.json
    - server/.gitignore
    - server/.dockerignore
---

## Overview

DineCircle uses a **two-tier configuration system** split between the Flutter client and the Node/TypeScript server:

1. **Flutter client**: compile-time constants injected via `--dart-define` / `--dart-define-from-file`, plus runtime user state persisted in `flutter_secure_storage`.
2. **Server (Node/Express)**: runtime environment variables loaded by `dotenv` from `.env`, with explicit boot-time validation that aborts on invalid secrets.

There is no centralized config abstraction layer — each concern owns its own loader.

---

## Client-Side Configuration

### Build-time constants (`lib/api/app_config.dart`)

All build-time values are read through `String.fromEnvironment` inside a single `AppConfig` class:

| Key | Default | Purpose |
|-----|---------|---------|
| `API_BASE_URL` | `http://10.0.2.2:4000` | DineCircle Express API root (Android emulator loopback) |
| `GOOGLE_MAPS_API_KEY` | empty string | Google Maps SDK key; UI treats an empty value as "demo" mode |
| `STRIPE_PUBLISHABLE_KEY` | empty string | Stripe publishable key; when empty, `stripeEnabled` is false and checkout stays simulated |

The file documents the build invocation pattern:
```
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=AIza...
flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_…
```

A template `dart-defines.example.json` ships keys for `STRIPE_PUBLISHABLE_KEY` and `GOOGLE_MAPS_API_KEY`; the real file `dart-defines.json` is gitignored (see `.gitignore` line 51–52). The README instructs building with `--dart-define-from-file=dart-defines.json`.

### Runtime user preferences (`lib/providers/app_prefs_provider.dart`)

First-run flags (`onboardingComplete`, `preferencesComplete`) are stored under the keys `dinecircle.prefs.onboarding` and `dinecircle.prefs.completed` in `FlutterSecureStorage`. Hydration happens asynchronously in the provider's `build()` via `ref.onDispose` + `Future.microtask`, so the splash screen covers the I/O window. Failures are swallowed — if secure storage is unavailable on a platform, defaults are used.

### Secure storage wiring

`secureStorageProvider` is a Riverpod `Provider<FlutterSecureStorage>` defined in `lib/providers/api_client_provider.dart` and consumed by `app_prefs_provider`, `session_provider`, and `saved_locations_provider`. Tests override it with `InMemorySecureStorage`.

### What is NOT configured at runtime

- There is no runtime config file parser, no feature-flag service, and no remote settings endpoint in the Flutter codebase.
- No `package:flutter_dotenv` or equivalent is used on the client side.

---

## Server-Side Configuration

### Environment variables (`server/.env.example`)

The server reads all runtime configuration from `process.env` (via `dotenv`, declared in `package-lock.json`). Template entries include:

- `DATABASE_URL` — Postgres connection string
- `PORT` (default 4000)
- `NODE_ENV` (development)
- `PLATFORM_COMMISSION_RATE` (commented out, default 0.10)
- `API_RATE_LIMIT_MAX`, `AUTH_RATE_LIMIT_MAX` (rate-limit overrides)
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_CURRENCY`, `PAYMENTS_MODE` (Phase 4 payments)
- `STRIPE_CONNECT_CLIENT_ID`, `FCM_SERVER_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_MAPS_API_KEY` (later phases)

The template header states the rule: *Copy to `.env` and fill real values. NEVER commit `.env`.*

### Boot-time validation

`server/src/server.ts` enforces configuration at startup:

1. `waitForDatabase()` retries Postgres connectivity up to 15 times before giving up and exiting.
2. `initPayments()` is called once at boot; if `STRIPE_SECRET_KEY` is malformed, the process exits rather than failing mid-request.
3. `process.env.PORT ?? 4000` provides the fallback port.
4. CORS allows a fixed localhost/emulator origin list; in production (`NODE_ENV !== 'production'`), only listed origins pass.

### Docker & CI

- `server/.dockerignore` excludes `.env` and `.env.*` but explicitly re-includes `!.env.example`.
- `server/docker-compose.yml` comments indicate env vars are supplied from the host shell or a local `.env` file.
- `server/.gitignore` excludes `.env`.

---

## Conventions Observed

1. **Client secrets are never shipped to the device.** The README explicitly says the Stripe secret key (`sk_test_`) stays only in `server/.env` and must never reach the Flutter side. Only public keys (`pk_test_`, Google Maps API key) are passed via `--dart-define`.
2. **Build-time vs runtime boundary is strict.** Build-time values go through `String.fromEnvironment` in `AppConfig`; runtime values go through `process.env` on the server. There is no cross-cutting config object shared between tiers.
3. **Defaults are baked into code, not files.** `AppConfig` supplies sensible defaults (emulator URL, empty strings for optional keys); `server.ts` supplies defaults (`PORT = 4000`, commission rate 0.10).
4. **Optional features gate on presence of keys.** `AppConfig.stripeEnabled` checks whether `stripePublishableKey` is non-empty; an empty Google Maps key leaves the demo path active.
5. **User state is persisted in `flutter_secure_storage`, not SharedPreferences.** All persistent first-run/session flags use the secure-storage-backed providers.
6. **Secret templates ship without real values.** Both `dart-defines.example.json` and `server/.env.example` contain placeholder values and instructions to copy them locally.
7. **Tests mock secure storage, not env vars.** Test files override `secureStorageProvider` with `InMemorySecureStorage`; there is no test harness for `process.env` because server tests run against the real dotenv-loaded process.
8. **Configuration changes require a rebuild for client-side values.** Because `String.fromEnvironment` compiles constants into the binary, changing `API_BASE_URL` or any dart-define requires rebuilding the app.