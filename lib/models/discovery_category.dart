import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The five primary discovery categories surfaced on the homepage and driving
/// the category-aware Explore view.
///
/// This is a UI-facing taxonomy only, each value maps onto existing server
/// query axes in [ExploreScreen]; it carries no server coupling of its own.
enum DiscoveryCategory {
  /// Reserve tables for individuals, couples, families, or friends.
  bookTable,

  /// Exclusive discounts, couple packages, group deals, and special menus.
  deals,

  /// Join public or private dinners hosted by influencers and community hosts.
  diningEvents,

  /// Meet new people, join shared tables, find dining companions by interest.
  socialDining,

  /// Chef's tables, food tastings, themed dinners, premium culinary events.
  experiences,
}

/// Presentation metadata for each [DiscoveryCategory] and a tolerant parser for
/// route/param strings.
extension DiscoveryCategoryX on DiscoveryCategory {
  String get label => switch (this) {
    DiscoveryCategory.bookTable => 'Book a Table',
    DiscoveryCategory.deals => 'Deals & Offers',
    DiscoveryCategory.diningEvents => 'Dining Events',
    DiscoveryCategory.socialDining => 'Social Dining',
    DiscoveryCategory.experiences => 'Exclusive Experiences',
  };

  String get subtitle => switch (this) {
    DiscoveryCategory.bookTable => 'Reserve a table near you',
    DiscoveryCategory.deals => 'Couple & group packages, special menus',
    DiscoveryCategory.diningEvents => 'Public dinners hosted by your circle',
    DiscoveryCategory.socialDining => 'Shared tables & dining companions',
    DiscoveryCategory.experiences => "Chef's tables, tastings & themed nights",
  };

  IconData get icon => switch (this) {
    DiscoveryCategory.bookTable => Icons.event_seat_rounded,
    DiscoveryCategory.deals => Icons.local_offer_rounded,
    DiscoveryCategory.diningEvents => Icons.restaurant_rounded,
    DiscoveryCategory.socialDining => Icons.groups_rounded,
    DiscoveryCategory.experiences => Icons.workspace_premium_rounded,
  };

  Color get tint => switch (this) {
    DiscoveryCategory.bookTable => AppColors.info,
    DiscoveryCategory.deals => AppColors.success,
    DiscoveryCategory.diningEvents => AppColors.primary,
    DiscoveryCategory.socialDining => AppColors.primaryLight,
    DiscoveryCategory.experiences => AppColors.gold,
  };

  /// Stable wire/route name (the enum identifier).
  String get key => name;

  /// Parses a route/query string back into a category, matching on the enum
  /// name case-insensitively. Returns `null` for unknown or empty input.
  static DiscoveryCategory? fromName(String? raw) {
    if (raw == null) return null;
    final needle = raw.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final value in DiscoveryCategory.values) {
      if (value.name.toLowerCase() == needle) return value;
    }
    return null;
  }
}
