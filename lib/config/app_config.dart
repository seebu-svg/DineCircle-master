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

  /// DineCircle Express API base URL
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: isProduction
        ? 'https://api.dinecircle.com'
        : 'http://localhost:4000',
  );

  /// API request timeout in milliseconds
  static const int apiTimeoutMs = int.fromEnvironment(
    'API_TIMEOUT_MS',
    defaultValue: 30000,
  );

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
