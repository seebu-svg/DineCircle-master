import '../utils/venue_time.dart';
import 'user_profile.dart';
import 'restaurant.dart';
import 'host_models.dart';

/// Menu item model
class MenuItem {
  final String id;
  final String name;
  final String description;
  final double price;
  final String? imagePath;
  final List<String> tags;

  const MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.imagePath,
    this.tags = const [],
  });
}

/// Dinner model
class Dinner {
  final String id;
  final String title;
  final String description;
  final Restaurant restaurant;
  final UserProfile host;
  final DateTime dateTime;
  final int totalSeats;
  final int bookedSeats;
  final double pricePerSeat;
  final String? imagePath;
  final List<MenuItem> menu;
  final List<String> tags;
  final bool isPublic;
  final bool isSpecialEvent;
  final String? dressCode;
  final String? ageRestriction;
  final String cancellationPolicy;
  final String category;
  final DateTime? endsAt;
  final List<UserProfile> attendees;
  final HostEventStatus hostStatus;

  /// The venue's own words when it declined, shown verbatim next to a
  /// `Declined by venue` status so the host knows what to fix.
  final String? declineReason;

  /// When a change reopened an already-decided experience. The venue inbox
  /// reads it to tell "first approval" apart from "re-approval after a change".
  final DateTime? approvalStaleAt;

  /// When the experience was soft-cancelled. The row is retained, so guests
  /// and Host Studio can still open it after it leaves the feed.
  final DateTime? cancelledAt;

  /// Whether this venue reserves the right to approve a host's experience
  /// before diners can see it.
  final bool requiresVenueApproval;

  const Dinner({
    required this.id,
    required this.title,
    required this.description,
    required this.restaurant,
    required this.host,
    required this.dateTime,
    required this.totalSeats,
    required this.bookedSeats,
    required this.pricePerSeat,
    this.imagePath,
    this.menu = const [],
    this.tags = const [],
    this.isPublic = true,
    this.isSpecialEvent = false,
    this.dressCode,
    this.ageRestriction,
    this.cancellationPolicy = 'Free cancellation up to 48 hours before',
    this.category = 'Public Dinner',
    this.endsAt,
    this.attendees = const [],
    this.hostStatus = HostEventStatus.published,
    this.declineReason,
    this.approvalStaleAt,
    this.cancelledAt,
    this.requiresVenueApproval = false,
  });

  int get availableSeats => totalSeats - bookedSeats;
  bool get isFull => availableSeats <= 0;

  /// True when the venue has decided once and the host changed the experience
  /// afterwards, so the approval on file no longer describes what is being
  /// published.
  bool get isReapproval => approvalStaleAt != null;

  /// Whether [userId] is this dinner's host. Use the live session id, the old
  /// `isHostedByCurrentUser` getter was a hardcoded stub with no session access.
  bool hostedBy(String? userId) =>
      userId != null && userId.isNotEmpty && host.id == userId;

  String get formattedDate {
    final start = dateTime.toLocal();
    final now = DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    final daysAway = startDay.difference(today).inDays;

    if (daysAway == 0) {
      return 'Today';
    } else if (daysAway == 1) {
      return 'Tomorrow';
    } else if (daysAway > 1 && daysAway < 7) {
      return '$daysAway days';
    } else {
      return formatVenueDate(dateTime);
    }
  }

  String get formattedTime => formatVenueTime(dateTime);

  String get formattedEndTime {
    if (endsAt == null) {
      return formatVenueTime(dateTime.add(const Duration(hours: 3)));
    }
    return formatVenueTime(endsAt!);
  }

  String get formattedLocation {
    return '${restaurant.address}, ${restaurant.city}';
  }

  Dinner copyWith({
    String? id,
    String? title,
    String? description,
    Restaurant? restaurant,
    UserProfile? host,
    DateTime? dateTime,
    int? totalSeats,
    int? bookedSeats,
    double? pricePerSeat,
    String? imagePath,
    List<MenuItem>? menu,
    List<String>? tags,
    bool? isPublic,
    bool? isSpecialEvent,
    String? dressCode,
    String? ageRestriction,
    String? cancellationPolicy,
    String? category,
    DateTime? endsAt,
    List<UserProfile>? attendees,
    HostEventStatus? hostStatus,
    String? declineReason,
    DateTime? approvalStaleAt,
    DateTime? cancelledAt,
    bool? requiresVenueApproval,
  }) {
    return Dinner(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      restaurant: restaurant ?? this.restaurant,
      host: host ?? this.host,
      dateTime: dateTime ?? this.dateTime,
      totalSeats: totalSeats ?? this.totalSeats,
      bookedSeats: bookedSeats ?? this.bookedSeats,
      pricePerSeat: pricePerSeat ?? this.pricePerSeat,
      imagePath: imagePath ?? this.imagePath,
      menu: menu ?? this.menu,
      tags: tags ?? this.tags,
      isPublic: isPublic ?? this.isPublic,
      isSpecialEvent: isSpecialEvent ?? this.isSpecialEvent,
      dressCode: dressCode ?? this.dressCode,
      ageRestriction: ageRestriction ?? this.ageRestriction,
      cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
      category: category ?? this.category,
      endsAt: endsAt ?? this.endsAt,
      attendees: attendees ?? this.attendees,
      hostStatus: hostStatus ?? this.hostStatus,
      declineReason: declineReason ?? this.declineReason,
      approvalStaleAt: approvalStaleAt ?? this.approvalStaleAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      requiresVenueApproval: requiresVenueApproval ?? this.requiresVenueApproval,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Dinner && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
