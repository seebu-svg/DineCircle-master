/// A diner-facing deal derived from a restaurant's active special menu
/// (`GET /offers`). [kind] is the coarse bucket the server tags each menu with:
/// `couple`, `group`, or `tasting`.
class Offer {
  const Offer({
    required this.id,
    required this.name,
    required this.description,
    required this.restaurantId,
    required this.restaurantName,
    required this.city,
    required this.pricePerGuest,
    required this.minGuests,
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

  String get kindLabel => switch (kind) {
    'couple' => 'For two',
    'group' => 'Group deal',
    _ => 'Tasting',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Offer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A server-validated booking discount surfaced in the Deals feed.
class PromoCode {
  const PromoCode({required this.code, required this.discountPct});

  final String code;
  final double discountPct;

  String get label => '$code · ${discountPct.toStringAsFixed(0)}% off';
}

/// The `/offers` envelope: deal packages plus any live promo codes.
class OfferFeed {
  const OfferFeed({this.offers = const [], this.promos = const []});

  final List<Offer> offers;
  final List<PromoCode> promos;
}
