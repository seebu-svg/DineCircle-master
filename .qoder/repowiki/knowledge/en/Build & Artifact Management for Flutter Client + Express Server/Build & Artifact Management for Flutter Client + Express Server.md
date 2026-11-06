---
kind: build_system
name: Build & Artifact Management for Flutter Client + Express Server
category: build_system
scope:
    - '**'
source_files:
    - .github/workflows/server-ci.yml
    - server/Dockerfile
    - server/docker-compose.yml
    - server/package.json
    - android/build.gradle.kts
    - android/app/build.gradle.kts
    - pubspec.yaml
    - .deploy_stage/README.md
    - .deploy_stage/VERSION_NOTE.md
---

## Overview

The DineCircle monorepo uses three independent build systems, one per target:

- **Flutter client** (Android/iOS/web) — built via the Flutter toolchain (`flutter build`), with Gradle/Kotlin for Android and Xcode for iOS.
- **Express/TypeScript server** — built via `tsx` at runtime, packaged as a Docker image on Node 24 Alpine.
- **CI pipeline** — GitHub Actions runs only against the server side; there is no Flutter CI job in this repository.

There is no top-level Makefile or unified orchestrator. Each subproject owns its own dependency and artifact lifecycle.

## Key Files

| Area | File(s) | Role |
|---|---|---|
| Flutter app manifest | `pubspec.yaml` | Declares Dart SDK `^3.13.4`, dependencies, assets, version `1.0.0+1`, and `publish_to: 'none'` |
| Android Gradle (root) | `android/build.gradle.kts` | Centralizes Google/MavenCentral repos, redirects all Gradle output to `build/` under repo root, disables every lint task project-wide |
| Android Gradle (app) | `android/app/build.gradle.kts` | Applies `com.android.application` + `dev.flutter.flutter-gradle-plugin`; sets Java/Kotlin 17, pulls `versionCode`/`versionName` from `pubspec.yaml`, injects `GOOGLE_MAPS_API_KEY` via Gradle property or `--dart-define`, signs release builds with debug key |
| iOS shell | `ios/Runner.xcodeproj/project.pbxproj` | Generated Xcode project bootstrapped by Flutter |
| Server scripts | `server/package.json` | Defines `dev`, `start`, `typecheck`, `test`, `db:schema`, `db:seed`, `db:reset`, `db:setup` |
| Server container | `server/Dockerfile` | Multi-stage-free single-stage image based on `node:24-alpine`, copies `package.json`/`package-lock.json` first for layer caching, exposes port 4000 |
| Local compose | `server/docker-compose.yml` | Brings up `postgres:16-alpine` + API, waits for DB health, runs `npm run db:setup && npm start` |
| CI | `.github/workflows/server-ci.yml` | Triggers on push/PR touching `server/**`; spins up Postgres 16 service, installs deps with `npm ci`, typechecks, applies schema+seed, then performs an extensive HTTP smoke test of auth, bookings, promo codes, authorization, host-studio endpoints |
| Release notes | `.deploy_stage/README.md`, `.deploy_stage/VERSION_NOTE.md` | Documents sideloaded APK distribution, ABI variants, signing with debug key, and that the build points at a LAN dev server |

## Architecture & Conventions

### Versioning

- The Flutter app's version lives in `pubspec.yaml` as `version: 1.0.0+1`. Android's `versionCode` and `versionName` are read from it at build time via `flutter.versionCode` / `flutter.versionName`.
- The server's version is separate in `server/package.json` (`0.1.0`) and is not synchronized with the Flutter version.
- `.deploy_stage/VERSION_NOTE.md` records the human-readable version, package ID, build date, signing mode, and baked-in server URL — serving as the release manifest for sideloaded APKs.

### Dependency management

- **Dart**: `pubspec.yaml` + `pubspec.lock`; no vendoring.
- **Node.js**: `server/package.json` + `server/package-lock.json`; CI uses `npm ci` for deterministic installs.
- **Android**: Gradle resolves from `google()` and `mavenCentral()`; `flutter_stripe`'s lint-only dependency (`play-services-tapandpay:18.8.0`) is worked around by disabling all lint tasks project-wide because it cannot be resolved from those repositories.
- **iOS**: Managed by Flutter/Xcode; no explicit lock file in the tree.

