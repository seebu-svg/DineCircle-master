import '../api/api_client.dart';
import '../api/dto/reservation_dto.dart';
import '../api/json.dart';
import '../api/mappers/mappers.dart';
import '../models/table_reservation.dart';

/// Read/write access to the signed-in diner's table reservations.
///
/// The server's reservation engine lives in `server/src/reservations.ts`;
/// this repository calls the customer-facing routes mounted at
/// `server/src/routes/reservations.ts`.
///
/// Declared as an interface so widget tests can inject a fake.
abstract class ReservationsRepository {
  /// The diner's own reservations (`GET /users/me/reservations`).
  Future<List<TableReservation>> mine({String? status});

  /// Availability for one service day at a venue
  /// (`GET /restaurants/:id/availability`).
  Future<AvailabilityDto> availability({
    required String restaurantId,
    required DateTime date,
    required int partySize,
    String? branchId,
  });

  /// Books a table (`POST /restaurants/:id/reservations`).
  Future<TableReservation> create({
    required String restaurantId,
    required DateTime startAt,
    required int partySize,
    String? tableId,
    String? branchId,
    String notes,
  });

  /// Cancels the diner's own reservation (`POST /reservations/:id/cancel`).
  Future<void> cancel(String reservationId);
}

class ApiReservationsRepository implements ReservationsRepository {
  ApiReservationsRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<TableReservation>> mine({String? status}) async {
    final body = await _client.getJson(
      '/users/me/reservations',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    // The server wraps list routes in the `{ data: { ... }, meta }` envelope
    // (see server/src/api.ts `list()`), so unwrap before reading the key.
    final payload = asMap(asMap(body)['data']);
    return asMapList(payload['reservations'])
        .map((m) => Mappers.reservationFromDto(ReservationDto.fromJson(m)))
        .toList();
  }

  @override
  Future<AvailabilityDto> availability({
    required String restaurantId,
    required DateTime date,
    required int partySize,
    String? branchId,
  }) async {
    final body = await _client.getJson(
      '/restaurants/$restaurantId/availability',
      query: {
        'date': date.toIso8601String().split('T').first,
        'partySize': partySize.toString(),
        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
      },
    );
    return AvailabilityDto.fromJson(asMap(asMap(body)['data']));
  }

  @override
  Future<TableReservation> create({
    required String restaurantId,
    required DateTime startAt,
    required int partySize,
    String? tableId,
    String? branchId,
    String notes = '',
  }) async {
    final body = await _client.postJson(
      '/restaurants/$restaurantId/reservations',
      body: {
        'startAt': startAt.toUtc().toIso8601String(),
        'partySize': partySize,
        if (tableId != null && tableId.isNotEmpty) 'tableId': tableId,
        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    final data = asMap(asMap(body)['data']);
    return Mappers.reservationFromDto(
      ReservationDto.fromJson(asMap(data['reservation'])),
    );
  }

  @override
  Future<void> cancel(String reservationId) async {
    await _client.postJson('/reservations/$reservationId/cancel');
  }
}
