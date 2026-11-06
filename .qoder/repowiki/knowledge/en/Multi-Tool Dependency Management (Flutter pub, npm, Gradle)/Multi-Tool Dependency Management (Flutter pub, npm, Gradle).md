---
kind: dependency_management
name: Multi-Tool Dependency Management (Flutter pub, npm, Gradle)
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - server/package.json
    - server/package-lock.json
    - android/build.gradle.kts
    - android/app/build.gradle.kts
---

## Overview

This monorepo manages dependencies across three distinct toolchains:

| Layer | Toolchain | Manifest | Lockfile | Registry |
|---|---|---|---|---|
| Flutter app (`lib/`, `android/`, `ios/`) | Dart/Flutter `pub` | `pubspec.yaml` | `pubspec.lock` | `https://pub.dev` (hosted) |
| Express API (`server/`) | Node.js `npm` | `server/package.json` | `server/package-lock.json` | `https://registry.npmjs.org` |
| Android native shell (`android/`) | Gradle (Kotlin DSL) | `android/build.gradle.kts` + `android/app/build.gradle.kts` | — (no lockfile) | `google()`, `mavenCentral()` |

There is no cross-tool dependency orchestrator (no Lerna, Turborepo, Nx, or Bazel). Each sub-project is managed independently.

## Flutter / Dart Dependencies

- Declared in `pubspec.yaml` under `dependencies:` and `dev_dependencies:`.
- SDK constraint: `environment.sdk: ^3.13.4`.
- The package is marked private via `publish_to: 'none'` so it cannot be accidentally published to `pub.dev`.
- Direct main dependencies include: `flutter_riverpod`, `dio`, `flutter_secure_storage`, `connectivity_plus`, `qr_flutter`, `google_maps_flutter`, `geolocator`, `geocoding`, `url_launcher`, `flutter_stripe`, `cupertino_icons`, `google_fonts`.
- Dev dependencies: `flutter_test` (SDK), `flutter_lints ^6.0.0`.
- `pubspec.lock` pins every transitive dependency with a `sha256` digest and the resolved `https://pub.dev` URL, ensuring reproducible builds.
- No custom `dependency_overrides`, no `pubspec_overrides.yaml`, and no `.dart_tool/package_config.json` vendoring of third-party code — all packages are fetched from `pub.dev` at build time.

## Node.js / Server Dependencies

- Declared in `server/package.json` under `dependencies:` and `devDependencies:`.
- Runtime deps: `express ^5.2.1`, `socket.io ^4.8.4`, `stripe ^23.0.1`, `pg ^8.16.1`, `helmet ^8.3.0`, `cors ^2.8.5`, `dotenv ^17.2.3`, `express-rate-limit ^8.7.0`, `zod ^4.1.13`.
- Dev deps: `tsx ^4.20.6`, `typescript ^5.9.3`, plus `@types/*` for express, cors, pg, node.
- `package-lock.json` (lockfileVersion 3) records exact resolved URLs under `https://registry.npmjs.org/...` and integrity hashes for every package, including optional platform-specific binaries (e.g. `@esbuild/linux-arm64`).
- No `.npmrc`, no `package.json` `publishConfig.registry`, no `node_modules/` committed — the directory exists locally but is excluded by default Git behavior.
- No private registry, no `GOOGLE_CLOUD_*` or GitHub Packages configuration found.

## Android / Gradle Dependencies

- Top-level `android/build.gradle.kts` declares two repositories: `google()` then `mavenCentral()`.
- App module `android/app/build.gradle.kts` adds one explicit Gradle dependency: `implementation("androidx.appcompat:appcompat:1.7.1")` — added as a workaround because `flutter_stripe`'s lint-only classpath pulls `play-services-tapandpay:18.8.0` which is not resolvable from the configured repos; the comment explains that lint tasks are disabled project-wide instead.
- All other Android dependencies come transitively through the Flutter Gradle plugin (`dev.flutter.flutter-gradle-plugin`) and its bundled plugins; there is no `android/settings.gradle.kts` `dependencyResolutionManagement` block overriding repos.
- No `gradle.properties` private credentials or `GRADLE_OPTS` overrides were observed in the repo.

## Versioning Conventions Observed

- **Semver ranges**: Both `pubspec.yaml` and `package.json` use caret ranges (`^x.y.z`) rather than pinned exact versions, allowing patch/minor upgrades while constraining major versions.
- **Lockfiles committed**: `pubspec.lock` and `server/package-lock.json` are checked into version control, pinning transitive resolution for reproducibility.
- **No vendored third-party source**: There is no `vendor/`, `third_party/`, or copied library tree. All third-party code is fetched from remote registries at install/build time.
- **Private package marker**: `pubspec.yaml` sets `publish_to: 'none'` to prevent accidental publication of the Flutter app package.
- **Android manifest keys injected at build time**: `GOOGLE_MAPS_API_KEY` is passed via `--dart-define` or a Gradle property and interpolated into `AndroidManifest.xml` through `manifestPlaceholders`; secrets are not embedded in source.

## Not Absent

- No Go modules (`go.mod` / `go.sum` absent).
- No Python `requirements.txt` / `pyproject.toml`.
- No CocoaPods `Podfile` (iOS uses Flutter's Swift Package Manager integration under `ios/Flutter/ephemeral/.swift_pm.lock`).
- No private Docker registry auth or `GOPRIVATE` configuration.