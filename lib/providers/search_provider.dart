import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../models/search.dart';
import '../services/recent_searches_store.dart';
import 'api_client_provider.dart';

/// Local persistence for the recent-search chips.
final recentSearchesStoreProvider = Provider<RecentSearchesStore>(
  (ref) => RecentSearchesStore(ref.watch(secureStorageProvider)),
);

/// Where the search screen is in its lifecycle.
enum SearchStatus { idle, loading, ready, error }

@immutable
class SearchState {
  const SearchState({
    this.filters = const SearchFilters(),
    this.status = SearchStatus.idle,
    this.results = SearchResults.empty,
    this.error,
    this.category,
    this.page = 1,
    this.loadingMore = false,
  });

  final SearchFilters filters;
  final SearchStatus status;
  final SearchResults results;

  /// Human-readable failure for the error state (`ApiException.message`).
  final String? error;

  /// Active category chip; null means "All".
  final SearchCategory? category;
  final int page;
  final bool loadingMore;

  bool get isLoading => status == SearchStatus.loading;
  bool get hasError => status == SearchStatus.error;
  bool get isIdle => status == SearchStatus.idle;
  bool get hasSearched => filters.hasQuery && status != SearchStatus.idle;
  bool get hasResults => results.isNotEmpty;

  /// True when the last search finished and produced nothing anywhere.
  bool get isEmptyResult =>
      status == SearchStatus.ready && results.isEmpty && filters.hasQuery;

  SearchState copyWith({
    SearchFilters? filters,
    SearchStatus? status,
    SearchResults? results,
    String? error,
    bool clearError = false,
    SearchCategory? category,
    bool clearCategory = false,
    int? page,
    bool? loadingMore,
  }) => SearchState(
    filters: filters ?? this.filters,
    status: status ?? this.status,
    results: results ?? this.results,
    error: clearError ? null : (error ?? this.error),
    category: clearCategory ? null : (category ?? this.category),
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Owns the committed query, the active filters and the accumulated pages.
///
/// Named with the `Universal` prefix because Flutter's Material library already
/// exports a `SearchController` (the anchor-based search bar).
///
/// Typing only updates [SearchState.filters]; nothing is requested until the
/// user submits (keyboard action, a typeahead tap or a recent chip), so the
/// result list never flickers mid-word and one search costs one round-trip.
class UniversalSearchController extends Notifier<SearchState> {
  /// Every category is fetched on every page, so switching the chip row is
  /// instant and each chip can show its own count.
  static const Set<SearchCategory> allCategories = {
    SearchCategory.restaurants,
    SearchCategory.menu,
    SearchCategory.deals,
    SearchCategory.experiences,
    SearchCategory.hosts,
  };

  @override
  SearchState build() => const SearchState();

  /// Called on every keystroke. Does not hit the network.
  void queryChanged(String value) {
    if (value == state.filters.query) return;
    state = state.copyWith(
      filters: state.filters.copyWith(query: value),
      clearError: true,
    );
  }

  /// Runs (or re-runs) the search for the current text and filters.
  Future<void> submit([String? query]) async {
    final previous = state;
    final filters = previous.filters.copyWith(query: query ?? previous.filters.query);
    if (!filters.hasQuery) {
      state = SearchState(
        filters: filters.copyWith(query: ''),
        category: previous.category,
      );
      return;
    }
    state = SearchState(
      filters: filters,
      status: SearchStatus.loading,
      category: previous.category,
      // Re-submitting the same query keeps the rows visible (only the spinner
      // is added); a different query starts from a clean slate.
      results: filters == previous.filters
          ? previous.results
          : SearchResults.empty,
    );
    await _load(page: 1);
    // Persist only after the attempt: a failed search is still a search the
    // user wants to repeat, and the recent chips live off the same store.
    await ref.read(recentSearchesProvider.notifier).add(filters.query);
  }

  /// Applies the filter sheet, re-running the query when there is one.
  Future<void> applyFilters(SearchFilters filters) async {
    state = state.copyWith(filters: filters, clearError: true);
    if (filters.hasQuery) await submit();
  }

  /// Clears every filter but keeps the text and the results it produced.
  Future<void> clearFilters() async {
    if (!state.filters.hasFilters) return;
    await applyFilters(state.filters.cleared());
  }

  /// Back to the idle screen (recent chips) without losing the filters.
  void clear() {
    state = SearchState(
      filters: state.filters.copyWith(query: ''),
      category: state.category,
    );
  }

  void selectCategory(SearchCategory? category) {
    state = category == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(category: category);
  }

  /// Loads the next page of every category and appends it.
  Future<void> loadMore() async {
    if (state.loadingMore || state.isLoading) return;
    if (!state.results.hasMore.values.any((more) => more)) return;
    state = state.copyWith(loadingMore: true);
    await _load(page: state.page + 1, append: true);
  }

  /// Retries the page that failed.
  Future<void> retry() async {
    if (!state.filters.hasQuery) return;
    state = state.copyWith(status: SearchStatus.loading, clearError: true);
    await _load(page: state.page, append: state.page > 1);
  }

  Future<void> _load({required int page, bool append = false}) async {
    final filters = state.filters;
    try {
      final results = await ref
          .read(searchRepositoryProvider)
          .search(filters, categories: allCategories, page: page);
      // A newer submit landed while this request was in flight: its own
      // response is authoritative, so drop this one.
      if (state.filters != filters) return;
      state = state.copyWith(
        status: SearchStatus.ready,
        results: append && page > 1 ? state.results.merge(results) : results,
        page: page,
        loadingMore: false,
        clearError: true,
      );
    } catch (error) {
      if (state.filters != filters) return;
      state = state.copyWith(
        status: SearchStatus.error,
        error: _messageFor(error),
        loadingMore: false,
      );
    }
  }

  static String _messageFor(Object error) => error is ApiException
      ? error.message
      : 'Search is unavailable right now. Please try again.';
}

final searchControllerProvider =
    NotifierProvider<UniversalSearchController, SearchState>(
      UniversalSearchController.new,
    );

/// The most recent search terms, newest first.
class RecentSearchesController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() => ref.watch(recentSearchesStoreProvider).load();

  Future<void> add(String query) async {
    final next = await ref.read(recentSearchesStoreProvider).add(query);
    state = AsyncData(next);
  }

  Future<void> remove(String query) async {
    final next = await ref.read(recentSearchesStoreProvider).remove(query);
    state = AsyncData(next);
  }

  Future<void> clear() async {
    await ref.read(recentSearchesStoreProvider).clear();
    state = const AsyncData([]);
  }
}

final recentSearchesProvider =
    AsyncNotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

/// Typeahead strings for the in-progress query.
///
/// Auto-disposed per term so abandoned prefixes do not pile up, and never
/// throws: a suggestion failure must not block the user from typing a query
/// and pressing search.
final searchSuggestionsProvider =
    FutureProvider.autoDispose.family<List<SearchSuggestion>, String>((
      ref,
      query,
    ) async {
      if (query.trim().length < 2) return const [];
      try {
        return await ref.watch(searchRepositoryProvider).suggest(query);
      } catch (_) {
        return const [];
      }
    });
