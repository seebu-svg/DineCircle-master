import 'package:flutter/material.dart';

import 'deal.dart';
import 'dinner.dart';
import 'restaurant.dart';
import 'user_profile.dart';

/// The five entity types the universal search returns, in display order.
enum SearchCategory {
  restaurants('restaurants', 'Restaurants', Icons.restaurant_rounded),
  menu('menu', 'Dishes', Icons.local_dining_rounded),
  deals('deals', 'Deals', Icons.local_offer_rounded),
  experiences('experiences', 'Experiences', Icons.people_alt_rounded),
  hosts('hosts', 'Hosts', Icons.person_pin_circle_rounded);

  const SearchCategory(this.apiKey, this.label, this.icon);

  /// Wire value used in `?category=` and in the `counts`/`hasMore` maps.
  final String apiKey;
  final String label;
  final IconData icon;

  static SearchCategory fromApiKey(String key) => values.firstWhere(
    (category) => category.apiKey == key,
    orElse: () => SearchCategory.restaurants,
  );
}

/// Everything the search surface filters on. A value type so it can key a
/// Riverpod `family` without re-querying on unrelated rebuilds.
///
/// [query] is the committed free text (what the user actually submitted or
/// last typed past the debounce); the remaining fields come from the filter
/// sheet and stay server-side (one round-trip, no client-side filtering).
@immutable
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.city = '',
    this.cuisine = '',
    this.venueType = '',
    this.dealKind = '',
    this.from,
    this.to,
    this.availableOnly = false,
  });

  final String query;

  /// Venue city (`Karachi`, `Lahore`, …). Empty means anywhere.
  final String city;

  /// Cuisine chip (`Sushi`, `BBQ`, …); matched against `restaurants.cuisines`.
  final String cuisine;

  /// Restaurant type chip (`fine dining`, `rooftop`, `cafe`, …) matched against
  /// the tag/cuisine arrays.
  final String venueType;

  /// Deal kind (`percent`, `fixed`, `package`); empty means every kind.
  final String dealKind;

  /// Experience window bounds (inclusive).
  final DateTime? from;
  final DateTime? to;

  /// Only tables with seats left.
  final bool availableOnly;

  bool get hasQuery => query.trim().isNotEmpty;
  bool get hasDateWindow => from != null || to != null;

  /// How many filters are active, shown as the badge on the filter button.
  int get activeCount {
    var count = 0;
    if (city.isNotEmpty) count++;
    if (cuisine.isNotEmpty) count++;
    if (venueType.isNotEmpty) count++;
    if (dealKind.isNotEmpty) count++;
    if (hasDateWindow) count++;
    if (availableOnly) count++;
    return count;
  }

  bool get hasFilters => activeCount > 0;

  SearchFilters copyWith({
    String? query,
    String? city,
    String? cuisine,
    String? venueType,
    String? dealKind,
    DateTime? from,
    DateTime? to,
    bool? availableOnly,
    bool clearDates = false,
  }) => SearchFilters(
    query: query ?? this.query,
    city: city ?? this.city,
    cuisine: cuisine ?? this.cuisine,
    venueType: venueType ?? this.venueType,
    dealKind: dealKind ?? this.dealKind,
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    availableOnly: availableOnly ?? this.availableOnly,
  );

  /// Clears every filter sheet value but keeps the typed query.
  SearchFilters cleared() => SearchFilters(query: query);

  /// Query parameters for `GET /api/search`.
  Map<String, dynamic> toQuery({
    int page = 1,
    int limit = 10,
    Set<SearchCategory>? categories,
  }) => {
    'q': query.trim(),
    if (city.trim().isNotEmpty) 'city': city.trim(),
    if (cuisine.trim().isNotEmpty) 'cuisine': cuisine.trim(),
    if (venueType.trim().isNotEmpty) 'type': venueType.trim(),
    if (dealKind.trim().isNotEmpty) 'dealKind': dealKind.trim(),
    if (from != null) 'from': from!.toUtc().toIso8601String(),
    if (to != null) 'to': to!.toUtc().toIso8601String(),
    if (availableOnly) 'available': 'true',
    if (categories != null && categories.isNotEmpty)
      'category': categories.map((category) => category.apiKey).join(','),
    'page': page,
    'limit': limit,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchFilters &&
          other.query == query &&
          other.city == city &&
          other.cuisine == cuisine &&
          other.venueType == venueType &&
          other.dealKind == dealKind &&
          other.from == from &&
          other.to == to &&
          other.availableOnly == availableOnly;

  @override
  int get hashCode => Object.hash(
    query,
    city,
    cuisine,
    venueType,
    dealKind,
    from,
    to,
    availableOnly,
  );
}

