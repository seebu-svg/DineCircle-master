import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/booking.dart';
import '../models/dinner.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';

/// The signed-in user's profile, sourced from the session bootstrap.
///
/// A [Notifier] rather than a plain `Provider` because [UserProfile] equality
/// is id-only: a plain provider would see an edited profile (new name, handle,
/// photo…) as "unchanged" and never rebuild its listeners. Every profile the
/// session publishes is a fresh instance, so identity is the right signal.
final currentUserProvider = NotifierProvider<CurrentUserNotifier, UserProfile?>(
  CurrentUserNotifier.new,
);

class CurrentUserNotifier extends Notifier<UserProfile?> {
  @override
  UserProfile? build() =>
      ref.watch(sessionControllerProvider).valueOrNull?.user;

  @override
  bool updateShouldNotify(UserProfile? previous, UserProfile? next) =>
      !identical(previous, next);
}

/// A public host profile (user + hosted events + reviews + follow state).
final userProfileProvider = FutureProvider.family<HostProfile, String>((
  ref,
  id,
) {
  if (!ref.watch(authReadyProvider)) {
    return HostProfile(
      user: UserProfile(id: id, name: ''),
    );
  }
  return ref.watch(usersRepositoryProvider).profile(id);
});

/// Advisory username check for the profile editor
/// (`GET /users/handle-available`). Keyed by the normalised handle so repeated
/// keystrokes that collapse to the same value reuse one request; an empty
/// key never reaches the server.
final handleAvailabilityProvider =
    FutureProvider.family<HandleAvailability, String>((ref, handle) {
      final value = handle.trim().toLowerCase();
      if (!ref.watch(authReadyProvider) || value.isEmpty) {
        return const HandleAvailability(handle: '', available: true);
      }
      return ref.watch(usersRepositoryProvider).handleAvailability(value);
    });

/// Curated host roster for Explore's Hosts tab. Reads the same `GET /users`
/// roster the People screen uses and keeps only accounts that actually host
/// (`isProfessional`, i.e. their public mode) or have hosted before, ranked by
/// reach then rating. A Personal account is private, so it never appears here
/// even if it holds the host role from an earlier stint.
final discoverHostsProvider = FutureProvider<List<RosterUser>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  final me = ref.watch(currentUserIdProvider);
  final roster = await ref.watch(usersRepositoryProvider).discover(limit: 50);
  final hosts = roster
      .where((row) => row.user.isProfessional || row.user.dinnersHosted > 0)
      .where((row) => row.user.id != me && row.user.name.trim().isNotEmpty)
      .toList();
  hosts.sort((a, b) {
    final byReach = b.user.followers.compareTo(a.user.followers);
    if (byReach != 0) return byReach;
    return b.user.rating.compareTo(a.user.rating);
  });
  return hosts;
});

/// The signed-in user's own tickets (read-only in Phase 2).
final myBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(bookingsRepositoryProvider).getMine(user);
});

/// Whether the signed-in user may review the event with [eventId]: only guests
/// with a completed booking for that event are allowed to post (mirrors the
/// server-side attended-guest check on `POST /events/:id/reviews`).
final canReviewProvider = Provider.family<bool, String>((ref, eventId) {
  final bookings =
      ref.watch(myBookingsProvider).valueOrNull ?? const <Booking>[];
  return bookings.any(
    (b) => b.dinner.id == eventId && b.status == BookingStatus.completed,
  );
});

/// Returns the signed-in user's active booking for [eventId], or `null` if
/// they have none (or only a cancelled/completed one).
final myBookingForEventProvider =
    Provider.family<Booking?, String>((ref, eventId) {
  final bookings =
      ref.watch(myBookingsProvider).valueOrNull ?? const <Booking>[];
  for (final b in bookings) {
    if (b.dinner.id == eventId &&
        b.status != BookingStatus.cancelled &&
        b.status != BookingStatus.completed) {
      return b;
    }
  }
  return null;
});

/// Booking writes (join, cancel, check-in). Each success invalidates
/// [myBookingsProvider] so the list re-reads the authoritative server state.
class BookingsController {
  BookingsController(this._ref);

  final Ref _ref;

  /// Creates a booking via `POST /events/:id/bookings` and returns the server's
  /// [Booking] (real id/reference/total). Throws [ApiException] (seat sold out,
  /// duplicate, audience gate, bad promo) for the checkout screen to surface.
  Future<Booking> join({
    required Dinner dinner,
    required UserProfile user,
    required int seats,
    String? promoCode,
    String paymentLabel = Booking.kDefaultPaymentMethod,
  }) async {
    final booking = await _ref
        .read(bookingsRepositoryProvider)
        .join(
          dinner: dinner,
          user: user,
          seats: seats,
          promoCode: promoCode,
          paymentLabel: paymentLabel,
        );
    _ref.invalidate(myBookingsProvider);
    return booking;
  }

  Future<void> cancel(String bookingId) async {
    await _ref.read(bookingsRepositoryProvider).cancelBooking(bookingId);
    _ref.invalidate(myBookingsProvider);
  }

  /// Re-issues the PaymentSheet secret for the guest's own abandoned
  /// `pending_payment` booking (the `Complete payment` retry).
  Future<String> refreshPaymentSecret(String bookingId) =>
      _ref.read(bookingsRepositoryProvider).refreshPaymentSecret(bookingId);

  /// After PaymentSheet reports success, the server's webhook is the only
  /// authority that may mark a booking `paid`. Poll `GET /bookings` with a
  /// capped backoff for up to 20s; returns true once settled, false when the
  /// hold failed/was swept — and also false on timeout, which is the honest
  /// "we'll notify you" state (the webhook still settles it server-side).
  Future<bool> waitForPaymentSettled(String bookingId, UserProfile user) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    var delay = const Duration(milliseconds: 700);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(delay);
      final rows = await _ref.read(bookingsRepositoryProvider).getMine(user);
      final mine = rows.where((b) => b.id == bookingId);
      if (mine.isEmpty) continue;
      final booking = mine.first;
      if (booking.paymentStatus == 'paid') {
        _ref.invalidate(myBookingsProvider);
        return true;
      }
      if (booking.isPaymentFailed ||
          booking.status == BookingStatus.cancelled) {
        _ref.invalidate(myBookingsProvider);
        return false;
      }
      delay = Duration(
        milliseconds: (delay.inMilliseconds * 2).clamp(700, 3000),
      );
    }
    _ref.invalidate(myBookingsProvider);
    return false;
  }

  Future<void> checkIn(String bookingId) async {
    await _ref.read(bookingsRepositoryProvider).checkIn(bookingId);
    _ref.invalidate(myBookingsProvider);
  }
}

final bookingsControllerProvider = Provider<BookingsController>(
  (ref) => BookingsController(ref),
);
