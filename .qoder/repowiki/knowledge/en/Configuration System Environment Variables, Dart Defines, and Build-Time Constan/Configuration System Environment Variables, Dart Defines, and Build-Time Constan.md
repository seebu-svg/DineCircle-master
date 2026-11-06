---
kind: configuration_system
name: 'Configuration System: Environment Variables, Dart Defines, and Build-Time Constants'
category: configuration_system
scope:
    - '**'
source_files:
    - server/.env.example
    - server/.env
    - server/src/db.ts
    - server/src/server.ts
    - lib/api/app_config.dart
    - dart-defines.example.json
---

## Overview

DineCircle is a Flutter + Express monorepo. Configuration is split across two layers:

- **Server (Express/TypeScript)** — runtime configuration via `dotenv` loading `process.env`.
- **Client (Flutter/Dart)** — build-time configuration via `--dart-define` / `String.fromEnvironment`, with no runtime config loader.

There is no shared configuration library, no YAML/TOML config files consumed at runtime, and no feature-flag framework. Secrets are kept out of source control; only `.env.example` and `dart-defines.example.json` ship as templates.

## Server-side configuration

### Loading mechanism

- `server/src/db.ts` imports `dotenv/config` (`import 'dotenv/config'`) which loads `server/.env` into `process.env` before any other module runs.
- The database connection string is read from `process.env.DATABASE_URL` with an inline fallback to `postgresql://dinecircle:dinecircle@localhost:5432/dinecircle`.
- `server/src/server.ts` reads `process.env.PORT` (defaulting to `4000`) and `process.env.NODE_ENV` for CORS policy.
- Payment gateway configuration (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_CURRENCY`, `PAYMENTS_MODE`, etc.) is documented in `server/.env.example`; the server calls `initPayments()` once at boot and exits on failure so malformed secrets kill the process rather than failing mid-request.

### Enforced rules

- `.env` is gitignored (see `server/.gitignore`); only `.env.example` is committed.
- `NODE_ENV=production` tightens CORS: only origins explicitly listed in `server.ts` are allowed; non-production allows all origins.
- Stripe webhook route (`/api/stripe_webhook`) is mounted *before* `express.json()` and rate limiters because it must receive the raw body for signature verification — this ordering is enforced by middleware registration order in `server.ts`.
- `PAYMENTS_MODE=mock` is rejected when `NODE_ENV=production` (documented in `.env.example`).

### Key environment variables (from `.env.example`)

| Variable | Purpose | Required? |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection string for `pg.Pool` | Yes |
| `PORT` | HTTP listen port | No (default `4000`) |
| `NODE_ENV` | Drives CORS and payment mode behavior | No |
| `PLATFORM_COMMISSION_RATE` | Platform commission on seat sales | No (default `0.10`) |
| `API_RATE_LIMIT_MAX`, `AUTH_RATE_LIMIT_MAX` | Rate-limit overrides | No |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_CURRENCY`, `PAYMENTS_MODE` | Stripe payments (Phase 4+) | Conditional |
| `FCM_SERVER_KEY`, `GOOGLE_APPLICATION_CREDENTIALS` | Push notifications (Phase 7) | Conditional |
| `GOOGLE_MAPS_API_KEY` | Server-side geocoding (Phase 5) | Conditional |

## Client-side configuration

### Build-time constants

All client configuration lives in `lib/api/app_config.dart`. It uses `String.fromEnvironment` to resolve values injected at compile time via `--dart-define`:

- `API_BASE_URL` — defaults to `http://10.0.2.2:4000` (Android emulator loopback to host). All API URLs are derived from this via `AppConfig.apiUrl`.
- `GOOGLE_MAPS_API_KEY` — baked into the binary; UI can detect a keyless build and show a demo mode.
- `STRIPE_PUBLISHABLE_KEY` — public Stripe key; when empty, the Stripe checkout path stays dormant and the historical simulated confirmation is used.

A convenience getter `stripeEnabled` returns `true` when the publishable key is non-empty.

### Templates and examples

- `dart-defines.example.json` provides placeholder values for `STRIPE_PUBLISHABLE_KEY` and `GOOGLE_MAPS_API_KEY`.
- The example shows how to pass defines: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000` and `flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=AIza...`.

### Platform-specific configuration

No runtime platform detection is used for configuration. Native shells configure themselves through their own manifests:

- Android: `android/app/src/main/AndroidManifest.xml`, `gradle.properties`, `local.properties`.
- iOS: `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/project.pbxproj`.
- Web: `web/manifest.json`, `web/index.html`.

These are standard Flutter/Native shell configs, not application-level feature flags.

## Conventions observed

1. **No runtime config file loader on the client.** All Flutter configuration is compile-time constants via `String.fromEnvironment` / `--dart-define`. There is no `SharedPreferences`, `File`, or network-based config bootstrap.
2. **Secrets never cross the client/server boundary.** Server-only keys (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`) are documented as "NEVER commit and NEVER paste into the Flutter side" in `.env.example`.
3. **Defaults are explicit and local.** Both `AppConfig` and `db.ts` provide sensible defaults so development works without custom env vars.
4. **Boot-time validation kills the process on bad config.** `server.ts` calls `waitForDatabase()` then `initPayments()` before listening; failures exit with code 1.
5. **Feature toggles are implicit, not declared centrally.** Features like Stripe are gated by the presence of a key (`stripeEnabled`, `STRIPE_SECRET_KEY` set), not by a feature flag registry.
6. **CORS is environment-aware.** Production restricts origins to a hard-coded allowlist; development is permissive.
7. **Rate limits are configurable via env but default to safe values** (`API_RATE_LIMIT_MAX=100`, `AUTH_RATE_LIMIT_MAX=10`), with integration tests raising them.

## Key files

- `server/.env.example` — authoritative template of all server environment variables with comments explaining each.
- `server/.env` — local developer secrets (gitignored).
- `server/src/db.ts` — `dotenv` import and `DATABASE_URL` resolution.
- `server/src/server.ts` — `PORT`, `NODE_ENV`, CORS origin policy, Stripe webhook ordering, payment init, shutdown handling.
- `lib/api/app_config.dart` — single source of Dart build-time configuration (`API_BASE_URL`, `GOOGLE_MAPS_API_KEY`, `STRIPE_PUBLISHABLE_KEY`).
- `dart-defines.example.json` — example `--dart-define` values for Flutter builds.