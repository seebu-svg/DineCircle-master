---
kind: build_system
name: 'Build System: Flutter + Node/TS Dual-Stack with GitHub Actions CI'
category: build_system
scope:
    - '**'
source_files:
    - .github/workflows/server-ci.yml
    - server/Dockerfile
    - server/docker-compose.yml
    - server/package.json
    - pubspec.yaml
    - .deploy_stage/README.md
    - .deploy_stage/VERSION_NOTE.md
    - android/build.gradle.kts
    - android/app/build.gradle.kts
    - android/settings.gradle.kts
---

# Build System

DineCircle is a **dual-stack** project: a Flutter client (`pubspec.yaml`, `android/`, `ios/`) and a separate Node/TypeScript server (`server/`). There is no monorepo build tool (no Makefile, no Nx, no Turborepo); each side builds itself with its native toolchain.

## Client (Flutter)

- **Dependency & version management**: `pubspec.yaml` pins the app version as `1.0.0+1` (commented convention: `build-name` → Android `versionName` / iOS `CFBundleShortVersionString`; `build-number` → Android `versionCode` / iOS `CFBundleVersion`). The SDK constraint is `^3.13.4`. Dependencies are resolved via `pubspec.lock`.
- **Android build**: Gradle Kotlin DSL (`android/build.gradle.kts`, `android/app/build.gradle.kts`, `settings.gradle.kts`), invoked through `gradlew`. The generated `MainActivity.kt` and `GeneratedPluginRegistrant.java` are standard Flutter outputs.
- **iOS build**: Xcode workspace (`ios/Runner.xcworkspace`, `ios/Runner.xcodeproj`) with `Debug.xcconfig` / `Release.xcconfig` for environment configuration.
- **Web target**: minimal PWA under `web/` (`index.html`, `manifest.json`, icons).
- **Tests**: `flutter test` runs the suite in `test/` (widget tests, integration-style flows against fakes). The README documents an expected baseline of 110 passing tests; audit reports reference counts up to 899 after layout overflow expansion.
- **Linting**: `analysis_options.yaml` activates `flutter_lints ^6.0.0`.
- **Artifacts**: Per-ABI release APKs built with `flutter build apk --release --split-per-abi` (documented in `README.md`). Prebuilt `.apk_probe/lib/{arm64-v8a,armeabi-v7a}/` artifacts exist alongside `.deploy_stage/` which holds signed debug-key APKs for sideload testing. Version notes live in `.deploy_stage/VERSION_NOTE.md` (e.g. `App version : 1.0.0+1`, `Built : 26 Oct 2026, 21:47 (release, debug-key signed — sideload OK, not for Play Store)`).
- **Signing**: Current staged builds use the **Android debug key**; `.deploy_stage/README.md` explicitly states they are "internal testing only" and that a future keystore-signed build will require uninstalling the debug-signed one first.
- **No Flutter CI job exists yet**. A plan file (`docs/superpowers/plans/2026-10-29-flutter-overflow-suite-green.md`) calls out adding a second CI job for `flutter analyze` + `flutter test`, but it is not implemented.

## Server (Node/TypeScript)

- **Runtime**: TypeScript compiled at runtime via `tsx` (`"start": "tsx src/server.ts"`, dev mode uses `tsx watch`).
- **Package manager**: npm with lockfile `package-lock.json`.
- **Scripts** (`server/package.json`):
  - `dev` — hot-reload development server.
  - `typecheck` — `tsc --noEmit`.
  - `test:integration` — `tsx --test src/tests/*.test.ts` (Node's built-in test runner).
  - `db:schema` / `db:seed` / `db:reset` / `db:setup` — schema migration and seeding via `src/schema.ts` and `src/seed.ts`.
- **Containerization**:
  - `server/Dockerfile`: multi-stage-free single image from `node:24-alpine`, copies `package.json` + `package-lock.json` first for layer caching, then source; exposes port 4000; entrypoint `npm start`.
  - `server/docker-compose.yml`: brings up `postgres:16-alpine` (health-checked via `pg_isready`) plus the API service, which runs `npm run db:setup && npm start` on boot. Environment variables include `DATABASE_URL`, `PORT=4000`, `NODE_ENV`, and Stripe keys passed through `${STRIPE_SECRET_KEY:-}` defaults.
- **CI pipeline** (`.github/workflows/server-ci.yml`):
  - Triggered on push/pull_request when paths match `server/**` or `.github/workflows/server-ci.yml`.
  - Runs on `ubuntu-latest` with a `postgres:16-alpine` service container (user/password/db = `dinecircle`).
  - Steps: checkout → setup Node 24 with npm cache → `npm ci` → `npm run typecheck` → `npm run db:setup` → `npm run test:integration` → start server and run a long inline curl-based smoke test covering auth, booking, promo codes, authorization, host-studio surfaces, wallet withdrawals, event creation, approve/decline, and seat-release semantics.
  - The smoke test asserts specific HTTP status codes (201, 400, 403, 409) and JSON fields via `jq`, making it both a health check and a contract test.

## Conventions and Constraints

- **Dual-stack separation**: Flutter code lives at the repo root; server code is isolated under `server/`. There is no shared dependency graph between them.
- **Server CI is gated by path changes**: only changes under `server/**` or `.github/workflows/server-ci.yml` trigger the workflow (enforced by the `on.paths` filter in the workflow file).
- **Database lifecycle**: both local compose and CI seed the database before running tests — `npm run db:setup` (which runs `db:schema` then `db:seed`) is a prerequisite step in CI and the compose `command`.
- **Environment variables**: server secrets (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_CURRENCY`, `PAYMENTS_MODE`) are injected at runtime via compose env substitution; the Dockerfile comment says "never bake keys into the image".
- **Flutter artifact distribution**: prebuilt APKs are shipped manually under `.deploy_stage/` and `assets/images/`-style documentation describes ABI selection (arm64 vs armeabi-v7a) and the incompatibility between debug-key and keystore-signed installs.
- **Version numbering**: Flutter app version is declared in `pubspec.yaml` as `1.0.0+1`; server package version is independently `0.1.0` in `server/package.json`. No automated bump script was found.
- **No Flutter CI**: despite documented expectations (`flutter analyze` + `flutter test` pass baselines), there is no GitHub Actions job for the Flutter side — only the server has CI.