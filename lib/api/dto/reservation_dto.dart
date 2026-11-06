import '../json.dart';

/// Raw reservation payload from the server's `serializeReservation` envelope.
///
/// The list endpoint (`GET /users/me/reservations`) joins venue name, city,
/// cover image and table label; the create endpoint returns the same shape
/// plus a `restaurantName` field. Both are parsed here.
class ReservationDto {
  const ReservationDto({
    required this.id,
    required this.restaurantId,
    this.branchId,
    this.tableId,
    this.userId,
    this.guestName = '',
    this.guestPhone = '',
    this.partySize = 0,
    this.startAt,
    this.durationMinutes = 90,
    this.endsAt,
    this.status = 'pending',
    this.reference = '',
    this.notes = '',
    this.source = 'customer',
    this.createdAt,
    // Joined fields from the list endpoint.
    this.restaurantName,
    this.city,
    this.coverImage,
    this.tableLabel,
  });

  final String id;
  final String restaurantId;
  final String? branchId;
  final String? tableId;
  final String? userId;
  final String guestName;
  final String guestPhone;
  final int partySize;
  final DateTime? startAt;
  final int durationMinutes;
  final DateTime? endsAt;
  final String status;
  final String reference;
  final String notes;
  final String source;
  final DateTime? createdAt;

  // Joined venue fields (only present on list reads).
  final String? restaurantName;
  final String? city;
  final String? coverImage;
  final String? tableLabel;

  static ReservationDto fromJson(Map<String, dynamic> json) => ReservationDto(
    id: asString(json['id']),
    restaurantId: asString(json['restaurantId']),
    branchId: asStringOrNull(json['branchId']),
    tableId: asStringOrNull(json['tableId']),
    userId: asStringOrNull(json['userId']),
    guestName: asString(json['guestName']),
    guestPhone: asString(json['guestPhone']),
    partySize: asInt(json['partySize']),
    startAt: asDateOrNull(json['startAt']),
    durationMinutes: asInt(json['durationMinutes']),
    endsAt: asDateOrNull(json['endsAt']),
    status: asString(json['status'], 'pending'),
    reference: asString(json['reference']),
    notes: asString(json['notes']),
    source: asString(json['source'], 'customer'),
    createdAt: asDateOrNull(json['createdAt']),
    restaurantName: asStringOrNull(json['restaurantName']),
    city: asStringOrNull(json['city']),
    coverImage: asStringOrNull(json['coverImage']),
    tableLabel: asStringOrNull(json['tableLabel']),
  );
}

/// One availability slot returned by `GET /restaurants/:id/availability`.
///
/// Mirrors the server's `SlotOption` shape: a 30-minute window with a flag
/// for whether the party can actually book it (capacity + table fit + future).
class AvailabilitySlotDto {
  const AvailabilitySlotDto({
    required this.startAt,
    required this.endAt,
    required this.available,
    required this.seatsLeft,
  });

  final DateTime startAt;
  final DateTime endAt;
  final bool available;
  final int seatsLeft;

  static AvailabilitySlotDto fromJson(Map<String, dynamic> json) =>
      AvailabilitySlotDto(
        startAt: asDateOrNull(json['startAt']) ?? DateTime.now(),
        endAt: asDateOrNull(json['endAt']) ?? DateTime.now(),
        available: asBool(json['available']),
        seatsLeft: asInt(json['seatsLeft']),
      );
}

/// Full availability response for one service day.
class AvailabilityDto {
  const AvailabilityDto({
    required this.date,
    required this.timeZone,
    required this.slots,
    required this.capacity,
    required this.configuredHours,
  });

  final String date;
  final String timeZone;
  final List<AvailabilitySlotDto> slots;
  final int capacity;
  final bool configuredHours;

  static AvailabilityDto fromJson(Map<String, dynamic> json) => AvailabilityDto(
    date: asString(json['date']),
    timeZone: asString(json['timeZone']),
    slots: asMapList(json['slots']).map(AvailabilitySlotDto.fromJson).toList(),
    capacity: asInt(json['capacity']),
    configuredHours: asBool(json['configuredHours']),
  );
}
