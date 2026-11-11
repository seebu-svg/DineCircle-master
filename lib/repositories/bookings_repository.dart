import '../models/booking.dart';
import '../models/dinner.dart';
import '../models/user_profile.dart';
import '../api/api_client.dart';
import '../api/dto/booking_dto.dart';
import '../api/json.dart';
import '../api/mappers/mappers.dart';

/// Read access to the signed-in user's tickets plus the booking writes the
/// app performs. Payment capture itself stays simulated until Phase 4
/// (Stripe); the server is already the source of truth for the total.
abstract class BookingsRepository {
  Future<List<Booking>> getMine(UserProfile currentUser);

  /// Joins an event (`POST /events/:id/bookings`). The server recomputes the
  /// total (and any promo discount), the returned [Booking] carries that
  /// authoritative amount. [paymentLabel] records how the guest intends to
  /// settle; DineCircle takes no payment in-app, so it defaults to paying the
  /// venue on arrival.
  Future<Booking> join({
    required Dinner dinner,
    required UserProfile user,
    required int seats,
    String? promoCode,
    String paymentLabel = Booking.kDefaultPaymentMethod,
    String? guestName,
    String? guestEmail,
    String? guestPhone,
  });

  /// Cancels one of the caller's bookings; seats are released server-side.
  Future<void> cancelBooking(String bookingId);

  /// Re-issues the PaymentSheet client secret for the caller's own still
  /// `pending_payment` booking, the `Complete payment` retry path after an
  /// abandoned checkout. Throws [ApiException] (409) once settled/swept.
  Future<String> refreshPaymentSecret(String bookingId);

  /// Marks a ticket checked-in (guest or its host may call this).
  Future<void> checkIn(String bookingId);

  /// A host's guest list for one of their events (`GET /bookings?eventId=`).
  Future<List<Booking>> guestsFor(String eventId, UserProfile currentUser);

  /// The event host approves a pending seat request (`POST /bookings/:id/approve`)
  ///, the booking is confirmed and the hold is captured.
  Future<Booking> approveRequest(String bookingId, UserProfile currentUser);

  /// The event host declines a pending seat request (`POST /bookings/:id/decline`)
  ///, it is cancelled/refunded and the held seat is released.
  Future<Booking> declineRequest(String bookingId, UserProfile currentUser);
}

class ApiBookingsRepository implements BookingsRepository {
  ApiBookingsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Booking>> getMine(UserProfile currentUser) async {
    final body = await _client.getJson('/bookings');
    return asMapList(asMap(body)['bookings'])
        .map((m) => Mappers.bookingFromDto(BookingDto.fromJson(m), currentUser))
        .toList();
  }

  @override
  Future<Booking> join({
    required Dinner dinner,
    required UserProfile user,
    required int seats,
    String? promoCode,
    String paymentLabel = Booking.kDefaultPaymentMethod,
    String? guestName,
    String? guestEmail,
    String? guestPhone,
  }) async {
    final body = await _client.postJson(
      '/events/${dinner.id}/bookings',
      body: {
        'seats': seats,
        'paymentLabel': paymentLabel,
        if (promoCode != null && promoCode.trim().isNotEmpty)
          'promoCode': promoCode.trim().toUpperCase(),
        // Real contact the host can act on; omitted rather than invented when
        // the guest left a field blank.
        if (guestName != null && guestName.trim().isNotEmpty)
          'guestName': guestName.trim(),
        if (guestEmail != null && guestEmail.trim().isNotEmpty)
          'guestEmail': guestEmail.trim(),
        if (guestPhone != null && guestPhone.trim().isNotEmpty)
          'guestPhone': guestPhone.trim(),
      },
    );
    final booking = asMap(asMap(body)['booking']);
    return Mappers.bookingFromJoin(
      BookingDto.fromJson(booking),
      dinner: dinner,
      user: user,
      discount: asDouble(booking['discount']),
    );
  }

  @override
  Future<void> cancelBooking(String bookingId) =>
      _client.postJson('/bookings/$bookingId/cancel');

  @override
  Future<String> refreshPaymentSecret(String bookingId) async {
    final body = await _client.postJson('/bookings/$bookingId/refresh-payment');
    return asString(asMap(body)['clientSecret']);
  }

  @override
  Future<void> checkIn(String bookingId) =>
      _client.postJson('/bookings/$bookingId/checkin');

  @override
  Future<List<Booking>> guestsFor(
    String eventId,
    UserProfile currentUser,
  ) async {
    final body = await _client.getJson(
      '/bookings',
      query: {'eventId': eventId},
    );
    return asMapList(asMap(body)['bookings'])
        .map((m) => Mappers.bookingFromDto(BookingDto.fromJson(m), currentUser))
        .toList();
  }

  /// Reads the single serialized booking the server returns from an
  /// approve/decline call and rebuilds a [Booking] for the guest list.
  Booking _bookingFromAck(dynamic body, UserProfile currentUser) {
    final row = asMap(asMap(body)['booking']);
    return Mappers.bookingFromDto(BookingDto.fromJson(row), currentUser);
  }

  @override
  Future<Booking> approveRequest(
    String bookingId,
    UserProfile currentUser,
  ) async {
    final body = await _client.postJson('/bookings/$bookingId/approve');
    return _bookingFromAck(body, currentUser);
  }

  @override
  Future<Booking> declineRequest(
    String bookingId,
    UserProfile currentUser,
  ) async {
    final body = await _client.postJson('/bookings/$bookingId/decline');
    return _bookingFromAck(body, currentUser);
  }
}
