import '../models/offer.dart';
import '../api/api_client.dart';
import '../api/dto/offer_dto.dart';
import '../api/json.dart';
import '../api/mappers/mappers.dart';

/// Deals & Offers feed for the discovery categories (`GET /offers`).
abstract class OffersRepository {
  /// [city] narrows by venue city; [kind] is `all` | `couple` | `group` |
  /// `tasting`. Returns both the deal packages and any live promo codes.
  Future<OfferFeed> feed({String? city, String kind = 'all'});
}

class ApiOffersRepository implements OffersRepository {
  ApiOffersRepository(this._client);

  final ApiClient _client;

  @override
  Future<OfferFeed> feed({String? city, String kind = 'all'}) async {
    final body = await _client.getJson(
      '/offers',
      query: {
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        if (kind.isNotEmpty && kind != 'all' && kind != 'any') 'kind': kind,
      },
    );
    return Mappers.offerFeedFromDto(OfferFeedDto.fromJson(asMap(body)));
  }
}
