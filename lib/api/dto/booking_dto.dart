import '../json.dart';

/// A booking row from `/bookings` (the flat host/guest ticket payload).
class BookingDto {
  const BookingDto({
    required this.id,
    required this.eventId,
    this.eventTitle = '',
    this.eventCoverImage,
    this.hostName,
    this.restaurantName,
    this.userId,
    this.seats = 0,
    this.pricePerSeat = 0,
    this.total = 0,
    this.reference = '',
    this.paymentLabel = '',
    this.paymentStatus = '',
    this.clientSecret,
    this.status = 'confirmed',
    this.checkedIn = false,
    this.createdAt,
    this.startAt,
    this.isUpcoming = false,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String? eventCoverImage;
  final String? hostName;
  final String? restaurantName;
  final String? userId;
  final int seats;
  final double pricePerSeat;
  final double total;
  final String reference;
  final String paymentLabel;

  /// Server payment state: '' (legacy), 'paid', 'pending_payment',
  /// 'authorized', 'refunded' or 'failed'.
  final String paymentStatus;

  /// PaymentSheet client secret, only present on the deferred checkout
  /// response for a booking still awaiting the guest's card confirmation.
  final String? clientSecret;
  final String status;
  final bool checkedIn;
  final DateTime? createdAt;
  final DateTime? startAt;
  final bool isUpcoming;

  static BookingDto fromJson(Map<String, dynamic> json) => BookingDto(
    id: asString(json['id']),
    eventId: asString(json['eventId']),
    eventTitle: asString(json['eventTitle']),
    eventCoverImage: asStringOrNull(json['eventCoverImage']),
    hostName: asStringOrNull(json['hostName']),
    restaurantName: asStringOrNull(json['restaurantName']),
    userId: asStringOrNull(json['userId']),
    seats: asInt(json['seats']),
    pricePerSeat: asDouble(json['pricePerSeat']),
    total: asDouble(json['total']),
    reference: asString(json['reference']),
    paymentLabel: asString(json['paymentLabel']),
    paymentStatus: asString(json['paymentStatus']),
    clientSecret: asStringOrNull(json['clientSecret']),
    status: asString(json['status'], 'confirmed'),
    checkedIn: asBool(json['checkedIn']),
    createdAt: asDateOrNull(json['createdAt']),
    startAt: asDateOrNull(json['startAt']),
    isUpcoming: asBool(json['isUpcoming']),
  );
}
