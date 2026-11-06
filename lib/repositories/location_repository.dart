import '../models/saved_location.dart';
import '../api/api_client.dart';
import '../api/json.dart';

/// A supported DineCircle city returned by `GET /api/cities`.
class ServiceCity {
  final String name;
  final String country;
  final List<String> areas;

  const ServiceCity({
    required this.name,
    this.country = 'Pakistan',
    this.areas = const [],
  });

  factory ServiceCity.fromJson(Map<String, dynamic> json) => ServiceCity(
    name: json['name'] as String,
    country: json['country'] as String? ?? '',
    areas: (json['areas'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toList(),
  );
}

/// Location data access — supported cities and the user's saved locations.
abstract class LocationRepository {
  /// Supported DineCircle cities with their neighbourhoods.
  Future<List<ServiceCity>> supportedCities();

  /// The viewer's saved locations (Home, Work, favourites).
  Future<List<SavedLocation>> savedLocations();

  /// Create or update a saved location.
  Future<SavedLocation> saveLocation(SavedLocation location);

  /// Remove a saved location by id.
  Future<void> deleteLocation(String id);
}

class ApiLocationRepository implements LocationRepository {
  ApiLocationRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<ServiceCity>> supportedCities() async {
    final body = await _client.getJson('/cities');
    return asMapList(asMap(body)['cities'])
        .map((m) => ServiceCity.fromJson(m))
        .toList();
  }

  @override
  Future<List<SavedLocation>> savedLocations() async {
    final body = await _client.getJson('/users/me/saved-locations');
    return asMapList(asMap(body)['locations'])
        .map((m) => SavedLocation.fromJson(m))
        .toList();
  }

  @override
  Future<SavedLocation> saveLocation(SavedLocation location) async {
    final body = await _client.postJson(
      '/users/me/saved-locations',
      body: location.toJson(),
    );
    return SavedLocation.fromJson(asMap(body));
  }

  @override
  Future<void> deleteLocation(String id) async {
    await _client.deleteJson('/users/me/saved-locations/$id');
  }
}
