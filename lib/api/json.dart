/// Null-safe coercion helpers for parsing untyped JSON maps coming from Dio.
///
/// The API serialises numerics from Postgres `numeric` columns, so ratings,
/// prices and amounts can arrive as either `num` or `String`. Everything here
/// degrades gracefully to a supplied default rather than throwing, which keeps
/// a single odd field from blanking an entire screen.
library;

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return value.toString();
}

double asDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Parses a nullable numeric field (coordinates, distances), absent or
/// unparseable values stay null rather than collapsing to 0.
double? asDoubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int asInt(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true' || value == '1';
  return fallback;
}

/// Parses an ISO-8601 string (or epoch) into a [DateTime]; returns [null] when
/// the value is missing or unparseable.
DateTime? asDateOrNull(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<String> asStringList(Object? value) {
  if (value is List) {
    return value
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

Map<String, dynamic> asMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
  return const [];
}
