import '../models/dinner.dart';
import '../models/restaurant.dart';
import '../api/api_client.dart';
import '../api/dto/restaurant_dto.dart';
import '../api/json.dart';
import '../api/mappers/mappers.dart';

/// A venue profile plus its upcoming events (from `/restaurants/:id`).
class RestaurantDetail {
  const RestaurantDetail({required this.restaurant, this.events = const []});

  final Restaurant restaurant;
  final List<Dinner> events;
}

abstract class RestaurantsRepository {
  Future<List<Restaurant>> list({
    bool? partner,
    String? query,
    String? tag,
    String? city,
  });

  /// Distance-ordered venues around a live GPS fix (`/restaurants/nearby`).
  /// Results carry `distanceKm`; venues without coordinates are excluded.
  Future<List<Restaurant>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 25,
  });
  Future<RestaurantDetail> byId(String id);

  /// Saves or unsaves a venue (`POST`/`DELETE /restaurants/:id/follow`).
  /// Returns the server's authoritative follow state so the caller can settle
  /// an optimistic toggle on the real value.
  Future<bool> setFollowing(String id, bool following);

  /// Venues the signed-in user saved (`GET /me/followed-restaurants`),
  /// newest first. Same payload shape as [list] so cards render identically.
  Future<List<Restaurant>> following();
}

class ApiRestaurantsRepository implements RestaurantsRepository {
  ApiRestaurantsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Restaurant>> list({
    bool? partner,
    String? query,
    String? tag,
    String? city,
  }) async {
    final body = await _client.getJson(
      '/restaurants',
      query: {
        if (partner == true) 'partner': 'true',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (tag != null && tag.trim().isNotEmpty) 'tag': tag.trim(),
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      },
    );
    return asMapList(asMap(body)['restaurants'])
        .map((m) => Mappers.restaurantFromDto(RestaurantDto.fromJson(m)))
        .toList();
  }

  @override
  Future<List<Restaurant>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 25,
  }) async {
    final body = await _client.getJson(
      '/restaurants/nearby',
      query: {'lat': lat, 'lng': lng, 'radiusKm': radiusKm},
    );
    return asMapList(asMap(body)['restaurants'])
        .map((m) => Mappers.restaurantFromDto(RestaurantDto.fromJson(m)))
        .toList();
  }

  @override
  Future<RestaurantDetail> byId(String id) async {
    final body = await _client.getJson('/restaurants/$id');
    final dto = RestaurantDetailDto.fromJson(asMap(body));
    final restaurant = Mappers.restaurantFromDto(dto.restaurant);
    final events = dto.events
        .map((e) => Mappers.dinnerFromVenueEvent(e, restaurant: restaurant))
        .toList();
    return RestaurantDetail(restaurant: restaurant, events: events);
  }

  @override
  Future<bool> setFollowing(String id, bool following) async {
    final body = following
        ? await _client.postJson('/restaurants/$id/follow')
        : await _client.deleteJson('/restaurants/$id/follow');
    return asBool(asMap(body)['isFollowing'], following);
  }

  @override
  Future<List<Restaurant>> following() async {
    final body = await _client.getJson('/me/followed-restaurants');
    return asMapList(asMap(body)['restaurants'])
        .map((m) => Mappers.restaurantFromDto(RestaurantDto.fromJson(m)))
        .toList();
  }
}
