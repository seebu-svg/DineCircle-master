import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deal.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';

/// Query key for the Deals feed. Value type so the `family` recomputes
/// only when [city], [kind] or [query] actually changes.
class DealSearch {
  const DealSearch({this.city = '', this.kind = '', this.query = ''});

  final String city;
  final String kind;

  /// Free-text search, matched server-side against the deal and its venue so
  /// offers beyond the first page are still found.
  final String query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DealSearch &&
          other.city == city &&
          other.kind == kind &&
          other.query == query;

  @override
  int get hashCode => Object.hash(city, kind, query);
}

/// Live deals for the Deals tab (`GET /api/deals?city=&kind=&q=`).
/// Empty until the session is ready.
final dealsFeedProvider = FutureProvider.family<List<Deal>, DealSearch>((
  ref,
  search,
) {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref
      .watch(dealsRepositoryProvider)
      .feed(
        city: search.city.isEmpty ? null : search.city,
        kind: search.kind.isEmpty ? null : search.kind,
        query: search.query.isEmpty ? null : search.query,
      );
});

/// Active deals for a specific restaurant (`GET /api/restaurants/:id/deals`).
final restaurantDealsProvider =
    FutureProvider.family<List<Deal>, String>((ref, restaurantId) {
  return ref.watch(dealsRepositoryProvider).forRestaurant(restaurantId);
});