/// A dish matched across every venue menu.
class MenuItemHit {
  const MenuItemHit({
    required this.id,
    required this.name,
    required this.restaurantId,
    required this.restaurantName,
    this.description = '',
    this.price = 0,
    this.photoUrl = '',
    this.sectionName = '',
    this.dietaryTags = const [],
    this.restaurantNeighborhood = '',
    this.restaurantCity = '',
    this.restaurantCoverImage,
  });

  final String id;
  final String name;
  final String restaurantId;
  final String restaurantName;
  final String description;
  final double price;
  final String photoUrl;
  final String sectionName;
  final List<String> dietaryTags;
  final String restaurantNeighborhood;
  final String restaurantCity;
  final String? restaurantCoverImage;

  /// `Section · Venue`, what the diner needs to place the dish.
  String get subtitle => [
    sectionName,
    restaurantName,
  ].where((part) => part.trim().isNotEmpty).join(' · ');

  /// `Clifton · Karachi`, falling back to whichever half exists.
  String get locationLine => [
    restaurantNeighborhood,
    restaurantCity,
  ].where((part) => part.trim().isNotEmpty).join(' · ');
}

/// What a typeahead row points at.
enum SuggestionKind {
  restaurant('restaurant', Icons.restaurant_rounded),
  cuisine('cuisine', Icons.ramen_dining_rounded),
  menu('menu', Icons.local_dining_rounded),
  deal('deal', Icons.local_offer_rounded),
  experience('experience', Icons.people_alt_rounded),
  host('host', Icons.person_pin_circle_rounded);

  const SuggestionKind(this.apiKey, this.icon);

  final String apiKey;
  final IconData icon;

  static SuggestionKind fromApiKey(String key) => values.firstWhere(
    (kind) => kind.apiKey == key,
    orElse: () => SuggestionKind.restaurant,
  );
}

/// One typeahead entry (`GET /api/search/suggest`).
class SearchSuggestion {
  const SearchSuggestion({
    required this.text,
    required this.kind,
    this.refId,
  });

  final String text;
  final SuggestionKind kind;

  /// Venue/deal/experience/host id when the server knows one; null for a
  /// cuisine, which is re-run as a fresh query instead of opening a screen.
  final String? refId;
}

/// One page of ranked results, grouped by category.
class SearchResults {
  const SearchResults({
    required this.query,
    this.page = 1,
    this.limit = 10,
    this.restaurants = const [],
    this.menuItems = const [],
    this.deals = const [],
    this.experiences = const [],
    this.hosts = const [],
    this.counts = const {},
    this.hasMore = const {},
  });

  static const empty = SearchResults(query: '');

  final String query;
  final int page;
  final int limit;
  final List<Restaurant> restaurants;
  final List<MenuItemHit> menuItems;
  final List<Deal> deals;
  final List<Dinner> experiences;
  final List<UserProfile> hosts;

  /// Unpaged totals per category (for the "See all (12)" chips).
  final Map<SearchCategory, int> counts;

  /// Whether another page exists per category.
  final Map<SearchCategory, bool> hasMore;

  int countFor(SearchCategory category) =>
      counts[category] ??
      switch (category) {
        SearchCategory.restaurants => restaurants.length,
        SearchCategory.menu => menuItems.length,
        SearchCategory.deals => deals.length,
        SearchCategory.experiences => experiences.length,
        SearchCategory.hosts => hosts.length,
      };

  bool hasMoreFor(SearchCategory category) => hasMore[category] ?? false;

  List<Object> itemsFor(SearchCategory category) => switch (category) {
    SearchCategory.restaurants => restaurants,
    SearchCategory.menu => menuItems,
    SearchCategory.deals => deals,
    SearchCategory.experiences => experiences,
    SearchCategory.hosts => hosts,
  };

  bool get isEmpty =>
      restaurants.isEmpty &&
      menuItems.isEmpty &&
      deals.isEmpty &&
      experiences.isEmpty &&
      hosts.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Total hits across every category on this page.
  int get total => counts.entries.fold(0, (sum, entry) => sum + entry.value);

  /// Appends the next page's rows, keeping the newest totals/flags.
  SearchResults merge(SearchResults next) => SearchResults(
    query: next.query,
    page: next.page,
    limit: next.limit,
    restaurants: [...restaurants, ...next.restaurants],
    menuItems: [...menuItems, ...next.menuItems],
    deals: [...deals, ...next.deals],
    experiences: [...experiences, ...next.experiences],
    hosts: [...hosts, ...next.hosts],
    counts: next.counts.isEmpty ? counts : next.counts,
    hasMore: next.hasMore,
  );
}
