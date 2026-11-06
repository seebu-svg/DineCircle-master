---
kind: build_system
name: Build & Artifact Management for DineCircle Monorepo
category: build_system
scope:
    - '**'
source_files:
    - .github/workflows/server-ci.yml
    - server/Dockerfile
    - server/docker-compose.yml
    - server/package.json
    - android/app/build.gradle.kts
    - android/build.gradle.kts
    - android/gradle.properties
    - android/settings.gradle.kts
    - pubspec.yaml
    - .deploy_stage/README.md
---

## Overview

DineCircle is a monorepo containing three build targets: a Flutter mobile app (Android/iOS), an Express/TypeScript API server, and native shells. Build tooling is split per target — there is no top-level Makefile or unified orchestrator.

## Server (Express + TypeScript)

- **Runtime**: Node.js 24 (`node:24-alpine` base image, `NODE_ENV=production`).
- **Compiler**: TypeScript via `tsx` at runtime — no precompiled JS artifacts are produced. The `start` script runs `tsx src/server.ts`; `dev` uses `tsx watch`.
- **Dependency management**: `npm ci` against `server/package-lock.json`. `package.json` declares the full dependency tree; nothing is vendored.
- **Database bootstrap**: `npm run db:setup` runs `src/schema.ts` then `src/seed.ts`, applied on every container start in local/staging (`docker-compose.yml` command: `sh -c "npm run db:setup && npm start"`) and during CI before smoke tests.
- **Containerization**:
  - `server/Dockerfile`: single-stage image that copies `package.json` + lock first for layer caching, then source, exposes port 4000, and runs `npm start`.
  - `server/docker-compose.yml`: defines `db` (postgres:16-alpine) and `api` services; `api` depends on `db` being healthy (`pg_isready` healthcheck with 5s interval / 5s timeout / 10 retries). Environment variables for Stripe keys are injected from the host shell or a `.env` file next to compose — never baked into the image.
- **CI pipeline** (`github/workflows/server-ci.yml`):
  - Triggered on push/PR touching `server/**` or the workflow itself.
  - Runs on `ubuntu-latest` with a `postgres:16-alpine` service using credentials `dinecircle:dinecircle@dinecircle`.
  - Steps: checkout → setup-node@v4 (Node 24, npm cache keyed on `server/package-lock.json`) → `npm ci` → `npm run typecheck` → `npm run db:setup` → start server in background and poll `/api/health` up to 30s → smoke-test suite of curl/jq assertions covering auth, booking flow, promo codes, horizontal authorization, event creation, host-studio approve/decline, wallet withdrawals, and seat-release on decline.
  - No artifact upload step exists in this workflow.

## Flutter App (Android/iOS)

- **Flutter engine**: version 3.47.5 / Dart 3.13.4 (recorded in `.deploy_stage/README.md`).
- **Android build**: standard Flutter-generated Gradle project under `android/` (`build.gradle.kts`, `app/build.gradle.kts`, `gradlew`, `gradle/wrapper/`). The deploy README documents a release build split per ABI producing two APKs: `DineCircle-v0.1.0-arm64-release.apk` (~43 MB) and `DineCircle-v0.1.0-arm32-release.apk` (~41 MB).
- **Signing**: debug key only — internal testing builds are signed with the Android debug keystore. A future release signed with a proper keystore cannot update it in place; users must uninstall the debug-signed APK first.
- **Distribution**: direct APK install from `.deploy_stage/`; not published to Google Play.
- **iOS**: native shell present under `ios/Runner/` but explicitly excluded from the staged distribution (`iOS is not included in this folder — this build is Android-only`).
- **Web target**: minimal `web/index.html` + manifest/icons present, but no explicit web build step is documented in the staging notes.

## Versioning & Artifacts

- Application ID: `com.dinecircle.dine_circle`.
- Version string used in staged artifacts: `0.1.0` (also `server/package.json` `"version": "0.1.0"`).
- Staged artifacts live in `.deploy_stage/` alongside a human-readable `README.md` describing which APK to install, known limitations (mock data, no backend, simulated payments/QR/map), and build metadata.
- There is no automated version bump or artifact publishing pipeline visible in the repository — the staged APKs appear to be produced manually and committed to `.deploy_stage/`.

## Conventions Observed

- Per-target build configuration: each subproject owns its own build system (Gradle for Flutter/Android, Docker/npm for the server); no cross-cutting top-level build script was found.
- Database schema and seed are code-first: `src/schema.ts` generates SQL and `src/seed.ts` populates test data; both are invoked via npm scripts (`db:schema`, `db:seed`, `db:setup`, `db:reset`).
- CI mirrors production environment shape: same Postgres image, same credential pattern, same `DATABASE_URL` format.
- Secrets handling: Stripe keys and other secrets are passed through environment variables at runtime (compose reads `${STRIPE_SECRET_KEY:-}` etc.); nothing is committed as secrets.
- Integration tests double as smoke tests: the GitHub Actions job asserts HTTP status codes and JSON fields directly against the running server rather than delegating to a separate test runner.