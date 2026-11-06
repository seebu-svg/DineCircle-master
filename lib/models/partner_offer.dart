import 'restaurant.dart';

/// Partner offer type
enum OfferType { discount, specialMenu, exclusiveExperience }

/// Restaurant partner offer model
class PartnerOffer {
  final String id;
  final Restaurant restaurant;
  final String title;
  final String description;
  final OfferType type;
  final double? discountPercentage;
  final double? specialPrice;
  final String? imagePath;
  final DateTime validUntil;
  final int? maxRedemptions;
  final int currentRedemptions;

  const PartnerOffer({
    required this.id,
    required this.restaurant,
    required this.title,
    required this.description,
    required this.type,
    this.discountPercentage,
    this.specialPrice,
    this.imagePath,
    required this.validUntil,
    this.maxRedemptions,
    this.currentRedemptions = 0,
  });

  bool get isExpired => DateTime.now().isAfter(validUntil);
  bool get isFullyRedeemed =>
      maxRedemptions != null && currentRedemptions >= maxRedemptions!;
  bool get isAvailable => !isExpired && !isFullyRedeemed;

  String get typeLabel {
    switch (type) {
      case OfferType.discount:
        return 'Discount';
      case OfferType.specialMenu:
        return 'Special Menu';
      case OfferType.exclusiveExperience:
        return 'Exclusive';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartnerOffer &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
