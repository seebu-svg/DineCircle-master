import '../../models/booking.dart';
import '../../models/dinner.dart';
import '../../models/host_models.dart';
import '../../models/message.dart';
import '../../models/notification_item.dart';
import '../../models/offer.dart';
import '../../models/restaurant.dart';
import '../../models/review.dart';
import '../../models/table_reservation.dart';
import '../../models/user_profile.dart';
import '../dto/booking_dto.dart';
import '../dto/event_dto.dart';
import '../dto/offer_dto.dart';
import '../dto/reservation_dto.dart';
import '../dto/restaurant_dto.dart';
import '../dto/review_dto.dart';
import '../dto/user_dto.dart';
import '../json.dart';

/// Pure DTO → domain-model conversions.
///
/// The list feed only embeds a slim host/venue reference, so these mappers
/// deliberately fill required-but-absent fields with safe defaults (null
/// coordinates, empty strings). The detail endpoints supply the full
/// venue/menu/attendees — including real lat/lng — which these same functions
/// consume when present.
class Mappers {
  Mappers._();

  static const Map<String, String> _typeLabels = {
    'dinner': 'Public Dinner',
    'tasting': 'Tasting',
    'supperClub': 'Supper Club',
    'brunch': 'Brunch',
    'workshop': 'Food Experience',
    'festival': 'Festival',
  };

  static String typeLabel(String type) => _typeLabels[type] ?? 'Public Dinner';

  // ── Restaurant ──────────────────────────────────────────────────────────────

  static Restaurant restaurantFromDto(RestaurantDto d) => Restaurant(
    id: d.id,
    name: d.name,
    description: d.about,
    cuisine: d.cuisines.isNotEmpty ? d.cuisines.join(', ') : '',
    address: d.address.isNotEmpty ? d.address : d.neighborhood,
    neighborhood: d.neighborhood,
    city: d.city.isEmpty ? null : d.city,
    latitude: d.latitude,
    longitude: d.longitude,
    imagePath: d.coverImage,
    gallery: d.gallery,
    logoPath: d.logoPath,
    phoneNumber: d.phoneNumber,
    website: d.website,
    email: d.email,
    instagram: d.instagram,
    facebook: d.facebook,
    twitter: d.twitter,
    rating: d.rating,
    reviewCount: d.reviewCount,
    priceRange: d.priceRange,
    tags: d.tags,
    isPartner: d.isPartner,
    partnershipStatus: d.partnershipStatus,
    isFollowing: d.isFollowing,
    distanceKm: d.distanceKm,
    openingHours: d.openingHours,
    amenities: d.amenities,
  );

  static Restaurant _restaurantFromVenueRef(VenueRef v) => Restaurant(
    id: v.id,
    name: v.name,
    description: '',
    cuisine: '',
    address: v.neighborhood ?? '',
    latitude: v.latitude,
    longitude: v.longitude,
  );

  /// A partial [Restaurant] built from the slim venue references the host
  /// surfaces return (partner venues, invite senders). The host UI only reads
  /// name / cover / neighborhood, so the remaining required fields fall back to
  /// safe defaults, exactly like [_restaurantFromVenueRef].
  static Restaurant slimRestaurant({
    required String id,
    required String name,
    String? coverImage,
    String? neighborhood,
  }) => Restaurant(
    id: id,
    name: name,
    description: '',
    cuisine: neighborhood ?? '',
    address: neighborhood ?? '',
    imagePath: (coverImage == null || coverImage.isEmpty) ? null : coverImage,
  );

  // ── User ────────────────────────────────────────────────────────────────────

  static UserProfile userFromDto(UserDto d) => UserProfile(
    id: d.id,
    name: d.name,
    handle: d.handle,
    bio: d.bio.isEmpty ? null : d.bio,
    avatarPath: d.avatarUrl,
    dinnersHosted: d.dinnersHosted,
    dinnersAttended: d.dinnersJoined,
    followers: d.followers,
    following: d.following,
    rating: d.rating,
    reviewCount: d.reviewCount,
    isRestaurantPartner: d.isPartnerAdmin,
    isVerified: d.isVerified,
    isInfluencer: d.isInfluencer,
    interests: d.tastes,
    location: d.city.isEmpty ? null : d.city,
    socialLinks: d.instagram.isEmpty
        ? const []
        : [SocialLink(platform: SocialPlatform.instagram, handle: d.instagram)],
    role: d.role,
    accountType: d.accountType,
    professionalSince: d.professionalSince,
    joinedYear: d.joinedYear,
    // Account & Settings (P1) — ride the `/auth/me` payload so the Settings
    // screens hydrate straight off the session without a second round-trip.
    email: d.email,
    homeArea: d.homeArea,
    dietary: d.dietary,
    allergies: d.allergies,
    showFollowList: d.showFollowList,
    showActivity: d.showActivity,
    dmFromFollowersOnly: d.dmFromFollowersOnly,
    allowTagging: d.allowTagging,
  );

