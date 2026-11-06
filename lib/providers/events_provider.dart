import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dinner.dart';
import '../models/review.dart';
import '../repositories/events_repository.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';

/// Query parameters for the events feed. Value type so `family` recomputes only
/// when the filter actually changes.
class EventFilter {
  const EventFilter({
    this.type,
    this.audience,
    this.featured,
    this.query,
    this.city,
    this.includePast = false,
    this.maxPrice,
    this.from,
    this.to,
    this.sort,
  });

  final String? type;
  final String? audience;
  final bool? featured;
  final String? query;

  /// Venue-city scoping for location-based discovery (`?city=` on the feed).
  final String? city;
  final bool includePast;

  /// Upper bound on `price_per_seat` (filter sheet → `maxPrice=`).
  final double? maxPrice;

  /// ISO window bounds on `start_at` (filter sheet → `from`/`to`).
  final DateTime? from;
  final DateTime? to;

  /// Server-side sort mode: `soon` (default), `trending` (fill ratio), or
  /// `forYou` (venue cuisines overlapping the viewer's tastes).
  final String? sort;

  EventFilter copyWith({
    String? type,
    String? audience,
    bool? featured,
    String? query,
    String? city,
    bool? includePast,
    double? maxPrice,
    DateTime? from,
    DateTime? to,
    String? sort,
  }) => EventFilter(
    type: type ?? this.type,
    audience: audience ?? this.audience,
    featured: featured ?? this.featured,
    query: query ?? this.query,
    city: city ?? this.city,
    includePast: includePast ?? this.includePast,
    maxPrice: maxPrice ?? this.maxPrice,
    from: from ?? this.from,
    to: to ?? this.to,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventFilter &&
          other.type == type &&
          other.audience == audience &&
          other.featured == featured &&
          other.query == query &&
          other.city == city &&
          other.includePast == includePast &&
          other.maxPrice == maxPrice &&
          other.from == from &&
          other.to == to &&
          other.sort == sort;

  @override
  int get hashCode => Object.hash(
    type,
    audience,
    featured,
    query,
    city,
    includePast,
    maxPrice,
    from,
    to,
    sort,
  );
}

/// Filterable upcoming-events feed (Home / Explore).
final eventsFeedProvider = FutureProvider.family<List<Dinner>, EventFilter>((
  ref,
  filter,
) {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref
      .watch(eventsRepositoryProvider)
      .feed(
        type: filter.type,
        audience: filter.audience,
        featured: filter.featured,
        query: filter.query,
        city: filter.city,
        includePast: filter.includePast,
        maxPrice: filter.maxPrice,
        from: filter.from,
        to: filter.to,
        sort: filter.sort,
      );
});

/// A single event with menu, venue and attendees.
final dinnerDetailProvider = FutureProvider.family<Dinner, String>(
  (ref, id) => ref.watch(eventsRepositoryProvider).byId(id),
);

/// Other upcoming events hosted by the same user.
final hostEventsProvider = FutureProvider.family<List<Dinner>, String>(
  (ref, hostId) => ref.watch(eventsRepositoryProvider).byHost(hostId),
);

/// The signed-in host's own events, drafts included (`GET /events/mine`).
/// Host Studio reads this instead of the public feed so drafts surface there.
final myEventsProvider = FutureProvider<List<Dinner>>((ref) {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref.watch(eventsRepositoryProvider).mine();
});

/// Reviews for one event (DinnerDetail).
final reviewsForEventProvider = FutureProvider.family<List<Review>, String>(
  (ref, eventId) => ref.watch(eventsRepositoryProvider).reviewsFor(eventId),
);

/// Whether the signed-in user hosts the dinner with the given [hostId].
/// Replaces the old `Dinner.isHostedByCurrentUser` stub, which had no access
/// to the live session.
final isHostedByMeProvider = Provider.family<bool, String>((ref, hostId) {
  final me = ref.watch(currentUserIdProvider);
  return me != null && me == hostId;
});

/// Event-scoped writes. Each success invalidates the feed so a freshly
/// published or cancelled dinner shows up without a manual refresh.
class EventsController {
  EventsController(this._ref);

  final Ref _ref;

  /// Publishes a wizard draft (`POST /events`), or saves it as an invisible
  /// draft when [asDraft] is set. Throws [ApiException] (403 when
  /// the caller is not a host, 422 for an unknown venue) for the caller to
  /// surface; only invalidates the feed on success.
  Future<Dinner> publish(NewDinnerDraft draft, {bool asDraft = false}) async {
    final dinner = await _ref
        .read(eventsRepositoryProvider)
        .publish(draft, asDraft: asDraft);
    _ref.invalidate(eventsFeedProvider);
    _ref.invalidate(myEventsProvider);
    return dinner;
  }

  /// Edits or publishes one of the host's own drafts (`PATCH /events/:id`).
  /// A 422 ("Draft not ready to publish: …") throws [ApiException] for the
  /// caller to surface inline.
  Future<Dinner> patchEvent(String id, Map<String, dynamic> patch) async {
    final dinner = await _ref
        .read(eventsRepositoryProvider)
        .patchEvent(id, patch);
    _ref.invalidate(eventsFeedProvider);
    _ref.invalidate(myEventsProvider);
    return dinner;
  }

  /// The host cancels their own event (`DELETE /events/:id`).
  Future<void> cancelEvent(String id) async {
    await _ref.read(eventsRepositoryProvider).cancelEvent(id);
    _ref.invalidate(eventsFeedProvider);
    _ref.invalidate(myEventsProvider);
  }

  /// An attended guest posts a review (`POST /events/:id/reviews`). The server
  /// rejects non-attendees; on success the event's review list is refetched.
  Future<void> submitReview(
    String eventId, {
    required double rating,
    required String text,
  }) async {
    await _ref
        .read(eventsRepositoryProvider)
        .submitReview(eventId, rating: rating, text: text);
    _ref.invalidate(reviewsForEventProvider(eventId));
  }
}

final eventsControllerProvider = Provider<EventsController>(
  (ref) => EventsController(ref),
);
