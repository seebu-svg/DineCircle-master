import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/offer.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';

/// Query key for the Deals & Offers feed. Value type so the `family` recomputes
/// only when [city] or [kind] actually changes (mirrors [VenueSearch]).
class OfferSearch {
  const OfferSearch({this.city = '', this.kind = 'all'});

  final String city;
  final String kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfferSearch && other.city == city && other.kind == kind;

  @override
  int get hashCode => Object.hash(city, kind);
}

/// Live deals + promo codes for the Deals & Offers category
/// (`GET /offers?city=&kind=`). Empty until the session is ready.
final offersFeedProvider = FutureProvider.family<OfferFeed, OfferSearch>((
  ref,
  search,
) {
  if (!ref.watch(authReadyProvider)) return const OfferFeed();
  return ref
      .watch(offersRepositoryProvider)
      .feed(city: search.city.isEmpty ? null : search.city, kind: search.kind);
});
