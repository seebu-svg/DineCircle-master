/// Table reservation model — mirrors the server's `table_reservations` row
/// plus the joined venue name / cover image from `restaurants`.
///
/// Distinct from [Booking] (which is a dinner-event ticket with payment).
/// A reservation is a seat-hold at a restaurant, not a paid event booking.
class TableReservation {
  const TableReservation({
    required this.id,
    required this.restaurantId,
    this.restaurantName,
    this.city,
    this.coverImage,
    this.tableLabel,
    required this.partySize,
    required this.startAt,
    required this.durationMinutes,
    required this.endsAt,
    required this.status,
    required this.reference,
    this.notes = '',
    this.guestName = '',
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String? restaurantName;
  final String? city;
  final String? coverImage;
  final String? tableLabel;
  final int partySize;
  final DateTime startAt;
  final int durationMinutes;
  final DateTime endsAt;
  final ReservationStatus status;
  final String reference;
  final String notes;
  final String guestName;
  final DateTime? createdAt;

  /// True while the venue has not yet confirmed or cancelled.
  bool get isPending => status == ReservationStatus.pending;

  /// True once the venue has confirmed and the table is held.
  bool get isConfirmed => status == ReservationStatus.confirmed;

  /// True once the reservation has been seated (guest arrived).
  bool get isSeated => status == ReservationStatus.seated;

  /// True once the meal is complete.
  bool get isCompleted => status == ReservationStatus.completed;

  /// True once the guest or venue cancelled.
  bool get isCancelled => status == ReservationStatus.cancelled;

  /// True when the guest never showed up.
  bool get isNoShow => status == ReservationStatus.noShow;

  /// Whether the guest can still cancel (only pending/confirmed can).
  bool get isCancellable =>
      status == ReservationStatus.pending ||
      status == ReservationStatus.confirmed;

  /// Human-readable status label for display.
  String get statusLabel {
    switch (status) {
      case ReservationStatus.pending:
        return 'Pending';
      case ReservationStatus.confirmed:
        return 'Confirmed';
      case ReservationStatus.seated:
        return 'Seated';
      case ReservationStatus.completed:
        return 'Completed';
      case ReservationStatus.cancelled:
        return 'Cancelled';
      case ReservationStatus.noShow:
        return 'No-show';
      case ReservationStatus.unknown:
        return 'Unknown';
    }
  }

  /// Formatted start time for display (e.g. "7:30 PM").
  String get formattedTime {
    final hour = startAt.hour == 0 ? 12 : (startAt.hour > 12 ? startAt.hour - 12 : startAt.hour);
    final minute = startAt.minute.toString().padLeft(2, '0');
    final period = startAt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Formatted date for display (e.g. "Mon, Jan 15").
  String get formattedDate {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    // DateTime.weekday is 1=Mon..7=Sun
    final dayName = days[startAt.weekday - 1];
    final monthName = months[startAt.month - 1];
    return '$dayName, $monthName ${startAt.day}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TableReservation && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Reservation lifecycle statuses — mirrors the server's CHECK constraint.
enum ReservationStatus {
  pending,
  confirmed,
  seated,
  completed,
  cancelled,
  noShow,
  unknown;

  /// Parses a wire status string into the enum, returning [unknown] for any
  /// value the client does not recognise (forward-compatible with server
  /// additions).
  static ReservationStatus fromWire(String? value) {
    switch (value?.toLowerCase()) {
      case 'pending':
        return ReservationStatus.pending;
      case 'confirmed':
        return ReservationStatus.confirmed;
      case 'seated':
        return ReservationStatus.seated;
      case 'completed':
        return ReservationStatus.completed;
      case 'cancelled':
        return ReservationStatus.cancelled;
      case 'no_show':
        return ReservationStatus.noShow;
      default:
        return ReservationStatus.unknown;
    }
  }
}
