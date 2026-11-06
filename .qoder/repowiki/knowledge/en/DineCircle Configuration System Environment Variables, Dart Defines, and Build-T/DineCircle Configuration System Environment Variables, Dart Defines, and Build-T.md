---
kind: configuration_system
name: 'DineCircle Configuration System: Environment Variables, Dart Defines, and Build-Time Constants'
category: configuration_system
scope:
    - '**'
source_files:
    - server/.env.example
    - server/src/database_config.ts
    - server/src/server.ts
    - server/src/payments.ts
    - server/src/pricing.ts
    - lib/api/app_config.dart
    - lib/providers/app_prefs_provider.dart
    - dart-defines.example.json
---

## Overview

DineCircle is a two-part application (Flutter mobile + Node/Express backend) with no shared configuration framework. Each side loads its own runtime configuration from environment variables and build-time constants, with the server using `dotenv` and the Flutter app using `--dart-define`.

## Server-side (Node/Express)

### Loading mechanism
- `.env` files are loaded via `import 'dotenv/config'` in `server/src/payments.ts` and `server/src/pricing.ts`. The root `server/.env.example` documents every supported variable; `server/.env` is gitignored.
- All values are read directly from `process.env` at module load or boot time — there is no typed config object, schema validator, or central registry.

### Core variables (from `server/.env.example` and usage sites)
| Variable | Default / Validation | Used by |
|---|---|---|
| `DATABASE_URL` | `postgresql://dinecircle:dinecircle@localhost:5432/dinecircle` | `databaseConfig()` in `src/database_config.ts`; required in production |
| `DATABASE_SSL_CA_FILE` | none | TLS CA file for hosted/production Postgres |
| `DATABASE_POOL_MAX` | 10 | pg pool size |
| `DATABASE_CONNECT_TIMEOUT_MS` | 10000 | pg connection timeout |
| `PORT` | 4000 | Express listen port (`server.ts`) |
| `NODE_ENV` | development | CORS policy, payment mode selection |
| `PLATFORM_COMMISSION_RATE` | 0.10 | `pricing.ts` — validated to `[0, 1)` |
| `API_RATE_LIMIT_MAX` | 100/min | rate limiter override |
| `AUTH_RATE_LIMIT_MAX` | 10/min | auth rate limiter override |
| `STRIPE_SECRET_KEY` | none | Stripe gateway selection (`payments.ts`) |
| `STRIPE_WEBHOOK_SECRET` | none | Stripe webhook verification |
| `STRIPE_CURRENCY` | `usd` | Stripe PaymentIntent currency |
| `PAYMENTS_MODE` | auto-resolve | Forces `mock`, `stripe`, or `simulated` |
| `FCM_SERVER_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_MAPS_API_KEY` | commented out | Phase 7 / Phase 5 placeholders |

### Database configuration rules (`src/database_config.ts`)
- `DATABASE_URL` must be a `postgres:` or `postgresql:` URL; non-PostgreSQL protocols throw.
- Only `sslmode` values `require`, `verify-ca`, `verify-full`, `disable` are accepted.
- For Supabase-hosted URLs (hostname ends with `.supabase.co` or `.supabase.com`) or `NODE_ENV=production`, `sslmode=disable` is rejected.
- Other `pg` SSL options (`sslcert`, `sslkey`, `sslrootcert`, `ssl`, `uselibpqcompat`) are rejected in favor of `DATABASE_SSL_CA_FILE`.
- Pool size and connect timeout are parsed as positive integers; invalid values throw.

### Boot-time validation
- `server.ts` calls `waitForDatabase()` (up to 15 retries, 1500ms apart) before listening; failure exits with code 1.
- `initPayments()` is called once at boot; malformed `STRIPE_SECRET_KEY` or an invalid key format throws and exits.
- `PAYMENTS_MODE=mock` is explicitly forbidden when `NODE_ENV=production`.
- When `NODE_ENV=test`, any configured Stripe key is ignored and the simulated gateway is used instead.