### Build outputs

- All Gradle artifacts (Android) are redirected to a shared `build/` directory at the repo root via `rootProject.layout.buildDirectory` in `android/build.gradle.kts`, so both the root and `:app` subprojects write under `build/<project-name>/`.
- The server has no precompiled artifacts — `tsx` runs TypeScript directly at runtime (`"start": "tsx src/server.ts"`).
- The Docker image layers are optimized by copying `package.json` and `package-lock.json` before source, so dependency installation is cached across rebuilds.

### Environment & secrets

- Server env vars are supplied through `docker-compose.yml` environment blocks and/or a local `.env` file next to the compose file; Stripe keys are explicitly documented as host-provided and never baked into the image.
- CI hardcodes Postgres credentials (`dinecircle:dinecircle@dinecircle`) and passes them via the `DATABASE_URL` env var.
- The Android build accepts `GOOGLE_MAPS_API_KEY` either as a Gradle property or via `--dart-define=GOOGLE_MAPS_API_KEY=...`.

### Testing strategy

- **Server integration tests** live in `server/src/tests/*.test.ts` and are invoked via `npm run test:integration`, which runs the Node.js built-in `tsx --test` runner.
- **CI smoke tests** go beyond unit tests: they spin up the real server, authenticate two users, exercise booking flows, promo-code discounts, horizontal authorization (A cannot read B's bookings), event creation guards, host-studio invite acceptance, wallet withdrawals, approval/decline state transitions, and seat-release semantics — asserting exact HTTP status codes (`201`, `409`, `400`, `403`) and JSON fields via `jq`.
- **Flutter tests** exist under `test/` but are not wired into any CI step in this repository.

### Containerization

- Only the server is containerized. The Dockerfile does not compile TypeScript; it ships source and runs it through `tsx`.
- `docker-compose.yml` defines a `pgdata` volume for Postgres persistence and ensures the API depends on the database being healthy before starting.

### Distribution

- There is no Play Store or App Store pipeline. Releases are sideloaded APKs distributed from `.deploy_stage/`, available in two ABIs (`arm64-v8a`, `armeabi-v7a`).
- Both release builds are signed with the Android debug key (documented in `.deploy_stage/README.md`); a future keystore-signed build will require uninstalling the debug-signed variant before installing.
- The `.apk_probe/lib/` directory contains native libraries probed from the produced APKs.

## Conventions & Constraints

- **No top-level build orchestration.** Each subproject is built independently; nothing in this repo invokes `flutter build` from within CI or a Makefile.
- **CI is server-only.** `.github/workflows/server-ci.yml` triggers only when files under `server/**` or `.github/workflows/server-ci.yml` change; Flutter code changes do not trigger CI.
- **Postgres is required for every server build/test path.** Whether running locally via `docker-compose`, seeding via `npm run db:setup`, or executing CI, a Postgres 16 instance must be reachable at the configured `DATABASE_URL`.
- **Lint is disabled for Android builds.** The root `android/build.gradle.kts` unconditionally disables every task whose name contains `lint` because `flutter_stripe`'s lint classpath pulls an unresolvable dependency.
- **Release Android builds use debug signing.** `android/app/build.gradle.kts` sets `signingConfig = signingConfigs.getByName("debug")` for the release build type, making them unsuitable for production store distribution.
- **Java/Kotlin 17 is enforced.** Both `compileOptions.sourceCompatibility`/`targetCompatibility` and Kotlin `jvmTarget` are pinned to `JVM_17`.
- **Flutter SDK constraint:** `environment.sdk: ^3.13.4` in `pubspec.yaml` pins the minimum Dart SDK used to build the client.
- **Node 24 is the runtime for the server.** Both the Dockerfile base image and the CI `actions/setup-node@v4` step pin Node to version `24`.
- **API contract is tested end-to-end in CI.** The workflow asserts specific HTTP status codes and response shapes for signup, signin, bookings, promos, authorization, host-studio invites, wallet withdrawals, and approve/decline flows — treating these assertions as the authoritative integration spec.