  static UserProfile _userFromHostRef(HostRef? h, String? fallbackId) {
    if (h != null) {
      // Tier flags ride the event payload so verified badges and the
      // influencer filter render straight off lists and detail screens.
      return UserProfile(
        id: h.id,
        name: h.name,
        avatarPath: h.avatarUrl,
        isVerified: h.isVerified,
        isInfluencer: h.isInfluencer,
        // Whoever is attached to a published event is presenting a public
        // host profile, so this partial stub is Professional by definition
        // (the full profile is still fetched separately by its own screen).
        accountType: 'professional',
      );
    }
    return UserProfile(id: fallbackId ?? '', name: 'DineCircle Host');
  }

  static UserProfile _userFromAttendeeRef(AttendeeRef a) =>
      UserProfile(id: a.id, name: a.name, avatarPath: a.avatarUrl);

  static UserProfile _userFromReviewAuthor(ReviewAuthorDto a) => UserProfile(
    id: a.id ?? '',
    name: a.name.isEmpty ? 'A diner' : a.name,
    avatarPath: a.avatarUrl,
  );

  // ── Menu ────────────────────────────────────────────────────────────────────

  static MenuItem _menuItemFromCourse(MenuCourseDto c) => MenuItem(
    id: c.id,
    name: c.name,
    description: c.pairing != null && c.pairing!.isNotEmpty
        ? '${c.description} • ${c.pairing}'.trim()
        : c.description,
    price: 0,
    tags: c.isSignature ? const ['Signature'] : const [],
  );

  // ── Dinner ──────────────────────────────────────────────────────────────────

  /// Maps an [EventDto] (list or detail) to the rich [Dinner] the UI renders.
  /// `venue` on detail fully replaces the slim reference; menu/attendees are
  /// only populated for detail payloads.
  static Dinner dinnerFromEvent(EventDto e) {
    final restaurant = e.venue != null
        ? restaurantFromDto(RestaurantDto.fromJson(e.venue!))
        : (e.restaurant != null
              ? _restaurantFromVenueRef(e.restaurant!)
              : Restaurant(
                  id: e.restaurantId ?? '',
                  name: 'Venue',
                  description: '',
                  cuisine: '',
                  address: '',
                ));

    final start = e.startAt ?? DateTime.now();
    return Dinner(
      id: e.id,
      title: e.title,
      description: e.description.isNotEmpty ? e.description : e.tagline,
      restaurant: restaurant,
      host: _userFromHostRef(e.host, e.hostId),
      dateTime: start,
      totalSeats: e.seatsTotal,
      bookedSeats: e.seatsBooked,
      pricePerSeat: e.pricePerSeat,
      imagePath: e.coverImage,
      menu: e.menu.map(_menuItemFromCourse).toList(),
      tags: e.tags,
      isPublic: e.audience == 'public',
      isSpecialEvent: e.isFeatured,
      dressCode: e.dressCode.isEmpty ? null : e.dressCode,
      cancellationPolicy: e.cancellation.isEmpty
          ? 'Free cancellation up to 48 hours before'
          : e.cancellation,
      category: typeLabel(e.type),
      endsAt: e.durationMinutes > 0
          ? start.add(Duration(minutes: e.durationMinutes))
          : null,
      attendees: e.attendees.map(_userFromAttendeeRef).toList(),
      hostStatus: _hostStatusFromEventStatus(e.status),
    );
  }

  /// Server lifecycle status → host-side view status. Drafts drive the Host
  /// Studio drafts section; everything the public sees collapses to published.
  static HostEventStatus _hostStatusFromEventStatus(String status) {
    switch (status) {
      case 'draft':
        return HostEventStatus.draft;
      case 'completed':
        return HostEventStatus.completed;
      case 'cancelled':
      case 'declined':
        return HostEventStatus.cancelled;
      default:
        return HostEventStatus.published;
    }
  }

