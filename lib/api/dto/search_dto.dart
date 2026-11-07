import '../json.dart';

/// Envelope of `GET /api/search`, five categorised lists plus the unpaged
/// totals and the per-category "another page exists" flags.
///
/// Parsing only: the DTO keeps the raw maps so the repository can map them with
/// the same mappers the individual feeds already use (restaurants, deals,
/// events, users), instead of inventing a second shape for the same rows.
class SearchResponseDto {
  const SearchResponseDto({
    this.query = '',
    this.page = 1,
    this.limit = 10,
    this.restaurants = const [],
    this.menu = const [],
    this.deals = const [],
    this.experiences = const [],
    this.hosts = const [],
    this.counts = const {},
    this.hasMore = const {},
  });

  final String query;
  final int page;
  final int limit;
  final List<Map<String, dynamic>> restaurants;
  final List<Map<String, dynamic>> menu;
  final List<Map<String, dynamic>> deals;
  final List<Map<String, dynamic>> experiences;
  final List<Map<String, dynamic>> hosts;

  /// `{"restaurants": 12, "menu": 3, …}` keyed by API category name.
  final Map<String, int> counts;

  /// `{"restaurants": true, …}` keyed by API category name.
  final Map<String, bool> hasMore;

  factory SearchResponseDto.fromJson(Map<String, dynamic> json) {
    return SearchResponseDto(
      query: asString(json['query']),
      page: asInt(json['page'], 1),
      limit: asInt(json['limit'], 10),
      restaurants: asMapList(json['restaurants']),
      menu: asMapList(json['menu']),
      deals: asMapList(json['deals']),
      experiences: asMapList(json['experiences']),
      hosts: asMapList(json['hosts']),
      counts: {
        for (final entry in asMap(json['counts']).entries)
          entry.key: asInt(entry.value),
      },
      hasMore: {
        for (final entry in asMap(json['hasMore']).entries)
          entry.key: asBool(entry.value),
      },
    );
  }
}

/// Envelope of `GET /api/search/suggest`.
class SearchSuggestionsDto {
  const SearchSuggestionsDto(this.suggestions);

  final List<Map<String, dynamic>> suggestions;

  factory SearchSuggestionsDto.fromJson(Map<String, dynamic> json) =>
      SearchSuggestionsDto(asMapList(json['suggestions']));
}
