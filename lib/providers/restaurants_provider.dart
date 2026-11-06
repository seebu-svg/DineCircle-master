import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant.dart';
import '../repositories/restaurants_repository.dart';
import 'api_client_provider.dart';
import 'location_provider.dart';
import 'session_provider.dart';

/// All partner/trending venues (RestaurantDetail rails).
final restaurantsListProvider = FutureProvider.family<List<Restaurant>, bool?>((
  ref,
  partner,
) {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref.watch(restaurantsRepositoryProvider).list(partner: partner);
});

/// Venues inside a specific city, for the location map (WS-A). An empty
/// [city] falls back to the full list so the map still has markers before the
/// user's location is known.
final venuesInCityProvider = FutureProvider.family<List<Restaurant>, String>((
  ref,
  city,
) {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref
      .watch(restaurantsRepositoryProvider)
      .list(city: city.isEmpty ? null : city);
});

/// Distance-ordered venues for the discovery rails. When a live GPS fix is
/// available this hits `GET /restaurants/nearby` (rows carry `distanceKm`);
/// otherwise it degrades to the full list exactly like [restaurantsListProvider],
/// so the home/explore feeds still populate without location permission.
final nearbyRestaurantsProvider = FutureProvider<List<Restaurant>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  final fix = ref.watch(livePositionOrNullProvider);
  final repo = ref.watch(restaurantsRepositoryProvider);
  if (fix == null) return repo.list();
  final nearby = await repo.nearby(lat: fix.latitude, lng: fix.longitude);
  return rankByDistance(nearby, fix);
});

/// Venues the signed-in diner bookmarked (`GET /me/followed-restaurants`).
/// Backs the Saved → Restaurants tab; invalidated after a follow/unfollow.
final followedVenuesProvider = FutureProvider<List<Restaurant>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref.watch(restaurantsRepositoryProvider).following();
});

/// A single venue profile plus its upcoming events.
final restaurantDetailProvider =
    FutureProvider.family<RestaurantDetail, String>(
      (ref, id) => ref.watch(restaurantsRepositoryProvider).byId(id),
    );

/// Query key for the Explore venue search: the debounced free-text [query]
/// plus the active category [tag]. Value type so `family` recomputes only
/// when one of the two actually changes.
class VenueSearch {
  const VenueSearch({this.query = '', this.tag = ''});

  final String query;
  final String tag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VenueSearch && other.query == query && other.tag == tag;

  @override
  int get hashCode => Object.hash(query, tag);
}

/// Live venue results for the Explore search box (`GET /restaurants?q=&tag=`).
/// Feeds the "Venues" section that replaces the old client-only fold.
final venueSearchProvider =
    FutureProvider.family<List<Restaurant>, VenueSearch>((ref, search) {
      if (!ref.watch(authReadyProvider)) return const [];
      return ref
          .watch(restaurantsRepositoryProvider)
          .list(query: search.query, tag: search.tag);
    });