  /// Maps a slim `hostedUpcoming` venue-event entry (user profile / restaurant
  /// detail) to a lightweight [Dinner]. Host/restaurant are supplied by the
  /// caller since those payloads omit them.
  static Dinner dinnerFromVenueEvent(
    VenueEventDto e, {
    UserProfile? host,
    Restaurant? restaurant,
  }) {
    return Dinner(
      id: e.id,
      title: e.title,
      description: e.tagline,
      restaurant:
          restaurant ??
          Restaurant(
            id: '',
            name: '',
            description: '',
            cuisine: '',
            address: '',
          ),
      host: host ?? UserProfile(id: '', name: e.hostName ?? 'Host'),
      dateTime: e.startAt ?? DateTime.now(),
      totalSeats: e.seatsTotal,
      bookedSeats: e.seatsBooked,
      pricePerSeat: e.pricePerSeat,
      imagePath: e.coverImage,
      category: typeLabel(e.type),
    );
  }

  // ── Review ──────────────────────────────────────────────────────────────────

  static Review reviewFromDto(ReviewDto d) => Review(
    id: d.id,
    reviewer: _userFromReviewAuthor(d.author),
    rating: d.rating,
    comment: d.text,
    createdAt: d.createdAt ?? DateTime.now(),
  );

  // ── Booking ─────────────────────────────────────────────────────────────────

  static BookingStatus _bookingStatus(String status) => switch (status) {
    'pending' => BookingStatus.pending,
    'cancelled' => BookingStatus.cancelled,
    'completed' => BookingStatus.completed,
    _ => BookingStatus.confirmed,
  };

  static Booking bookingFromDto(BookingDto d, UserProfile user) {
    final dinner = Dinner(
      id: d.eventId,
      title: d.eventTitle,
      description: '',
      restaurant: Restaurant(
        id: '',
        name: d.restaurantName ?? '',
        description: '',
        cuisine: '',
        address: '',
      ),
      host: UserProfile(id: '', name: d.hostName ?? 'Host'),
      dateTime: d.startAt ?? DateTime.now(),
      totalSeats: 0,
      bookedSeats: 0,
      pricePerSeat: d.pricePerSeat,
      imagePath: d.eventCoverImage,
    );

    return Booking(
      id: d.id,
      dinner: dinner,
      user: user,
      seats: d.seats,
      subtotal: d.pricePerSeat * d.seats,
      serviceFee: 0,
      totalAmount: d.total,
      status: _bookingStatus(d.status),
      createdAt: d.createdAt ?? DateTime.now(),
      qrCode: d.reference,
      guestName: user.name,
      // The server stores an empty label while a gateway owns the payment —
      // the settlement webhook writes the real brand/last4. Inventing a card
      // here would show a method the guest never used, so the empty value is
      // passed through and surfaces as "Not recorded".
      paymentMethod: d.paymentLabel,
      paymentStatus: d.paymentStatus,
      checkInStatus: d.checkedIn
          ? CheckInStatus.checkedIn
          : (d.isUpcoming ? CheckInStatus.notCheckedIn : CheckInStatus.expired),
    );
  }

  /// Builds the [Booking] shown right after checkout from the server's create
  /// response. Unlike [bookingFromDto] (which reconstructs a slim Dinner from
  /// the flat ticket row), here we already hold the live [dinner] the user just
  /// booked, so we reuse it and take the authoritative `total`/`reference`.
  static Booking bookingFromJoin(
    BookingDto d, {
    required Dinner dinner,
    required UserProfile user,
    required double discount,
  }) {
    return Booking(
      id: d.id,
      dinner: dinner,
      user: user,
      seats: d.seats,
      subtotal: dinner.pricePerSeat * d.seats,
      serviceFee: 0,
      discount: discount,
      totalAmount: d.total,
      status: _bookingStatus(d.status),
      createdAt: d.createdAt ?? DateTime.now(),
      qrCode: d.reference,
      guestName: user.name,
      // The server stores an empty label while a gateway owns the payment —
      // the settlement webhook writes the real brand/last4. Inventing a card
      // here would show a method the guest never used, so the empty value is
      // passed through and surfaces as "Not recorded".
      paymentMethod: d.paymentLabel,
      paymentStatus: d.paymentStatus,
      clientSecret: d.clientSecret,
      checkInStatus: CheckInStatus.notCheckedIn,
    );
  }

  // ── Saved / activity / chat ────────────────────────────────────────────────

  /// A slim `GET /me/saved` row reuses the venue-event shape.
  static Dinner dinnerFromSavedRow(Map<String, dynamic> row) =>
      dinnerFromVenueEvent(VenueEventDto.fromJson(row));

  static NotificationType _notificationKind(String kind) => switch (kind) {
    'booking' => NotificationType.bookingConfirmed,
    'cancel' => NotificationType.bookingCancelled,
    'attendee' => NotificationType.newAttendee,
    'reminder' => NotificationType.dinnerReminder,
    'message' => NotificationType.message,
    'payout' => NotificationType.hostEarnings,
    'follow' => NotificationType.followRequest,
    'review' => NotificationType.review,
    _ => NotificationType.specialOffer,
  };

