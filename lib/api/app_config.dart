/// Static app configuration resolved at build time via `--dart-define`.
///
/// Supply the API host at build time, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=https://dinecircle-api.onrender.com
///
/// The default targets the Android emulator's loopback to the host machine,
/// which is where the local DineCircle API runs during development. Release
/// builds must pass the public HTTPS host explicitly.
class AppConfig {
  AppConfig._();

  /// Root of the DineCircle Express API (no trailing slash).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000',
  );

  /// All REST routes live under `/api`.
  static String get apiUrl => '$apiBaseUrl/api';

  // ─── Timeouts ─────────────────────────────────────────────────────────────
  //
  // Sized for the public deployment rather than a LAN box. A free / scale-to-
  // zero host keeps the TCP + TLS handshake cheap but may need most of a minute
  // to resume a sleeping instance before the first byte arrives, so `receive`
  // is generous. An unreachable host still fails fast on `connect`.

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 75);

  /// Google Maps SDK key baked in at build time. The Android manifest reads
  /// the same dart-define through Gradle; this copy lets the UI explain a
  /// key-less (demo) build when it is empty.
  ///   flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=AIza...
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  /// Stripe publishable key baked in at build time:
  ///   flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_…
  /// Public by design (Stripe's client-side key). When it is empty the whole
  /// PaymentSheet path stays dormant and checkout keeps the historical
  /// simulated confirmation, so keyless dev builds/CI are unaffected.
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );

  /// True when this build should route real payments through Stripe.
  static bool get stripeEnabled => stripePublishableKey.isNotEmpty;
}
