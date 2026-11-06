/// A restaurant deal surfaced to diners (`GET /api/deals`).
///
/// Deals are created by partners via the Partner App and stored in
/// `restaurant_deals`. The customer app reads active deals for discovery.
class Deal {
  const Deal({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.title,
    required this.description,
    required this.kind,
    required this.value,
    required this.startsAt,
    required this.endsAt,
    this.terms = '',
    this.code,
    this.maxRedemptions,
    this.redemptions = 0,
    this.status = 'active',
    this.city,
    this.coverImage,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String title;
  final String description;
  /// Conditions and redemption steps shown under the offer copy.
  final String terms;
  final String kind; // 'percent', 'fixed', 'package'
  final double value;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? code;
  final int? maxRedemptions;
  final int redemptions;
  final String status;
  final String? city;
  final String? coverImage;

  /// Human-readable label for the deal kind.
  String get kindLabel => switch (kind) {
    'percent' => '${value.toStringAsFixed(0)}% off',
    'fixed' => 'Rs ${value.toStringAsFixed(0)} off',
    'package' => 'Package deal',
    _ => 'Deal',
  };

  /// Whether the deal is currently active (not expired, not paused).
  bool get isActive => status == 'active' && endsAt.isAfter(DateTime.now());

  /// Whether a promo code is required to redeem.
  bool get requiresCode => code != null && code!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Deal && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
