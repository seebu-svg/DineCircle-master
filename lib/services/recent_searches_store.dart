import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the last few search terms the diner ran.
///
/// Stored through the app's existing [FlutterSecureStorage] instance (the same
/// one that holds the bearer token) rather than adding a preferences package:
/// one dependency fewer, and the value already survives restarts and the
/// Android backup/restore path.
class RecentSearchesStore {
  RecentSearchesStore(this._storage);

  /// Newest first, case-insensitively de-duplicated, capped at [maxEntries].
  static const String storageKey = 'dinecircle.search.recent';
  static const int maxEntries = 8;

  final FlutterSecureStorage _storage;

  Future<List<String>> load() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return _clean(
        decoded
            .whereType<Map>()
            .map((row) => row['q']?.toString() ?? '')
            .toList(),
      );
    } on FormatException {
      // A corrupt blob must never wedge the search screen: drop it and move on.
      debugPrint('Recent searches payload was corrupt; clearing it.');
      await clear();
      return const [];
    }
  }

  /// Puts [query] at the front, dropping any earlier spelling of the same term.
  Future<List<String>> add(String query) async {
    final term = query.trim();
    if (term.isEmpty) return load();
    final existing = await load();
    final next = _clean([term, ...existing]);
    await _write(next);
    return next;
  }

  Future<List<String>> remove(String query) async {
    final term = query.trim().toLowerCase();
    final next = (await load())
        .where((entry) => entry.toLowerCase() != term)
        .toList();
    await _write(next);
    return next;
  }

  Future<void> clear() => _storage.delete(key: storageKey);

  Future<void> _write(List<String> terms) async {
    await _storage.write(
      key: storageKey,
      value: jsonEncode([
        for (final term in terms)
          {'q': term, 'at': DateTime.now().toIso8601String()},
      ]),
    );
  }

  static List<String> _clean(List<String> terms) {
    final seen = <String>{};
    final cleaned = <String>[];
    for (final raw in terms) {
      final term = raw.trim();
      if (term.isEmpty) continue;
      if (!seen.add(term.toLowerCase())) continue;
      cleaned.add(term);
      if (cleaned.length >= maxEntries) break;
    }
    return cleaned;
  }
}
