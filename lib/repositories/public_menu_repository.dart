import '../api/api_client.dart';
import '../api/json.dart';
import '../models/public_menu.dart';

/// Fetches the unauthenticated public menu for a restaurant
/// (`GET /api/public/menu/:restaurantId`).
abstract class PublicMenuRepository {
  Future<PublicMenu> fetch(String restaurantId);

  /// Records a QR scan for analytics (fire-and-forget, rate-limited server-side).
  Future<void> recordScan(String restaurantId);
}

class ApiPublicMenuRepository implements PublicMenuRepository {
  ApiPublicMenuRepository(this._client);

  final ApiClient _client;

  @override
  Future<PublicMenu> fetch(String restaurantId) async {
    final body = asMap(await _client.getJson('/public/menu/$restaurantId'));
    return _parseMenu(body);
  }

  @override
  Future<void> recordScan(String restaurantId) async {
    try {
      await _client.postJson('/public/menu/$restaurantId/scan', body: {});
    } catch (_) {
      // Fire-and-forget — scan recording is best-effort for analytics.
    }
  }

  static PublicMenu _parseMenu(Map<String, dynamic> json) {
    final r = asMap(json['restaurant']);
    final restaurant = PublicMenuRestaurant(
      id: asString(r['id']),
      name: asString(r['name']),
      city: asString(r['city']),
      neighborhood: asString(r['neighborhood']),
      address: asString(r['address']),
      coverImage: asStringOrNull(r['coverImage']),
      openingHours: asMap(r['openingHours']),
      amenities: asStringList(r['amenities']),
    );

    final sections = asMapList(json['sections']).map((s) {
      final items = asMapList(s['items']).map((i) {
        return PublicMenuItem(
          id: asString(i['id']),
          name: asString(i['name']),
          description: asString(i['description']),
          price: asDouble(i['price']),
          dietaryTags: asStringList(i['dietaryTags']),
          photoUrl: asStringOrNull(i['photoUrl']),
        );
      }).toList();

      return PublicMenuSection(
        id: asString(s['id']),
        name: asString(s['name']),
        position: asInt(s['position']),
        items: items,
      );
    }).toList();

    return PublicMenu(restaurant: restaurant, sections: sections);
  }
}
