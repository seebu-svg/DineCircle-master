/// Coarse-grained failure categories the UI can react to uniformly.
enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  validation,
  conflict,
  server,
  unknown,
}

/// A single, typed error surfaced by [ApiClient].
///
/// Repositories and providers throw/catch this instead of raw `DioException`s
/// so screens can present a consistent message and drive the offline /
/// re-auth UX without knowing about the HTTP stack.
class ApiException implements Exception {
  const ApiException(
    this.kind, {
    this.message = 'Something went wrong. Please try again.',
    this.statusCode,
    this.cause,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final Object? cause;

  /// Whether the failure is worth an automatic retry / a "check connection"
  /// prompt rather than a hard error state.
  bool get isTransient =>
      kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  @override
  String toString() => 'ApiException(${kind.name}, $statusCode): $message';
}
