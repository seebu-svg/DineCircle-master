import 'user_profile.dart';
import 'restaurant.dart';
import 'dinner.dart';
import 'booking.dart';

/// Lifecycle status of a hosted event (host-side view)
enum HostEventStatus { draft, published, pausedBookings, completed, cancelled }

extension HostEventStatusX on HostEventStatus {
  String get label {
    switch (this) {
      case HostEventStatus.draft:
        return 'Draft';
      case HostEventStatus.published:
        return 'Published';
      case HostEventStatus.pausedBookings:
        return 'Bookings Paused';
      case HostEventStatus.completed:
        return 'Completed';
      case HostEventStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// Status of a guest seat request for a hosted event
enum GuestRequestStatus { pending, approved, rejected, cancelled }

extension GuestRequestStatusX on GuestRequestStatus {
  String get label {
    switch (this) {
      case GuestRequestStatus.pending:
        return 'Pending';
      case GuestRequestStatus.approved:
        return 'Approved';
      case GuestRequestStatus.rejected:
        return 'Rejected';
      case GuestRequestStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// A guest seat request / booking entry on a hosted event
class GuestEntry {
  final String id;
  final UserProfile user;
  final int seats;
  final GuestRequestStatus status;
  final String? message;
  final DateTime requestedAt;
  final CheckInStatus checkIn;
  final DateTime? checkInTime;

  const GuestEntry({
    required this.id,
    required this.user,
    required this.seats,
    required this.status,
    required this.requestedAt,
    this.message,
    this.checkIn = CheckInStatus.notCheckedIn,
    this.checkInTime,
  });

  GuestEntry copyWith({
    GuestRequestStatus? status,
    CheckInStatus? checkIn,
    DateTime? checkInTime,
  }) {
    return GuestEntry(
      id: id,
      user: user,
      seats: seats,
      status: status ?? this.status,
      requestedAt: requestedAt,
      message: message,
      checkIn: checkIn ?? this.checkIn,
      checkInTime: checkInTime ?? this.checkInTime,
    );
  }

  String get requestedLabel {
    final diff = DateTime.now().difference(requestedAt);
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// A collaboration invitation — bidirectional (host ↔ restaurant).
class CollaborationInvite {
  final String id;
  final Restaurant restaurant;
  final String title;
  final String message;
  final DateTime receivedAt;
  final bool isAccepted;

  /// Full lifecycle status: invited | accepted | declined | cancelled | completed.
  final String status;

  /// Who initiated the proposal: 'host' or 'restaurant'.
  final String proposedBy;

  /// Optional linked experience (set after collaboration is completed).
  final String? experienceId;

  /// Restaurant rating (from the server JOIN).
  final double restaurantRating;

  /// Restaurant cuisine tags (from the server JOIN).
  final List<String> restaurantCuisines;

  const CollaborationInvite({
    required this.id,
    required this.restaurant,
    required this.title,
    required this.message,
    required this.receivedAt,
    this.isAccepted = false,
    this.status = 'invited',
    this.proposedBy = 'restaurant',
    this.experienceId,
    this.restaurantRating = 0,
    this.restaurantCuisines = const [],
  });

  CollaborationInvite copyWith({
    bool? isAccepted,
    String? status,
    String? experienceId,
  }) {
    return CollaborationInvite(
      id: id,
      restaurant: restaurant,
      title: title,
      message: message,
      receivedAt: receivedAt,
      isAccepted: isAccepted ?? this.isAccepted,
      status: status ?? this.status,
      proposedBy: proposedBy,
      experienceId: experienceId ?? this.experienceId,
      restaurantRating: restaurantRating,
      restaurantCuisines: restaurantCuisines,
    );
  }

  bool get isIncoming => proposedBy == 'restaurant';
  bool get isOutgoing => proposedBy == 'host';
  bool get isPending => status == 'invited';
  bool get isDeclined => status == 'declined';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';

  String get statusLabel {
    switch (status) {
      case 'invited':
        return 'Pending';
      case 'accepted':
        return 'Active';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  String get receivedLabel {
    final diff = DateTime.now().difference(receivedAt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}

/// A host payout record
class HostPayout {
  final String id;
  final double amount;
  final String method;
  final String status; // paid | processing | pending
  final DateTime date;
  final String period;

  const HostPayout({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    required this.date,
    required this.period,
  });

  String get formattedAmount => 'Rs ${amount.toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostPayout && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Per-event performance metrics for the host analytics
class EventPerformance {
  final Dinner dinner;
  final int views;
  final int bookings;
  final int checkedIn;

  const EventPerformance({
    required this.dinner,
    required this.views,
    required this.bookings,
    required this.checkedIn,
  });

  /// Booking conversion: bookings per 100 event views
  double get conversion => views == 0 ? 0 : (bookings / views) * 100;

  double get grossRevenue => dinner.bookedSeats * dinner.pricePerSeat;
}

/// One per-event analytics row straight from `GET /hosts/:id/performance`.
/// [gross] is server-computed (`seatsBooked * pricePerSeat`) and [coverImage]
/// comes from the event itself, so the analytics screen renders entirely from
/// this list with no `MockData` lookup.
class HostEventStat {
  final String eventId;
  final String title;
  final String? coverImage;
  final int views;
  final int seatsBooked;
  final int bookings;
  final int pending;
  final int checkedIn;
  final double gross;

  const HostEventStat({
    required this.eventId,
    required this.title,
    this.coverImage,
    required this.views,
    required this.seatsBooked,
    required this.bookings,
    required this.pending,
    required this.checkedIn,
    required this.gross,
  });

  double get conversion => views == 0 ? 0 : (bookings / views) * 100;
}

/// A venue the host has held tables at (`GET /hosts/:id/partners`). Wraps a
/// slim [Restaurant] (name/cover/neighborhood only) plus the shared-event count
/// so [_PartnerCard] can render it without any `MockData` lookup.
class HostPartner {
  final Restaurant venue;
  final int eventsTogether;

  const HostPartner({required this.venue, required this.eventsTogether});
}

/// One withdrawal request from the host's simulated wallet ledger.
class Withdrawal {
  final String id;
  final double amount;
  final String method;
  final String status; // requested | processing | completed
  final DateTime date;

  const Withdrawal({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    required this.date,
  });

  String get formattedAmount => 'Rs ${amount.toStringAsFixed(2)}';
}

/// The host's wallet: a server-side simulated ledger. [available] is lifetime
/// net earnings minus every withdrawal recorded to date — no external gateway.
class Wallet {
  final double available;
  final double lifetimeNet;
  final double pendingWithdrawals;
  final List<Withdrawal> withdrawals;

  const Wallet({
    required this.available,
    required this.lifetimeNet,
    required this.pendingWithdrawals,
    required this.withdrawals,
  });
}

/// Headline earnings + activity numbers for the host dashboard
/// (`GET /hosts/:id/summary`).
class HostSummary {
  final double earned;
  final double inTransit;
  final double scheduled;
  final double netTotal;
  final double lifetimeGross;
  final double commissionTotal;
  final int seatsSold;
  final double averageSeatPrice;
  final int hostedCount;
  final int upcomingCount;
  final double averageFillRate;
  final DateTime? nextPayoutDate;
  final double platformCommissionRate;
  final double available;

  const HostSummary({
    required this.earned,
    required this.inTransit,
    required this.scheduled,
    required this.netTotal,
    required this.lifetimeGross,
    required this.commissionTotal,
    required this.seatsSold,
    required this.averageSeatPrice,
    required this.hostedCount,
    required this.upcomingCount,
    required this.averageFillRate,
    this.nextPayoutDate,
    this.platformCommissionRate = 0.10,
    this.available = 0,
  });
}

/// One month of net revenue / seats for the trend chart
/// (`GET /hosts/:id/trend`).
class HostTrendPoint {
  final String label;
  final int seats;
  final double revenue;

  const HostTrendPoint({
    required this.label,
    required this.seats,
    required this.revenue,
  });
}

/// Unified analytics payload from `GET /hosts/:id/analytics?period=`.
/// All values are server-computed — no hardcoded factors or mock data.
class HostAnalytics {
  final int totalEventsHosted;
  final int totalBookings;
  final int totalSeatsSold;
  final double grossRevenue;
  final double hostNetEarnings;
  final double averageSeatFillRate;
  final double averageRating;
  final int upcomingCount;
  final int completedCount;
  final int totalViews;
  final double conversionRate;
  final List<HostEventStat> topPerformingEvents;
  final List<HostTrendPoint> trend;
  final List<HostEventStat> performance;

  const HostAnalytics({
    required this.totalEventsHosted,
    required this.totalBookings,
    required this.totalSeatsSold,
    required this.grossRevenue,
    required this.hostNetEarnings,
    required this.averageSeatFillRate,
    required this.averageRating,
    required this.upcomingCount,
    required this.completedCount,
    required this.totalViews,
    required this.conversionRate,
    required this.topPerformingEvents,
    required this.trend,
    required this.performance,
  });

  double get averageSeatPrice =>
      totalSeatsSold > 0 ? grossRevenue / totalSeatsSold : 0;

  double get commission => grossRevenue - hostNetEarnings;
}

/// A discoverable restaurant partner for collaboration proposals.
class DiscoverablePartner {
  final String id;
  final String name;
  final String? coverImage;
  final String neighborhood;
  final String city;
  final double rating;
  final int reviewCount;
  final List<String> cuisines;

  const DiscoverablePartner({
    required this.id,
    required this.name,
    this.coverImage,
    required this.neighborhood,
    required this.city,
    required this.rating,
    required this.reviewCount,
    required this.cuisines,
  });
}

/// A promotable event with server-side eligibility checks.
class PromotableEvent {
  final String id;
  final String title;
  final String? coverImage;
  final DateTime startAt;
  final int seatsTotal;
  final int seatsBooked;
  final int seatsLeft;
  final double pricePerSeat;
  final String restaurantName;

  const PromotableEvent({
    required this.id,
    required this.title,
    this.coverImage,
    required this.startAt,
    required this.seatsTotal,
    required this.seatsBooked,
    required this.seatsLeft,
    required this.pricePerSeat,
    required this.restaurantName,
  });
}
