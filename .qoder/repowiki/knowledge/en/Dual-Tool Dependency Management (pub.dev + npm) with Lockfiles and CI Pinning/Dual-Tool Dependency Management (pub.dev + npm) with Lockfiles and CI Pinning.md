---
kind: dependency_management
name: Dual-Tool Dependency Management (pub.dev + npm) with Lockfiles and CI Pinning
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - server/package.json
    - server/package-lock.json
    - .github/workflows/server-ci.yml
---

## Approach

DineCircle is a two-language project, so dependency management is split across two independent package managers:

| Layer | Manager | Manifest | Lockfile | Registry |
|---|---|---|---|---|
| Flutter mobile app (root) | `flutter pub` | `pubspec.yaml` | `pubspec.lock` | `https://pub.dev` |
| Node/Express server (`server/`) | `npm` | `server/package.json` | `server/package-lock.json` | `https://registry.npmjs.org` |

There is no vendoring of third-party Dart or JS source code; all dependencies are resolved from their public registries at install time.

## Flutter side (`pubspec.yaml`, `pubspec.lock`)

- `pubspec.yaml` declares the SDK constraint `environment.sdk: ^3.13.4` and pins direct runtime dependencies under `dependencies:` (e.g. `dio ^5.7.0`, `supabase_flutter ^2.18.3`, `flutter_stripe ^14.2.0`, `google_maps_flutter ^2.19.0`) and dev-only tooling under `dev_dependencies:` (e.g. `flutter_lints ^6.0.0`).
- The package is marked private for publishing: `publish_to: 'none'` — this prevents accidental publication to `pub.dev` (documented in the file's own comment).
- `pubspec.lock` is committed to the repo and records every transitive dependency with its exact `version`, `sha256`, and `url: "https://pub.dev"`, providing reproducible builds.
- No custom `pubspec_overrides.yaml`, `pubspec.yaml` `dependency_overrides`, or `pubspec.yaml` `publish_to` override exists, so the default `pub.dev` hosted source is used throughout.
- Android/iOS native plugins are declared as regular Dart dependencies (e.g. `google_maps_flutter`, `flutter_secure_storage`, `qr_flutter`); platform-specific binaries are fetched by Flutter's build system rather than vendored here.

## Server side (`server/package.json`, `server/package-lock.json`)

- `server/package.json` separates runtime `dependencies` (express, pg, socket.io, stripe, zod, helmet, cors, dotenv, express-rate-limit) from `devDependencies` (@types/*, tsx, typescript).
- All version ranges use caret (`^`) semver specifiers, allowing minor/patch upgrades within the major version.
- `server/package-lock.json` is committed (lockfileVersion 3), pinning every installed package to an exact version, integrity hash, and `resolved` URL against `https://registry.npmjs.org`.
- The server package is marked `"private": true`, preventing accidental `npm publish`.

## CI enforcement (`.github/workflows/server-ci.yml`)

The only workflow in `.github/workflows/` enforces deterministic installs for the server:

- `actions/setup-node@v4` is configured with `cache-dependency-path: server/package-lock.json`.
- The install step runs `npm ci` (not `npm install`), which **requires** `package-lock.json` to exist and installs an exact tree matching it.
- The working directory is set to `server/` via `defaults.run.working-directory`, so the manifest and lockfile are always read from that subdirectory.

No equivalent Flutter CI job is present in the repository, so there is no automated `flutter pub get` / `flutter analyze` gate on the mobile side.

## Conventions observed

- Each language layer keeps its own manifest and lockfile at the conventional location (`pubspec.yaml` at repo root, `server/package.json` under `server/`).
- Lockfiles are committed alongside manifests, making dependency resolution deterministic across machines.
- Version ranges are expressed with caret (`^`) specifiers in both `pubspec.yaml` and `package.json`; exact versions are delegated to the generated lockfiles.
- Private packages are explicitly marked non-publishable (`publish_to: 'none'` in Dart, `"private": true` in Node).
- No private registries, proxy configurations, `GOPRIVATE`, `.npmrc`, or `.pubspec` overrides were found — all packages resolve from the default public registries.
- There is no automated dependency-update bot (no Dependabot, Renovate, or similar configuration) visible in the repository.