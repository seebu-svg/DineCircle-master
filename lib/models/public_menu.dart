/// Public venue menu — the unauthenticated payload served to diners who scan
/// a QR code on a restaurant table. Mirrors `GET /api/public/menu/:restaurantId`.
library;

import '../utils/money.dart';

/// A single dish/drink inside a [PublicMenuSection].
class PublicMenuItem {
  const PublicMenuItem({
    required this.id,
    required this.name,
    this.description = '',
    this.price = 0,
    this.dietaryTags = const [],
    this.photoUrl,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final List<String> dietaryTags;
  final String? photoUrl;

  /// `Rs 2,450` — menu prices are PKR and always shown with the symbol.
  String get formattedPrice => formatPkr(price);

  /// Tags are authored freely by partners, so comparison and display both use
  /// a trimmed, lower-cased form (`Vegan` and `vegan` are the same filter).
  List<String> get normalizedDietaryTags => dietaryTags
      .map((t) => t.trim().toLowerCase())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();
}

/// A section (e.g. "Starters", "Mains") grouping related [PublicMenuItem]s.
class PublicMenuSection {
  const PublicMenuSection({
    required this.id,
    required this.name,
    this.position = 0,
    this.items = const [],
  });

  final String id;
  final String name;
  final int position;
  final List<PublicMenuItem> items;
}

/// Restaurant header data returned alongside the menu sections.
class PublicMenuRestaurant {
  const PublicMenuRestaurant({
    required this.id,
    required this.name,
    this.city = '',
    this.neighborhood = '',
    this.address = '',
    this.coverImage,
    this.openingHours = const {},
    this.amenities = const [],
  });

  final String id;
  final String name;
  final String city;

  /// Area within the city (e.g. `Do Darya`); empty on venues that never set it.
  final String neighborhood;
  final String address;
  final String? coverImage;
  final Map<String, dynamic> openingHours;
  final List<String> amenities;

  /// Compact location line for the menu hero: `Do Darya · Karachi`, degrading
  /// to whichever part the venue actually filled in.
  String get locationLine {
    final parts = [neighborhood, city].where((p) => p.trim().isNotEmpty);
    if (parts.isEmpty) return address.trim();
    return parts.join(' · ');
  }
}

/// Complete public menu payload: restaurant header + ordered sections.
class PublicMenu {
  const PublicMenu({
    required this.restaurant,
    this.sections = const [],
  });

  final PublicMenuRestaurant restaurant;
  final List<PublicMenuSection> sections;

  bool get isEmpty => sections.isEmpty;

  /// Sections that actually have dishes to show. The route already drops
  /// unavailable items, so a section can still arrive with an empty item list
  /// when every dish in it is out of stock; those must not become empty
  /// headings or dead tabs.
  List<PublicMenuSection> get filledSections =>
      sections.where((s) => s.items.isNotEmpty).toList();
}