  /// Maps a `GET /activity` row to a [NotificationItem]. The optional `actor`
  /// reference becomes the notification's user avatar.
  static NotificationItem notificationFromActivityRow(
    Map<String, dynamic> row,
  ) {
    final actor = asMap(row['actor']);
    final user = actor.isEmpty
        ? null
        : UserProfile(
            id: asString(actor['id']),
            name: asString(actor['name'], 'Someone'),
            avatarPath: asStringOrNull(actor['avatarUrl']),
          );
    return NotificationItem(
      id: asString(row['id']),
      type: _notificationKind(asString(row['kind'])),
      title: asString(row['title']),
      message: asString(row['body']),
      timestamp: asDateOrNull(row['createdAt']) ?? DateTime.now(),
      isRead: !asBool(row['isUnread']),
      user: user,
    );
  }

  /// Maps a `GET /users/me/notifications` row to a [NotificationItem].
  /// The unified endpoint tags each item with `kind` = 'activity' | 'reminder'
  /// | 'offer' to drive the leading icon in the UI.
  static NotificationItem notificationFromUnifiedRow(
    Map<String, dynamic> row,
  ) {
    final actor = asMap(row['actor']);
    final user = actor.isEmpty
        ? null
        : UserProfile(
            id: asString(actor['id']),
            name: asString(actor['name'], 'Someone'),
            avatarPath: asStringOrNull(actor['avatarUrl']),
          );
    final kindStr = asString(row['kind']);
    final itemKind = switch (kindStr) {
      'reminder' => NotificationItemKind.reminder,
      'offer' => NotificationItemKind.offer,
      _ => NotificationItemKind.activity,
    };
    return NotificationItem(
      id: asString(row['id']),
      type: _notificationKind(kindStr),
      title: asString(row['title']),
      message: asString(row['body']),
      timestamp: asDateOrNull(row['createdAt']) ?? DateTime.now(),
      isRead: asBool(row['isRead']),
      user: user,
      itemKind: itemKind,
    );
  }

  /// Maps a chat message row (`/events/:id/messages`) to a [Message]. The
  /// sender is reconstructed from the embedded `author` reference.
  static Message messageFromRow(Map<String, dynamic> row) {
    final author = asMap(row['author']);
    final sender = UserProfile(
      id: asString(row['authorId']),
      name: author.isEmpty ? 'You' : asString(author['name'], 'Member'),
      avatarPath: asStringOrNull(author['avatarUrl']),
    );
    return Message(
      id: asString(row['id']),
      content: asString(row['text']),
      sender: sender,
      timestamp: asDateOrNull(row['sentAt']) ?? DateTime.now(),
    );
  }

  // ── Offers (Deals & Offers discovery category) ─────────────────────────

  static Offer offerFromDto(OfferDto d) => Offer(
    id: d.id,
    name: d.name,
    description: d.description,
    restaurantId: d.restaurantId,
    restaurantName: d.restaurantName,
    city: d.city,
    pricePerGuest: d.pricePerGuest,
    minGuests: d.minGuests,
    coverImage: d.coverImage,
    tags: d.tags,
    kind: d.kind,
  );

  static PromoCode promoFromDto(PromoCodeDto d) =>
      PromoCode(code: d.code, discountPct: d.discountPct);

  static OfferFeed offerFeedFromDto(OfferFeedDto d) => OfferFeed(
    offers: d.offers.map(offerFromDto).toList(),
    promos: d.promos.map(promoFromDto).toList(),
  );

  // ── Table Reservations ─────────────────────────────────────────────────────

  static TableReservation reservationFromDto(ReservationDto d) => TableReservation(
    id: d.id,
    restaurantId: d.restaurantId,
    restaurantName: d.restaurantName,
    city: d.city,
    coverImage: d.coverImage,
    tableLabel: d.tableLabel,
    partySize: d.partySize,
    startAt: d.startAt ?? DateTime.now(),
    durationMinutes: d.durationMinutes,
    endsAt: d.endsAt ?? DateTime.now(),
    status: ReservationStatus.fromWire(d.status),
    reference: d.reference,
    notes: d.notes,
    guestName: d.guestName,
    createdAt: d.createdAt,
  );

  static AvailabilitySlotDto availabilitySlotFromDto(Map<String, dynamic> json) =>
      AvailabilitySlotDto.fromJson(json);

  static AvailabilityDto availabilityFromDto(Map<String, dynamic> json) =>
      AvailabilityDto.fromJson(json);
}
