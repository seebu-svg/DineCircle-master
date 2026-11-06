import '../json.dart';

/// One deal row from `GET /offers`. The server already serialises to camelCase,
/// so this is a thin, null-safe parse.
class OfferDto {
  const OfferDto({
    required this.id,
    required this.name,
    this.description = '',
    this.restaurantId = '',
    this.restaurantName = '',
    this.city = '',
    this.pricePerGuest = 0,
    this.minGuests = 2,
    this.coverImage,
    this.tags = const [],
    this.kind = 'tasting',
  });

  final String id;
  final String name;
  final String description;
  final String restaurantId;
  final String restaurantName;
  final String city;
  final double pricePerGuest;
  final int minGuests;
  final String? coverImage;
  final List<String> tags;
  final String kind;

  static OfferDto fromJson(Map<String, dynamic> json) => OfferDto(
    id: asString(json['id']),
    name: asString(json['name']),
    description: asString(json['description']),
    restaurantId: asString(json['restaurantId']),
    restaurantName: asString(json['restaurantName']),
    city: asString(json['city']),
    pricePerGuest: asDouble(json['pricePerGuest']),
    minGuests: asInt(json['minGuests'], 2),
    coverImage: asStringOrNull(json['coverImage']),
    tags: asStringList(json['tags']),
    kind: asString(json['kind'], 'tasting'),
  );
}

/// A promo code row from `GET /offers`.
class PromoCodeDto {
  const PromoCodeDto({required this.code, this.discountPct = 0});

  final String code;
  final double discountPct;

  static PromoCodeDto fromJson(Map<String, dynamic> json) => PromoCodeDto(
    code: asString(json['code']),
    discountPct: asDouble(json['discountPct']),
  );
}

/// Parsed `/offers` envelope.
class OfferFeedDto {
  const OfferFeedDto({this.offers = const [], this.promos = const []});

  final List<OfferDto> offers;
  final List<PromoCodeDto> promos;

  static OfferFeedDto fromJson(Map<String, dynamic> json) => OfferFeedDto(
    offers: asMapList(json['offers']).map(OfferDto.fromJson).toList(),
    promos: asMapList(json['promos']).map(PromoCodeDto.fromJson).toList(),
  );
}
