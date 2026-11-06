import '../models/dinner.dart';
import '../models/review.dart';
import '../api/api_client.dart';
import '../api/dto/event_dto.dart';
import '../api/dto/review_dto.dart';
import '../api/json.dart';
import '../api/mappers/mappers.dart';

/// One course drafted in the Create-Dinner wizard, ready to publish.
class MenuCourseDraft {
  const MenuCourseDraft({
    required this.name,
    this.description = '',
    this.pairing,
    this.isSignature = false,
  });

  final String name;
  final String description;
  final String? pairing;
  final bool isSignature;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    if (pairing != null && pairing!.isNotEmpty) 'pairing': pairing,
    'isSignature': isSignature,
  };
}

/// The wizard's final state, serialized to the server's create-event contract.
class NewDinnerDraft {
  const NewDinnerDraft({
    required this.title,
    required this.description,
    required this.restaurantId,
    required this.coverImage,
    required this.startAt,
    required this.durationMinutes,
    required this.seatsTotal,
    required this.pricePerSeat,
    this.tagline = '',
    this.type = 'dinner',
    this.audience = 'public',
    this.menuStyle = 'familyStyle',
    this.included = const [],
    this.tags = const [],
    this.hostNote = '',
    this.menu = const [],
    this.requiresApproval = false,
  });

  final String title;
  final String tagline;
  final String description;
  final String restaurantId;
  final String coverImage;
  final DateTime startAt;
  final int durationMinutes;
  final int seatsTotal;
  final double pricePerSeat;
  final String type;
  final String audience;
  final String menuStyle;
  final List<String> included;
  final List<String> tags;
  final String hostNote;
  final List<MenuCourseDraft> menu;
  final bool requiresApproval;

  Map<String, dynamic> toJson() => {
    'title': title,
    'tagline': tagline,
    'description': description,
    'restaurantId': restaurantId,
    'coverImage': coverImage,
    'gallery': const <String>[],
    'startAt': startAt.toIso8601String(),
    'durationMinutes': durationMinutes,
    'seatsTotal': seatsTotal,
    'pricePerSeat': pricePerSeat,
    'type': type,
    'audience': audience,
    'menuStyle': menuStyle,
    'included': included,
    'tags': tags,
    'isFeatured': false,
    'hostNote': hostNote,
    'requiresApproval': requiresApproval,
    'menu': menu.map((m) => m.toJson()).toList(),
  };
}

/// Read access to the events feed plus the event-scoped writes the app
/// performs (publish, cancel, review, save reads).
///
/// Declared as an interface so widget tests can inject a fake that returns
/// fixtures without any network (Phase 2 test plan).
abstract class EventsRepository {
  Future<List<Dinner>> feed({
    String? type,
    String? audience,
    bool? featured,
    String? query,
    String? city,
    bool includePast = false,
    double? maxPrice,
    DateTime? from,
    DateTime? to,
    String? sort,
  });

  Future<Dinner> byId(String id);

  Future<List<Dinner>> byHost(String hostId);

  Future<List<Dinner>> byVenue(String venueId);

  Future<List<Review>> reviewsFor(String eventId);

  /// Publishes a wizard draft (`POST /events`). Host role required server-side.
  /// [asDraft] saves the event as an invisible draft instead (`status: 'draft'`).
  Future<Dinner> publish(NewDinnerDraft draft, {bool asDraft = false});

  /// The signed-in host's own events, drafts included (`GET /events/mine`).
  Future<List<Dinner>> mine();

  /// Edits or publishes one of the host's own drafts (`PATCH /events/:id`).
  Future<Dinner> patchEvent(String id, Map<String, dynamic> patch);

  /// The signed-in user cancels their own event (`DELETE /events/:id`).
  Future<void> cancelEvent(String id);

  /// Attended-guest review (`POST /events/:id/reviews`).
  Future<void> submitReview(
    String eventId, {
    required double rating,
    required String text,
  });

  /// Raw slim event rows from `GET /me/saved` (mapped by the social provider).
  Future<List<Map<String, dynamic>>> savedEvents();
}

class ApiEventsRepository implements EventsRepository {
  ApiEventsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Dinner>> feed({
    String? type,
    String? audience,
    bool? featured,
    String? query,
    String? city,
    bool includePast = false,
    double? maxPrice,
    DateTime? from,
    DateTime? to,
    String? sort,
  }) async {
    final body = await _client.getJson(
      '/events',
      query: {
        if (type != null && type.isNotEmpty) 'type': type,
        if (audience != null && audience.isNotEmpty) 'audience': audience,
        if (featured == true) 'featured': 'true',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        'maxPrice': ?maxPrice,
        'from': ?from?.toUtc().toIso8601String(),
        'to': ?to?.toUtc().toIso8601String(),
        if (includePast) 'upcoming': 'all',
        if (sort != null && sort.isNotEmpty) 'sort': sort,
      },
    );
    return asMapList(asMap(body)['events']).map(_eventToDinner).toList();
  }

  @override
  Future<Dinner> byId(String id) async {
    final body = await _client.getJson('/events/$id');
    final dto = EventDto.fromDetailEnvelope(asMap(body));
    return Mappers.dinnerFromEvent(dto);
  }

  @override
  Future<List<Dinner>> byHost(String hostId) async {
    final body = await _client.getJson(
      '/events',
      query: {'hostId': hostId, 'upcoming': 'all'},
    );
    return asMapList(asMap(body)['events']).map(_eventToDinner).toList();
  }

  @override
  Future<List<Dinner>> byVenue(String venueId) async {
    final body = await _client.getJson(
      '/events',
      query: {'venueId': venueId, 'upcoming': 'all'},
    );
    return asMapList(asMap(body)['events']).map(_eventToDinner).toList();
  }

  @override
  Future<List<Review>> reviewsFor(String eventId) async {
    final body = await _client.getJson('/reviews', query: {'eventId': eventId});
    return asMapList(asMap(body)['reviews'])
        .map((m) => Mappers.reviewFromDto(ReviewDto.fromJson(m)))
        .toList();
  }

  @override
  Future<Dinner> publish(NewDinnerDraft draft, {bool asDraft = false}) async {
    final body = await _client.postJson(
      '/events',
      body: {...draft.toJson(), if (asDraft) 'status': 'draft'},
    );
    return Mappers.dinnerFromEvent(EventDto.fromDetailEnvelope(asMap(body)));
  }

  @override
  Future<List<Dinner>> mine() async {
    final body = await _client.getJson('/events/mine');
    return asMapList(asMap(body)['events']).map(_eventToDinner).toList();
  }

  @override
  Future<Dinner> patchEvent(String id, Map<String, dynamic> patch) async {
    final body = await _client.patchJson('/events/$id', body: patch);
    return Mappers.dinnerFromEvent(EventDto.fromDetailEnvelope(asMap(body)));
  }

  @override
  Future<void> cancelEvent(String id) => _client.deleteJson('/events/$id');

  @override
  Future<void> submitReview(
    String eventId, {
    required double rating,
    required String text,
  }) => _client.postJson(
    '/events/$eventId/reviews',
    body: {'rating': rating, 'text': text},
  );

  @override
  Future<List<Map<String, dynamic>>> savedEvents() async {
    final body = await _client.getJson('/me/saved');
    return asMapList(asMap(body)['saved']);
  }

  static Dinner _eventToDinner(Map<String, dynamic> json) =>
      Mappers.dinnerFromEvent(EventDto.fromJson(json));
}
