import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto/reservation_dto.dart';
import '../models/table_reservation.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';

/// Query key for availability lookups. Value type so the `family` recomputes
/// only when the inputs actually change.
class AvailabilityQuery {
  const AvailabilityQuery({
    required this.restaurantId,
    required this.date,
    required this.partySize,
    this.branchId,
  });

  final String restaurantId;
  final DateTime date;
  final int partySize;
  final String? branchId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvailabilityQuery &&
          other.restaurantId == restaurantId &&
          _sameDate(other.date, date) &&
          other.partySize == partySize &&
          other.branchId == branchId;

  @override
  int get hashCode => Object.hash(
    restaurantId,
    date.year,
    date.month,
    date.day,
    partySize,
    branchId,
  );

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Availability for one service day at a venue
/// (`GET /restaurants/:id/availability`).
final availabilityProvider =
    FutureProvider.family<AvailabilityDto, AvailabilityQuery>(
  (ref, query) {
    if (!ref.watch(authReadyProvider)) {
      return AvailabilityDto(
        date: query.date.toIso8601String().split('T').first,
        timeZone: 'UTC',
        slots: const [],
        capacity: 0,
        configuredHours: false,
      );
    }
    return ref.watch(reservationsRepositoryProvider).availability(
      restaurantId: query.restaurantId,
      date: query.date,
      partySize: query.partySize,
      branchId: query.branchId,
    );
  },
);

/// The signed-in diner's own reservations (`GET /users/me/reservations`).
final myReservationsProvider = FutureProvider<List<TableReservation>>((ref) {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref.watch(reservationsRepositoryProvider).mine();
});

/// Write operations for reservations. Each success invalidates the relevant
/// read providers so the UI reflects the change without a manual refresh.
class ReservationsController {
  ReservationsController(this._ref);

  final Ref _ref;

  /// Books a table at a restaurant.
  Future<TableReservation> create({
    required String restaurantId,
    required DateTime startAt,
    required int partySize,
    String? tableId,
    String? branchId,
    String notes = '',
  }) async {
    final reservation = await _ref
        .read(reservationsRepositoryProvider)
        .create(
          restaurantId: restaurantId,
          startAt: startAt,
          partySize: partySize,
          tableId: tableId,
          branchId: branchId,
          notes: notes,
        );
    _ref.invalidate(myReservationsProvider);
    return reservation;
  }

  /// Cancels the diner's own reservation.
  Future<void> cancel(String reservationId) async {
    await _ref.read(reservationsRepositoryProvider).cancel(reservationId);
    _ref.invalidate(myReservationsProvider);
  }
}

final reservationsControllerProvider = Provider<ReservationsController>(
  (ref) => ReservationsController(ref),
);
