import '../json.dart';

/// Slim host reference embedded in event payloads (`host: {id,name,handle,
/// avatarUrl}` plus the growth-tier flags the server derives from role/badges).
class HostRef {
  const HostRef({
    required this.id,
    required this.name,
    this.handle,
    this.avatarUrl,
    this.isVerified = false,
    this.isInfluencer = false,
  });

  final String id;
  final String name;
  final String? handle;
  final String? avatarUrl;
  final bool isVerified;
  final bool isInfluencer;

  static HostRef? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return HostRef(
      id: asString(json['id']),
      name: asString(json['name']),
      handle: asStringOrNull(json['handle']),
      avatarUrl: asStringOrNull(json['avatarUrl']),
      isVerified: asBool(json['isVerified']),
      isInfluencer: asBool(json['isInfluencer']),
    );
  }
}

/// Slim venue reference embedded in event list payloads.
class VenueRef {
  const VenueRef({
    required this.id,
    required this.name,
    this.neighborhood,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String? neighborhood;
  final double? latitude;
  final double? longitude;

  static VenueRef? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return VenueRef(
      id: asString(json['id']),
      name: asString(json['name']),
      neighborhood: asStringOrNull(json['neighborhood']),
      latitude: asDoubleOrNull(json['latitude']),
      longitude: asDoubleOrNull(json['longitude']),
    );
  }
}

/// One menu course returned on the event detail payload.
class MenuCourseDto {
  const MenuCourseDto({
    required this.id,
    required this.name,
    this.position = 0,
    this.description = '',
    this.pairing,
    this.isSignature = false,
  });

  final String id;
  final String name;
  final int position;
  final String description;
  final String? pairing;
  final bool isSignature;

  static MenuCourseDto fromJson(Map<String, dynamic> json) => MenuCourseDto(
    id: asString(json['id']),
    name: asString(json['name']),
    position: asInt(json['position']),
    description: asString(json['description']),
    pairing: asStringOrNull(json['pairing']),
    isSignature: asBool(json['isSignature']),
  );
}

/// A confirmed attendee reference (event detail payload).
class AttendeeRef {
  const AttendeeRef({
    required this.id,
    required this.name,
    this.handle,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? handle;
  final String? avatarUrl;

  static AttendeeRef fromJson(Map<String, dynamic> json) => AttendeeRef(
    id: asString(json['id']),
    name: asString(json['name']),
    handle: asStringOrNull(json['handle']),
    avatarUrl: asStringOrNull(json['avatarUrl']),
  );
}

/// Raw event payload. The same shape backs both the list endpoint (`/events`)
/// and the richer detail endpoint (`/events/:id`, which adds `menu`, `venue`
/// and `attendees`). Detail-only fields fall back to empty when absent.
class EventDto {
  const EventDto({
    required this.id,
    required this.title,
    this.tagline = '',
    this.description = '',
    this.hostId,
    this.host,
    this.restaurantId,
    this.restaurant,
    this.coverImage,
    this.gallery = const [],
    this.startAt,
    this.durationMinutes = 0,
    this.seatsTotal = 0,
    this.seatsBooked = 0,
    this.pricePerSeat = 0,
    this.type = 'dinner',
    this.audience = 'public',
    this.menuStyle = '',
    this.included = const [],
    this.tags = const [],
    this.isFeatured = false,
    this.hostNote = '',
    this.language = '',
    this.dressCode = '',
    this.cancellation = '',
    this.attendeeIds = const [],
    this.status = 'confirmed',
    this.declineReason = '',
    this.requiresApproval = false,
    this.approvalStaleAt,
    this.restaurantApprovedAt,
    this.cancelledAt,
    this.cancellationReason = '',
    this.menu = const [],
    this.venue,
    this.attendees = const [],
  });

  final String id;
  final String title;
  final String tagline;
  final String description;
  final String? hostId;
  final HostRef? host;
  final String? restaurantId;
  final VenueRef? restaurant;
  final String? coverImage;
  final List<String> gallery;
  final DateTime? startAt;
  final int durationMinutes;
  final int seatsTotal;
  final int seatsBooked;
  final double pricePerSeat;
  final String type;
  final String audience;
  final String menuStyle;
  final List<String> included;
  final List<String> tags;
  final bool isFeatured;
  final String hostNote;
  final String language;
  final String dressCode;
  final String cancellation;
  final List<String> attendeeIds;
  final String status;

  // ── Venue approval trail ──
  // The server serialises these on every event, so Host Studio can render the
  // real approval state instead of guessing from `status` alone.
  final String declineReason;
  final bool requiresApproval;
  final DateTime? approvalStaleAt;
  final DateTime? restaurantApprovedAt;
  final DateTime? cancelledAt;
  final String cancellationReason;

  // ── Detail-only ──
  final List<MenuCourseDto> menu;
  final Map<String, dynamic>? venue;
  final List<AttendeeRef> attendees;

  int get seatsLeft => (seatsTotal - seatsBooked).clamp(0, seatsTotal);
  bool get isSoldOut => seatsLeft <= 0;

  static EventDto fromJson(Map<String, dynamic> json) => EventDto(
    id: asString(json['id']),
    title: asString(json['title']),
    tagline: asString(json['tagline']),
    description: asString(json['description']),
    hostId: asStringOrNull(json['hostId']),
    host: HostRef.fromJson(asMap(json['host'])),
    restaurantId: asStringOrNull(json['restaurantId']),
    restaurant: VenueRef.fromJson(asMap(json['restaurant'])),
    coverImage: asStringOrNull(json['coverImage']),
    gallery: asStringList(json['gallery']),
    startAt: asDateOrNull(json['startAt']),
    durationMinutes: asInt(json['durationMinutes']),
    seatsTotal: asInt(json['seatsTotal']),
    seatsBooked: asInt(json['seatsBooked']),
    pricePerSeat: asDouble(json['pricePerSeat']),
    type: asString(json['type'], 'dinner'),
    audience: asString(json['audience'], 'public'),
    menuStyle: asString(json['menuStyle']),
    included: asStringList(json['included']),
    tags: asStringList(json['tags']),
    isFeatured: asBool(json['isFeatured']),
    hostNote: asString(json['hostNote']),
    language: asString(json['language']),
    dressCode: asString(json['dressCode']),
    cancellation: asString(json['cancellation']),
    attendeeIds: asStringList(json['attendeeIds']),
    status: asString(json['status'], 'confirmed'),
    declineReason: asString(json['declineReason']),
    requiresApproval: asBool(json['requiresApproval']),
    approvalStaleAt: asDateOrNull(json['approvalStaleAt']),
    restaurantApprovedAt: asDateOrNull(json['restaurantApprovedAt']),
    cancelledAt: asDateOrNull(json['cancelledAt']),
    cancellationReason: asString(json['cancellationReason']),
    menu: asMapList(json['menu']).map(MenuCourseDto.fromJson).toList(),
    venue: json['venue'] is Map
        ? (json['venue'] as Map).cast<String, dynamic>()
        : null,
    attendees: asMapList(json['attendees']).map(AttendeeRef.fromJson).toList(),
  );

  /// Unwraps the `{ event: {...} }` detail envelope.
  static EventDto fromDetailEnvelope(Map<String, dynamic> json) =>
      EventDto.fromJson(asMap(json['event']));
}
