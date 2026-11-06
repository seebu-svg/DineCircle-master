import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/saved_location.dart';
import '../repositories/location_repository.dart';
import 'api_client_provider.dart';

/// Persistent key for locally cached saved locations.
const _savedLocationsKey = 'dinecircle.location.saved';

/// Persistent key for the last-selected city (survives app restarts).
const _lastCityKey = 'dinecircle.location.lastCity';

/// Persistent key for the last-selected area within the city.
const _lastAreaKey = 'dinecircle.location.lastArea';

// ── Supported cities ────────────────────────────────────────────────────────

/// All DineCircle-supported cities with their neighbourhoods. Falls back to a
/// hard-coded list when the endpoint is unreachable so the picker always works.
final supportedCitiesProvider = FutureProvider<List<ServiceCity>>((ref) async {
  try {
    return await ref.watch(locationRepositoryProvider).supportedCities();
  } catch (_) {
    return _fallbackCities;
  }
});

/// Flat list of city names for quick access (chip rows, dropdowns).
final supportedCityNamesProvider = Provider<List<String>>((ref) {
  final async = ref.watch(supportedCitiesProvider);
  return async.valueOrNull?.map((c) => c.name).toList() ??
      _fallbackCities.map((c) => c.name).toList();
});

/// Areas/neighbourhoods for a specific city.
final areasForCityProvider = Provider.family<List<String>, String>((ref, city) {
  final async = ref.watch(supportedCitiesProvider);
  final cities = async.valueOrNull ?? _fallbackCities;
  for (final c in cities) {
    if (c.name == city) return c.areas;
  }
  return const [];
});

// ── Saved locations ─────────────────────────────────────────────────────────

/// The user's saved locations (Home, Work, favourites). Reads from local cache
/// first, then refreshes from the server in the background.
final savedLocationsProvider =
    StateNotifierProvider<SavedLocationsNotifier, List<SavedLocation>>((ref) {
      return SavedLocationsNotifier(ref);
    });

class SavedLocationsNotifier extends StateNotifier<List<SavedLocation>> {
  SavedLocationsNotifier(this._ref) : super(const []) {
    _hydrate();
  }

  final Ref _ref;
  FlutterSecureStorage get _storage => _ref.read(secureStorageProvider);
  LocationRepository get _repo => _ref.read(locationRepositoryProvider);

  /// Load from local cache immediately, then fetch from server.
  Future<void> _hydrate() async {
    final cached = await _readLocal();
    if (cached.isNotEmpty) state = cached;
    await refresh();
  }

  /// Re-fetch from the server and update local cache.
  Future<void> refresh() async {
    try {
      final remote = await _repo.savedLocations();
      state = remote;
      await _writeLocal(remote);
    } catch (_) {
      // Network unavailable — keep local cache.
    }
  }

  /// Save a new or updated location (server + local).
  Future<SavedLocation?> add(SavedLocation location) async {
    try {
      final saved = await _repo.saveLocation(location);
      final updated = [...state.where((l) => l.id != saved.id), saved];
      state = updated;
      await _writeLocal(updated);
      return saved;
    } catch (_) {
      // Optimistic local update on network failure.
      final updated = [...state.where((l) => l.id != location.id), location];
      state = updated;
      await _writeLocal(updated);
      return location;
    }
  }

  /// Remove a saved location.
  Future<void> remove(String id) async {
    try {
      await _repo.deleteLocation(id);
    } catch (_) {
      // Best-effort server delete; local cache always advances.
    }
    final updated = state.where((l) => l.id != id).toList();
    state = updated;
    await _writeLocal(updated);
  }

  /// Look up a specific kind (Home, Work) — null when not set.
  SavedLocation? ofKind(SavedLocationKind kind) {
    for (final loc in state) {
      if (loc.kind == kind) return loc;
    }
    return null;
  }

  // ── Local persistence ──────────────────────────────────────────────────

  Future<List<SavedLocation>> _readLocal() async {
    try {
      final raw = await _storage.read(key: _savedLocationsKey);
      if (raw == null || raw.isEmpty) return const [];
      final list = json.decode(raw) as List<dynamic>;
      return list
          .map((e) => SavedLocation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeLocal(List<SavedLocation> locations) async {
    try {
      final encoded = json.encode(locations.map((l) => l.toJson()).toList());
      await _storage.write(key: _savedLocationsKey, value: encoded);
    } catch (_) {
      // Storage unavailable — state is already updated in memory.
    }
  }
}

// ── Last-selected location preferences ──────────────────────────────────────

/// The user's last-selected city, persisted across app restarts.
final lastSelectedCityProvider =
    StateNotifierProvider<LastCityNotifier, String>((ref) {
      return LastCityNotifier(ref);
    });

class LastCityNotifier extends StateNotifier<String> {
  LastCityNotifier(this._ref) : super('Karachi') {
    _hydrate();
  }

  final Ref _ref;
  FlutterSecureStorage get _storage => _ref.read(secureStorageProvider);

  Future<void> _hydrate() async {
    try {
      final saved = await _storage.read(key: _lastCityKey);
      if (saved != null && saved.isNotEmpty) state = saved;
    } catch (_) {
      // Keep default.
    }
  }

  Future<void> setCity(String city) async {
    state = city;
    try {
      await _storage.write(key: _lastCityKey, value: city);
    } catch (_) {
      // Best-effort persistence.
    }
  }
}

/// The user's last-selected area within their city.
final lastSelectedAreaProvider =
    StateNotifierProvider<LastAreaNotifier, String>((ref) {
      return LastAreaNotifier(ref);
    });

class LastAreaNotifier extends StateNotifier<String> {
  LastAreaNotifier(this._ref) : super('') {
    _hydrate();
  }

  final Ref _ref;
  FlutterSecureStorage get _storage => _ref.read(secureStorageProvider);

  Future<void> _hydrate() async {
    try {
      final saved = await _storage.read(key: _lastAreaKey);
      if (saved != null) state = saved;
    } catch (_) {
      // Keep default.
    }
  }

  Future<void> setArea(String area) async {
    state = area;
    try {
      await _storage.write(key: _lastAreaKey, value: area);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> clear() async {
    state = '';
    try {
      await _storage.delete(key: _lastAreaKey);
    } catch (_) {}
  }
}

// ── Fallback city data (used when the server endpoint is unreachable) ───────

const _fallbackCities = <ServiceCity>[
  ServiceCity(
    name: 'Karachi',
    areas: [
      'DHA',
      'Clifton',
      'Gulshan-e-Iqbal',
      'North Nazimabad',
      'PECHS',
      'Gulistan-e-Johar',
      'Bahadurabad',
      'Tariq Road',
    ],
  ),
  ServiceCity(
    name: 'Lahore',
    areas: [
      'DHA',
      'Gulberg',
      'Model Town',
      'Johar Town',
      'Cantt',
      'Bahria Town',
    ],
  ),
  ServiceCity(
    name: 'Islamabad',
    areas: ['F-6', 'F-7', 'F-8', 'F-10', 'F-11', 'G-9', 'G-10', 'G-11'],
  ),
  ServiceCity(name: 'Rawalpindi', areas: ['Satellite Town', 'Bahria Town']),
  ServiceCity(name: 'Faisalabad', areas: ['D-Ground', 'Peoples Colony']),
  ServiceCity(name: 'Multan', areas: ['Cantt', 'Gulgasht']),
  ServiceCity(name: 'Peshawar', areas: ['Hayatabad', 'University Town']),
  ServiceCity(name: 'Hyderabad', areas: ['Latifabad', 'Qasimabad']),
];
