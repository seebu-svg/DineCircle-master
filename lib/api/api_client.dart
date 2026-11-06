import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'app_config.dart';

/// Builds the default Dio instance with the app's base URL + timeouts.
Dio _buildDefaultDio() => Dio(
  BaseOptions(
    baseUrl: AppConfig.apiUrl,
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
    sendTimeout: AppConfig.sendTimeout,
    headers: const <String, dynamic>{'Accept': 'application/json'},
  ),
);

/// Thin, typed wrapper around Dio used by every repository.
///
/// Responsibilities:
///  * attach `Authorization: Bearer <token>` to every request;
///  * map transport + HTTP failures into a single [ApiException];
///  * retry idempotent GETs once on a transient (network/timeout) failure;
///  * notify the session layer when the server rejects the token (401).
class ApiClient {
  ApiClient({Dio? dio, this.token}) : dio = dio ?? _buildDefaultDio() {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final currentToken = token;
          if (currentToken != null && currentToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $currentToken';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;

  /// Current bearer token, if signed in. Mutated by the session layer.
  String? token;

  /// Invoked whenever a request fails with 401 so the session can clear itself.
  void Function()? onUnauthorized;

  /// Performs a liveness + reachability check without requiring auth.
  Future<bool> health() async {
    try {
      final res = await dio.get<dynamic>('/health');
      return res.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  /// Fire-and-forget probe run once at startup. A scale-to-zero host answers
  /// only after it boots, so warming it during the splash screen keeps that
  /// delay off the first sign-in the user actually waits for.
  Future<void> warmUp() async {
    if (await health()) return;
    // One more try: the first probe can be the request that triggers the boot.
    await health();
  }

  /// GET that returns the decoded JSON body.
  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query, retryOnTransient: true);

  /// POST that returns the decoded JSON body.
  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) => _send('POST', path, body: body, query: query);

  /// DELETE that returns the decoded JSON body.
  Future<dynamic> deleteJson(String path, {Object? body}) =>
      _send('DELETE', path, body: body);

  /// PATCH that returns the decoded JSON body (partial updates such as
  /// `PATCH /users/me`).
  Future<dynamic> patchJson(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  /// PUT that returns the decoded JSON body (whole-resource replacement such
  /// as `PUT /users/me/avatar`).
  ///
  /// [onSendProgress] reports bytes written so a long upload (a base64 profile
  /// photo) can render real progress instead of an indeterminate spinner.
  Future<dynamic> putJson(
    String path, {
    Object? body,
    void Function(int sent, int total)? onSendProgress,
  }) => _send('PUT', path, body: body, onSendProgress: onSendProgress);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool retryOnTransient = false,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final res = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
        onSendProgress: onSendProgress,
      );
      return res.data;
    } on DioException catch (error) {
      final mapped = _map(error);
      if (retryOnTransient && mapped.isTransient) {
        // One automatic retry for a flaky network / timeout on a GET.
        try {
          final retry = await dio.request<dynamic>(
            path,
            data: body,
            queryParameters: query,
            options: Options(method: method),
            onSendProgress: onSendProgress,
          );
          return retry.data;
        } on DioException catch (retryError) {
          throw _map(retryError);
        }
      }
      if (mapped.isUnauthorized) onUnauthorized?.call();
      throw mapped;
    }
  }

  ApiException _map(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          ApiErrorKind.timeout,
          message: 'The server took too long to respond.',
          cause: error,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return ApiException(
          ApiErrorKind.network,
          message: 'No connection. Check your network and try again.',
          cause: error,
        );
      case DioExceptionType.badResponse:
        return _fromResponse(error.response);
      case DioExceptionType.cancel:
      default:
        return ApiException(ApiErrorKind.unknown, cause: error);
    }
  }

  ApiException _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    final message = _extractMessage(response?.data) ?? _defaultFor(status);
    final kind = switch (status) {
      401 => ApiErrorKind.unauthorized,
      403 => ApiErrorKind.forbidden,
      404 => ApiErrorKind.notFound,
      409 => ApiErrorKind.conflict,
      400 || 422 => ApiErrorKind.validation,
      _ when status >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.unknown,
    };
    return ApiException(kind, message: message, statusCode: status);
  }

  static String? _extractMessage(dynamic data) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return null;
  }

  static String _defaultFor(int status) => status == 0
      ? 'No connection. Check your network and try again.'
      : 'Request failed ($status).';
}
