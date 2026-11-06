import 'user_profile.dart';
import 'dinner.dart';

/// The source kind of a notification — drives the leading icon.
enum NotificationItemKind { activity, reminder, offer }

/// Notification type
enum NotificationType {
  bookingConfirmed,
  bookingCancelled,
  newAttendee,
  dinnerReminder,
  message,
  hostEarnings,
  followRequest,
  specialOffer,
  review,
}

/// Notification item model
class NotificationItem {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final UserProfile? user;
  final Dinner? dinner;
  final String? actionUrl;
  final NotificationItemKind itemKind;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.user,
    this.dinner,
    this.actionUrl,
    this.itemKind = NotificationItemKind.activity,
  });

  String get typeIcon {
    switch (type) {
      case NotificationType.bookingConfirmed:
        return 'check_circle';
      case NotificationType.bookingCancelled:
        return 'cancel';
      case NotificationType.newAttendee:
        return 'person_add';
      case NotificationType.dinnerReminder:
        return 'event';
      case NotificationType.message:
        return 'message';
      case NotificationType.hostEarnings:
        return 'payments';
      case NotificationType.followRequest:
        return 'person_add';
      case NotificationType.specialOffer:
        return 'local_offer';
      case NotificationType.review:
        return 'star';
    }
  }

  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
