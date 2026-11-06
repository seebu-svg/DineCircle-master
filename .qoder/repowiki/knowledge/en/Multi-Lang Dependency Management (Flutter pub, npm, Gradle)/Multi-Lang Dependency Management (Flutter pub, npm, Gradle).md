---
kind: dependency_management
name: Multi-Lang Dependency Management (Flutter pub, npm, Gradle)
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - server/package.json
    - server/package-lock.json
    - android/settings.gradle.kts
    - android/build.gradle.kts
    - .github/workflows/server-ci.yml
    - .gitignore
---

## Overview

This monorepo manages dependencies across three distinct ecosystems — Flutter/Dart, Node/TypeScript, and Android/Gradle — each with its own package manager, lockfile, and repository configuration. There is no cross-language dependency resolver; each sub-project declares and resolves its own third-party libraries independently.

## Dart / Flutter client (`pubspec.yaml`)

- **Manifest**: `pubspec.yaml` at the repo root declares runtime and dev dependencies via `dependencies:` and `dev_dependencies:` blocks.
- **Versioning**: All Dart packages use caret ranges (e.g. `flutter_riverpod: ^2.6.1`, `dio: ^5.7.0`, `flutter_stripe: ^14.2.0`). The SDK constraint is pinned to `^3.13.4` under `environment.sdk`.
- **Lockfile**: `pubspec.lock` exists alongside `pubspec.yaml`; `.gitignore` excludes `.dart_tool/`, `.pub-cache/`, `.pub/`, `/build/`, and `.flutter-plugins-dependencies`, so only the lockfile is committed for reproducibility.
- **Publishing**: `publish_to: 'none'` explicitly prevents accidental publication of this app package to pub.dev (documented in a comment as the preferred setting for private packages).
- **No vendoring or custom registry**: No `dependency_overrides`, no `pubspec_overrides.yaml`, no `pubspec.yaml` `publish_to` override beyond `'none'`, and no `~/.pubspec.yaml` or `PUB_HOSTED_URL` usage observed. Dependencies are resolved from the public pub.dev index.
- **Update guidance**: A comment in `pubspec.yaml` documents the update workflow: `flutter pub upgrade --major-versions` and `flutter pub outdated`.

## Node / TypeScript server (`server/package.json`)

- **Manifest**: `server/package.json` declares runtime deps under `dependencies:` (express, pg, socket.io, stripe, zod, cors, dotenv, helmet, express-rate-limit) and dev deps under `devDependencies:` (@types/*, tsx, typescript).
- **Versioning**: All versions use caret ranges (e.g. `"express": "^5.2.1"`, `"stripe": "^23.0.1"`, `"zod": "^4.1.13"`).
- **Lockfile**: `server/package-lock.json` is committed and used by CI. The GitHub Actions workflow pins the cache key to it via `cache-dependency-path: server/package-lock.json` and runs `npm ci` (not `npm install`) to enforce exact resolution from the lockfile.
- **Node version**: CI uses `actions/setup-node@v4` with `node-version: '24'`.
- **Private flag**: `"private": true` prevents accidental `npm publish`.
- **No private registry or auth tokens** are configured in the manifest or CI; all packages come from the public npm registry.

## Android / Gradle (`android/build.gradle.kts`, `android/settings.gradle.kts`)

- **Repositories**: Both `settings.gradle.kts` (`pluginManagement.repositories`) and `build.gradle.kts` (`allprojects.repositories`) declare `google()`, `mavenCentral()`, and `gradlePluginPortal()` as the only sources. No local Maven repos, no `maven { url ... }` entries, no `POM.xml` or `ivy.xml` files.
- **Plugin versions**: Managed centrally in `settings.gradle.kts` via the `plugins {}` block:
  - `dev.flutter.flutter-plugin-loader` version `1.0.0`
  - `com.android.application` version `9.1.0`
  - `org.jetbrains.kotlin.android` version `2.4.0`
- **Flutter SDK resolution**: `settings.gradle.kts` reads `local.properties` for `flutter.sdk` and includes `$flutterSdkPath/packages/flutter_tools/gradle` via `includeBuild(...)`. This means the Flutter Gradle toolchain is pulled from the locally installed Flutter SDK rather than from a Gradle plugin portal artifact.
- **Lint workaround**: `android/build.gradle.kts` disables every task whose name contains `lint` project-wide because `flutter_stripe`'s lint-only classpath pulls `play-services-tapandpay:18.8.0`, which is not resolvable from `google()/mavenCentral()` in this context. The comment explains that lint is a static-analysis gate and not required to package a test-mode APK.
- **No Gradle wrapper version pinning in the checked-in wrapper properties** was visible in the snippet; the wrapper JAR and properties exist under `android/gradle/wrapper/`.

## CI integration

- Only the server has a CI workflow (`.github/workflows/server-ci.yml`). It triggers on push/pull requests touching `server/**` or the workflow file itself.
- Dependency installation flow: `actions/setup-node@v4` caches npm using `server/package-lock.json` as the cache key, then `npm ci` installs an exact tree from the lockfile before running `npm run typecheck`, `npm run db:setup`, and smoke tests against a real Express server backed by a PostgreSQL service container.
- There is no Flutter or Android build step in the current CI; dependency resolution for those targets is therefore not enforced in CI.

## Conventions and constraints

- Each language ecosystem owns its own dependency manifest and lockfile; there is no shared dependency graph across Dart/Node/Gradle.
- Version ranges are uniformly expressed with caret (`^`) semantics in both `pubspec.yaml` and `package.json`.
- Lockfiles (`pubspec.lock`, `server/package-lock.json`) are committed; generated directories (`.dart_tool/`, `.pub-cache/`, `.pub/`, `/build/`, `node_modules/`) are gitignored.
- Private publishing is disabled for both the Dart app (`publish_to: 'none'`) and the Node server (`"private": true`).
- No private registries, authentication tokens, or vendored third-party source code are present in the repository; all third-party code is fetched from public indexes (pub.dev, npm, Google/Maven Central/Gradle Plugin Portal).
- The Flutter Gradle toolchain is sourced from the local Flutter SDK path read from `local.properties` rather than from a Gradle plugin portal artifact.