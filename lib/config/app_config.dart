import '../api/app_config.dart' as api_config;

/// Application configuration management.
/// 
/// This file centralizes all environment-specific configuration values
/// that are passed at build time using --dart-define.
/// 
/// Usage:
/// ```bash
/// flutter run --dart-define-from-file=dart-defines.json
/// ```
/// 
/// Or individual defines:
/// ```bash
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
/// ```
///
/// The app talks to the DineCircle Express API for both authentication and
/// data access; there is no direct database client in the Flutter layer.
///
/// The API host and timeouts are NOT declared here. They live in
/// `lib/api/app_config.dart`, which the HTTP client, the avatar widget and the
/// booking screen all read. Re-declaring them here previously gave this file a
/// different default (`https://api.dinecircle.com` vs `http://10.0.2.2:4000`),
/// so a build without dart-defines would log one host while calling another.
/// These getters delegate to that single source so the two can never diverge.
class AppConfig {
  AppConfig._();

  // ─── Stripe Configuration ─────────────────────────────────────────────────

  /// Stripe publishable key for payments
  /// Example: pk_test_... or pk_live_...
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  // ─── Google Maps Configuration ────────────────────────────────────────────

  /// Google Maps API key for location services
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  // ─── Environment Detection ────────────────────────────────────────────────

  /// Current environment (development, staging, production)
  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Whether the app is running in production mode
  static const bool isProduction = environment == 'production';

  /// Whether the app is running in development mode
  static const bool isDevelopment = environment == 'development';

  /// Whether the app is running in staging mode
  static const bool isStaging = environment == 'staging';

  /// True when a production build was compiled against a non-HTTPS host.
  ///
  /// Release manifests no longer permit cleartext traffic, so such a build
  /// fails every request. Surfacing this at startup turns an opaque network
  /// error into a named configuration mistake.
  static bool get isInsecureProductionBuild =>
      isProduction && !apiBaseUrl.startsWith('https://');

  // ─── Feature Flags ────────────────────────────────────────────────────────

  /// Enable debug logging
  static const bool enableDebugLogging = bool.fromEnvironment(
    'ENABLE_DEBUG_LOGGING',
    defaultValue: isDevelopment,
  );

  /// Enable analytics
  static const bool enableAnalytics = bool.fromEnvironment(
    'ENABLE_ANALYTICS',
    defaultValue: isProduction,
  );

  /// Enable crash reporting
  static const bool enableCrashReporting = bool.fromEnvironment(
    'ENABLE_CRASH_REPORTING',
    defaultValue: isProduction,
  );

  // ─── API Configuration ────────────────────────────────────────────────────

  /// DineCircle Express API base URL. Delegates to the API client's own
  /// configuration so this value can never disagree with the host actually used.
  static String get apiBaseUrl => api_config.AppConfig.apiBaseUrl;

  // Request timeouts are declared as explicit `Duration` constants in
  // `lib/api/app_config.dart`. The `API_TIMEOUT_MS` dart-define is therefore
  // inert for this app (only the partner app consumes it); tune the durations
  // there instead of the build config.

  /// Returns a map of all configuration values (for debugging).
  ///
  /// Note: Sensitive values are masked.
  static Map<String, String> toDebugMap() {
    return {
      'environment': environment,
      'stripePublishableKey': _maskKey(stripePublishableKey),
      'googleMapsApiKey': _maskKey(googleMapsApiKey),
      'apiBaseUrl': apiBaseUrl,
      'enableDebugLogging': enableDebugLogging.toString(),
      'enableAnalytics': enableAnalytics.toString(),
      'enableCrashReporting': enableCrashReporting.toString(),
    };
  }

  static String _maskKey(String key) {
    if (key.isEmpty) return '(not set)';
    if (key.length <= 8) return '***';
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }
}
