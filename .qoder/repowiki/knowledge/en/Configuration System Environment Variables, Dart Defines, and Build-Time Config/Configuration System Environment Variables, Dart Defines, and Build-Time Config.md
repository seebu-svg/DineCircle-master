---
kind: configuration_system
name: 'Configuration System: Environment Variables, Dart Defines, and Build-Time Config'
category: configuration_system
scope:
    - '**'
source_files:
    - server/.env.example
    - server/.env
    - server/src/server.ts
    - server/src/payments.ts
    - server/src/db.ts
    - server/src/pricing.ts
    - server/src/security.ts
    - lib/api/app_config.dart
    - dart-defines.example.json
    - pubspec.yaml
    - ios/Runner/Info.plist
    - android/gradle.properties
---

## Overview

DineCircle is a monorepo with three runtime surfaces — a Flutter mobile app, an Express/PostgreSQL API server, and native Android/iOS shells. Configuration is split across these surfaces:

- **Server (Node/Express):** runtime configuration via `process.env`, loaded through `dotenv/config`.
- **Flutter client:** build-time configuration via `--dart-define`, resolved at compile time with `String.fromEnvironment`.
- **Native shells:** platform manifests (`Info.plist`, `AndroidManifest.xml`) plus Gradle properties for build flags.

There is no centralized config service, no feature-flag library, and no runtime config file format (YAML/TOML) consumed by the application code. The system is intentionally minimal: environment variables for secrets/runtime knobs, dart-define for per-build values, and native manifest keys for platform capabilities.

## Server-side configuration

### Loading mechanism

Every module that reads env vars imports `'dotenv/config'` as a side effect before accessing `process.env`. This pattern appears in:

- `server/src/db.ts` — loads `DATABASE_URL`
- `server/src/payments.ts` — loads Stripe keys and mode
- `server/src/pricing.ts` — loads `PLATFORM_COMMISSION_RATE`
- `server/src/security.ts` — loads rate-limit overrides

The template of all available variables lives in `server/.env.example`; the actual secrets are kept in `server/.env` (gitignored). The example file documents required vs. optional fields and explicitly states: "Copy to `.env` and fill real values. NEVER commit `.env`."

### Key variables

| Variable | Purpose | Default / Behavior |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection string for the `pg` pool | Required; startup fails if unreachable (see `waitForDatabase`) |
| `PORT` | HTTP listen port | `4000` |
| `NODE_ENV` | Drives CORS policy, payment-gateway selection, rate limits | `development` |
| `PLATFORM_COMMISSION_RATE` | Platform commission on gross seat sales (0 < rate < 1) | `0.10` |
| `API_RATE_LIMIT_MAX` | Per-minute API request limit override | `100` |
| `AUTH_RATE_LIMIT_MAX` | Per-minute auth endpoint limit override | `10` |
| `STRIPE_SECRET_KEY` | Stripe server secret (test/live) | Optional; absent → simulated gateway |
| `STRIPE_WEBHOOK_SECRET` | Webhook signature verification key | Required when `STRIPE_SECRET_KEY` is set |
| `STRIPE_CURRENCY` | PaymentIntent currency | `usd` |
| `PAYMENTS_MODE` | Gateway selection: `mock`, `stripe`, or `simulated` | See selection logic below |
| `GOOGLE_APPLICATION_CREDENTIALS` | GCP credentials path (for FCM/Maps phases) | Commented out |
| `GOOGLE_MAPS_API_KEY` | Server-side geocoding key (Phase 5) | Commented out |
| `FCM_SERVER_KEY` | Firebase Cloud Messaging server key (Phase 7) | Commented out |
| `STRIPE_CONNECT_CLIENT_ID` | Stripe Connect host payouts (Phase 6) | Commented out |

### Payment-gateway selection (enforced rule)

`server/src/payments.ts:initPayments()` selects the active gateway at boot:

1. If `PAYMENTS_MODE=mock` → use `MockGateway` (offline Stripe semantics).
2. If `PAYMENTS_MODE=mock` AND `NODE_ENV=production` → **throw** (the code explicitly forbids mock mode in production).
3. If `STRIPE_SECRET_KEY` is non-empty and not malformed (regex `^(sk|rk)_(test|live)_[A-Za-z0-9]+$`) → use `StripeGateway`.
4. If `NODE_ENV=test` with a Stripe key present → fall back to `SimulatedGateway` so integration tests never hit Stripe.
5. Otherwise → `SimulatedGateway` (historical instant-settlement, zero network calls).

Malformed Stripe keys cause the process to exit during `initPayments()`, which is called from `server.ts` before `httpServer.listen()`.

### Startup behavior

`server/src/server.ts` enforces ordered initialization:

1. Apply security middleware (`helmet`, `cors`).
2. Mount Stripe webhook router *before* JSON parsing so raw body bytes are preserved for signature verification.
3. Wait for Postgres via `waitForDatabase()` (up to 15 retries × 1500ms); failure exits the process.
4. Call `initPayments()`; malformed config exits the process.
5. Only then start listening on `PORT`.

CORS is whitelisted for local dev origins (`localhost:3000|4000|8080`, `127.0.0.1:8080`, emulator IP `10.0.2.2:*`); in production only origins explicitly listed are accepted.

## Flutter-side configuration

### Build-time dart-define

All client-facing configuration is baked into the binary at build time via `flutter run --dart-define=<KEY>=<VALUE>` or `flutter build ... --dart-define=...`. There is no runtime config loader.

The central access point is `lib/api/app_config.dart`:

```dart
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000');
  static String get apiUrl => '$apiBaseUrl/api';
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const String stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
  static bool get stripeEnabled => stripePublishableKey.isNotEmpty;
}
```

Defaults target the Android emulator loopback (`10.0.2.2:4000`) so development works without extra flags. An example mapping file `dart-defines.example.json` lists placeholder values for `STRIPE_PUBLISHABLE_KEY` and `GOOGLE_MAPS_API_KEY`.

### Runtime user preferences

User-level state (onboarding completion, taste preferences, session token) is persisted via `flutter_secure_storage` and surfaced through Riverpod providers (`sessionControllerProvider`, `appPrefsProvider`). These are not "configuration" in the deployment sense but act as per-user feature toggles driving the AppFlow screen sequence.

## Native shell configuration

### iOS

`ios/Runner/Info.plist` declares:
- URL scheme `dinecircle` for Stripe redirect-based payment methods.
- `LSApplicationQueriesSchemes` entries for `stripe` and `stripeapp`.
- Bundle versioning via `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)`.

### Android

`android/gradle.properties` sets JVM heap size and flags (`android.useAndroidX=true`, `android.newDsl=false`, `android.builtInKotlin=false`). The Android manifest and resource files do not contain application secrets; Google Maps keys are expected to be supplied via Gradle/dart-define rather than checked in.

## Conventions and constraints

- **Secrets live only in `.env` on the server.** The `.env.example` template and the comment in `.env` both state that `.env` must never be committed; it is gitignored.
- **Client-side keys are injected at build time, never read from the filesystem at runtime.** `AppConfig` uses `String.fromEnvironment`, meaning values are compiled into the binary.
- **Payment gateways are selected once at boot, not per-request.** `initPayments()` caches the chosen gateway in a module-level variable.
- **`PAYMENTS_MODE=mock` is forbidden in production.** Enforced by throwing in `payments.ts` when both conditions hold.
- **Malformed Stripe keys fail fast at startup.** A regex check rejects keys that don't match `^(sk|rk)_(test|live)_[A-Za-z0-9]+$`.
- **Integration tests force deterministic behavior** by setting `process.env.PAYMENTS_MODE = 'mock'` and `process.env.NODE_ENV = 'test'` before spawning the server.
- **Development defaults favor local connectivity:** `API_BASE_URL` defaults to the Android emulator's host loopback; `PORT` defaults to `4000`; `NODE_ENV` defaults to `development`.
- **No runtime config file format is used.** There is no YAML/TOML/JSON config loader in either the Flutter app or the Express server; all external configuration flows through `process.env` or `--dart-define`.