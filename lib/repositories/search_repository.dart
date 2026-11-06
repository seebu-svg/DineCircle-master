import '../api/api_client.dart';
import '../api/dto/event_dto.dart';
import '../api/dto/restaurant_dto.dart';
import '../api/dto/search_dto.dart';
import '../api/dto/user_dto.dart';
import '../api/json.dart';
import '../api/mappers/mappers.dart';
import '../models/search.dart';
import 'deals_repository.dart' show dealFromJson;

/// Universal search over restaurants, dishes, deals, experiences and hosts.
///
/// One endpoint (`GET /api/search`) returns every category in a single
/// round-trip, ranked server-side; `suggest` backs the typeahead
/// (`GET /api/search/suggest`).
abstract class SearchRepository {
  Future<SearchResults> search(
    SearchFilters filters, {
    Set<SearchCategory> categories = const {
      SearchCategory.restaurants,
      SearchCategory.menu,
      SearchCategory.deals,
      SearchCategory.experiences,
      SearchCategory.hosts,
    },
    int page = 1,
    int limit = 10,
  });

  /// Typeahead strings; returns an empty list for a term shorter than 2 chars.
  Future<List<SearchSuggestion>> suggest(String query);
}

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._client);

  final ApiClient _client;

  @override
  Future<SearchResults> search(
    SearchFilters filters, {
    Set<SearchCategory> categories = const {
      SearchCategory.restaurants,
      SearchCategory.menu,
      SearchCategory.deals,
      SearchCategory.experiences,
      SearchCategory.hosts,
    },
    int page = 1,
    int limit = 10,
  }) async {
    final body = await _client.getJson(
      '/search',
      query: filters.toQuery(page: page, limit: limit, categories: categories),
    );
    final dto = SearchResponseDto.fromJson(asMap(body));
    return SearchResults(
      query: dto.query.isEmpty ? filters.query : dto.query,
      page: dto.page,
      limit: dto.limit,
      restaurants: dto.restaurants
          .map((row) => Mappers.restaurantFromDto(RestaurantDto.fromJson(row)))
          .toList(),
      menuItems: dto.menu.map(_menuItemFromJson).toList(),
      deals: dto.deals.map(dealFromJson).toList(),
      experiences: dto.experiences
          .map((row) => Mappers.dinnerFromEvent(EventDto.fromJson(row)))
          .toList(),
      hosts: dto.hosts
          .map((row) => Mappers.userFromDto(UserDto.fromJson(row)))
          .toList(),
      counts: _keyed(dto.counts),
      hasMore: _keyed(dto.hasMore),
    );
  }

  @override
  Future<List<SearchSuggestion>> suggest(String query) async {
    final term = query.trim();
    if (term.length < 2) return const [];
    final body = await _client.getJson('/search/suggest', query: {'q': term});
    return SearchSuggestionsDto.fromJson(asMap(body)).suggestions
        .map(
          (row) => SearchSuggestion(
            text: asString(row['text']),
            kind: SuggestionKind.fromApiKey(asString(row['kind'])),
            refId: asStringOrNull(row['refId']),
          ),
        )
        .where((suggestion) => suggestion.text.trim().isNotEmpty)
        .toList();
  }

  /// Unknown keys are skipped rather than coerced, so a future server category
  /// cannot silently show up as "restaurants".
  static Map<SearchCategory, T> _keyed<T>(Map<String, T> raw) {
    final keyed = <SearchCategory, T>{};
    for (final entry in raw.entries) {
      final category = _category(entry.key);
      if (category != null) keyed[category] = entry.value;
    }
    return keyed;
  }

  static SearchCategory? _category(String apiKey) {
    for (final category in SearchCategory.values) {
      if (category.apiKey == apiKey) return category;
    }
    return null;
  }

  static MenuItemHit _menuItemFromJson(Map<String, dynamic> json) {
    final restaurant = asMap(json['restaurant']);
    return MenuItemHit(
      id: asString(json['id']),
      name: asString(json['name']),
      restaurantId: asString(restaurant['id']),
      restaurantName: asString(restaurant['name']),
      description: asString(json['description']),
      price: asDouble(json['price']),
      photoUrl: asString(json['photoUrl']),
      sectionName: asString(json['sectionName']),
      dietaryTags: asStringList(json['dietaryTags']),
      restaurantNeighborhood: asString(restaurant['neighborhood']),
      restaurantCity: asString(restaurant['city']),
      restaurantCoverImage: asStringOrNull(restaurant['coverImage']),
    );
  }
}
