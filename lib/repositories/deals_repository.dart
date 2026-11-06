import '../models/deal.dart';
import '../api/api_client.dart';
import '../api/json.dart';

/// Deals feed for the discovery tab (`GET /api/deals`).
abstract class DealsRepository {
  /// [city] narrows by venue city; [kind] filters by deal type; [query] is the
  /// free-text search the server applies to the whole active set.
  /// Returns active deals from partner restaurants.
  Future<List<Deal>> feed({String? city, String? kind, String? query});

  /// Returns active deals for a specific restaurant.
  Future<List<Deal>> forRestaurant(String restaurantId);
}

class ApiDealsRepository implements DealsRepository {
  ApiDealsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Deal>> feed({String? city, String? kind, String? query}) async {
    final body = await _client.getJson(
      '/deals',
      query: {
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        if (kind != null && kind.isNotEmpty && kind != 'all' && kind != 'any')
          'kind': kind,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    final deals = asMapList(asMap(body)['deals']);
    return deals.map(dealFromJson).toList();
  }

  @override
  Future<List<Deal>> forRestaurant(String restaurantId) async {
    final body = await _client.getJson('/restaurants/$restaurantId/deals');
    final deals = asMapList(asMap(body)['deals']);
    return deals.map(dealFromJson).toList();
  }
}

/// Maps one deal row from `/deals`, `/restaurants/:id/deals` or the universal
/// search (`/search` returns the identical serializer).
Deal dealFromJson(Map<String, dynamic> json) {
  final maxRedemptionsRaw = json['maxRedemptions'];
  return Deal(
    id: asString(json['id']),
    restaurantId: asString(json['restaurantId']),
    restaurantName: asString(json['restaurantName']),
    title: asString(json['title']),
    description: asString(json['description']),
    terms: asString(json['terms']),
    kind: asString(json['kind']),
    value: asDouble(json['value']),
    startsAt: DateTime.tryParse(asString(json['startsAt'])) ?? DateTime.now(),
    endsAt: DateTime.tryParse(asString(json['endsAt'])) ?? DateTime.now(),
    code: asStringOrNull(json['code']),
    maxRedemptions: maxRedemptionsRaw is int ? maxRedemptionsRaw : null,
    redemptions: asInt(json['redemptions']),
    status: asString(json['status']),
    city: asStringOrNull(json['city']),
    coverImage: asStringOrNull(json['coverImage']),
  );
}
