Three sibling screen files with no shared internal sub-packages; each is a self-contained entry point consumed by the top-level app flow.

- `splash_screen.dart` — Stateless `SplashScreen` taking an `onGetStarted` callback; renders the logo, tagline, and two action buttons (Get Started / Sign in).
- `onboarding_screen.dart` — Stateful `OnboardingScreen` holding a `PageController` over a fixed list of `_OnboardingSlide` data objects; exposes only an `onComplete` callback so navigation is driven by the parent.
- `auth_screen.dart` — `ConsumerStatefulWidget` backed by `flutter_riverpod`; it owns local form state (`TextEditingController`s, intent enum, loading/error flags) and calls `SessionController` via `sessionControllerProvider.notifier` for `login`/`signUp`. Success does not navigate itself — the session provider drives the rest of the app tree.

Dependency direction is one-way outward: these screens depend on shared theme (`app_colors`, `app_spacing`, `app_text_styles`) and the shared `PrimaryButton` widget, plus `api_exception.dart` for error mapping. They do not import business logic beyond the session provider.