### Payment gateway selection (`src/payments.ts`)
Three implementations share one interface:
- `StripeGateway` — real Stripe SDK, selected when `STRIPE_SECRET_KEY` is set (and not in test mode).
- `MockGateway` — offline, Stripe-shaped implementation for integration tests; uses `whsec_mock_offline_gateway` if `STRIPE_WEBHOOK_SECRET` is unset.
- `SimulatedGateway` — historical instant-settlement path with zero network calls; default when no key is configured.

The selected gateway is cached in a module-level `gateway` variable so it is resolved exactly once.

### CORS policy
In `server.ts`, only origins in a hard-coded allowlist (`http://localhost:3000`, `:4000`, `:8080`, `127.0.0.1:3000`, `10.0.2.2:3000`, `10.0.2.2:4000`) are accepted in production; all other origins are rejected. In non-production, any origin is allowed.

## Flutter client-side

### Build-time configuration via `--dart-define`
All runtime-facing configuration lives in `lib/api/app_config.dart` and is resolved through `String.fromEnvironment`:

| Define | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:4000` | Base URL for the Express API |
| `GOOGLE_MAPS_API_KEY` | empty string | Google Maps SDK key; UI shows a demo mode when absent |
| `STRIPE_PUBLISHABLE_KEY` | empty string | Enables Stripe PaymentSheet; absence keeps checkout in simulated mode |

`AppConfig.stripeEnabled` is `true` only when the publishable key is non-empty, gating the entire Stripe flow on the client.

### Runtime user preferences
First-run flags (`onboardingComplete`, `preferencesComplete`) are persisted in `flutter_secure_storage` under keys `dinecircle.prefs.onboarding` and `dinecircle.prefs.completed` (`lib/providers/app_prefs_provider.dart`). They are hydrated asynchronously after the first frame while the splash screen remains visible.

### Build-time definition template
`dart-defines.example.json` documents the expected defines (`STRIPE_PUBLISHABLE_KEY`, `GOOGLE_MAPS_API_KEY`) that should be passed via `flutter run --dart-define` or `flutter build apk --dart-define`.

## Conventions and constraints

1. **Server secrets never reach the client.** `server/.env.example` comments state "Secret key: server-only, NEVER commit and NEVER paste into the Flutter side." The Flutter side only receives the Stripe *publishable* key via `--dart-define`.
2. **No `.env` is committed.** The example file carries the explicit instruction "Copy to `.env` and fill real values. NEVER commit `.env`."
3. **Configuration is validated at boot, not lazily.** Both database connectivity and payment gateway initialization happen before `listen()` and will `process.exit(1)` on failure (`server.ts`).
4. **Production-enforced TLS.** `database_config.ts` rejects `sslmode=disable` for Supabase-hosted URLs and for `NODE_ENV=production`; `ssl.rejectUnauthorized` is forced true.
5. **Payment mode cannot be `mock` in production.** Enforced by a runtime check in `initPayments()` that throws when `PAYMENTS_MODE=mock` and `NODE_ENV=production`.
6. **Test isolation overrides live keys.** When `NODE_ENV=test`, `initPayments()` forces the simulated gateway regardless of `STRIPE_SECRET_KEY`, preventing accidental live Stripe calls in CI.
7. **Platform commission rate is server-side only.** `pricing.ts` treats `PLATFORM_COMMISSION_RATE` as a single source of truth for both accrual and recompute paths; invalid/out-of-range values silently fall back to `DEFAULT_PLATFORM_COMMISSION_RATE = 0.10` rather than crashing.
8. **Flutter config is compile-time constant.** `AppConfig` uses `String.fromEnvironment` with defaults, meaning values are baked into the binary at build time and cannot be changed at runtime on the device.
9. **User preference persistence is best-effort.** If secure storage fails (e.g., unsupported platform), the in-memory defaults are kept and the write is swallowed — the UI continues without persisting the flag.