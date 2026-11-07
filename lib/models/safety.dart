/// P2 Safety & Trust models: blocks, reports and feedback tickets.
///
/// Everything here is parsed straight from the Express payloads (`json.dart`
/// coercion), so a partially-unknown status never crashes a screen, unknown
/// wire values fall back to the safest open state rather than throwing.
library;

import '../api/json.dart';

enum ReportTargetType {
  user('user', 'Profile'),
  event('event', 'Event'),
  review('review', 'Review'),
  message('message', 'Message');

  const ReportTargetType(this.wire, this.label);
  final String wire;
  final String label;

  static ReportTargetType? tryParse(Object? value) {
    final s = value is String ? value : null;
    return values.where((e) => e.wire == s).firstOrNull;
  }
}

enum ReportReason {
  harassment('harassment', 'Harassment or bullying'),
  spam('spam', 'Spam or a scam'),
  inappropriateContent('inappropriate_content', 'Inappropriate content'),
  impersonation('impersonation', 'Fake profile or impersonation'),
  unsafeExperience('unsafe_experience', 'Unsafe dining experience'),
  misleadingEventInfo('misleading_event_info', 'Misleading event information'),
  other('other', 'Something else');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;

  static ReportReason? tryParse(Object? value) {
    final s = value is String ? value : null;
    return values.where((e) => e.wire == s).firstOrNull;
  }
}

enum ReportStatus {
  pending('pending', 'Pending'),
  reviewing('reviewing', 'Under review'),
  resolved('resolved', 'Resolved'),
  dismissed('dismissed', 'Dismissed');

  const ReportStatus(this.wire, this.label);
  final String wire;
  final String label;

  static ReportStatus tryParseOrPending(Object? value) {
    final s = value is String ? value : null;
    return values.where((e) => e.wire == s).firstOrNull ?? ReportStatus.pending;
  }
}

class ReportItem {
  const ReportItem({
    required this.id,
    required this.reference,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  final String id;

  /// User-facing confirmation handle, e.g. `RP-7K3MQF`.
  final String reference;
  final ReportTargetType targetType;
  final String targetId;
  final ReportReason reason;
  final String description;
  final ReportStatus status;
  final DateTime? createdAt;

  factory ReportItem.fromMap(Map<String, dynamic> map) => ReportItem(
    id: asString(map['id']),
    reference: asString(map['reference']),
    targetType:
        ReportTargetType.tryParse(map['targetType']) ?? ReportTargetType.user,
    targetId: asString(map['targetId']),
    reason: ReportReason.tryParse(map['reason']) ?? ReportReason.other,
    description: asString(map['description']),
    status: ReportStatus.tryParseOrPending(map['status']),
    createdAt: asDateOrNull(map['createdAt']),
  );
}

class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.blockedAt,
  });

  final String id;
  final String name;
  final String handle;
  final String? avatarUrl;
  final DateTime? blockedAt;

  factory BlockedUser.fromMap(Map<String, dynamic> map) => BlockedUser(
    id: asString(map['id']),
    name: asString(map['name'], 'Blocked user'),
    handle: asString(map['handle']),
    avatarUrl: asStringOrNull(map['avatarUrl']),
    blockedAt: asDateOrNull(map['blockedAt']),
  );

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

enum FeedbackCategory {
  bug('bug', 'Bug report'),
  feature('feature', 'Feature suggestion'),
  booking('booking', 'Booking issue'),
  payment('payment', 'Payment issue'),
  restaurantExperience('restaurant_experience', 'Restaurant experience'),
  general('general', 'General feedback');

  const FeedbackCategory(this.wire, this.label);
  final String wire;
  final String label;

  static FeedbackCategory? tryParse(Object? value) {
    final s = value is String ? value : null;
    return values.where((e) => e.wire == s).firstOrNull;
  }
}

enum FeedbackStatus {
  open('open', 'Open'),
  inProgress('in_progress', 'In progress'),
  resolved('resolved', 'Resolved'),
  closed('closed', 'Closed');

  const FeedbackStatus(this.wire, this.label);
  final String wire;
  final String label;

  static FeedbackStatus tryParseOrOpen(Object? value) {
    final s = value is String ? value : null;
    return values.where((e) => e.wire == s).firstOrNull ?? FeedbackStatus.open;
  }
}

class FeedbackItem {
  const FeedbackItem({
    required this.id,
    required this.ticket,
    required this.category,
    required this.subject,
    required this.description,
    required this.relatedRef,
    required this.status,
    required this.createdAt,
  });

  final String id;

  /// User-facing confirmation handle, e.g. `FB-7K3MQF`.
  final String ticket;
  final FeedbackCategory category;
  final String subject;
  final String description;
  final String relatedRef;
  final FeedbackStatus status;
  final DateTime? createdAt;

  factory FeedbackItem.fromMap(Map<String, dynamic> map) => FeedbackItem(
    id: asString(map['id']),
    ticket: asString(map['ticket']),
    category:
        FeedbackCategory.tryParse(map['category']) ?? FeedbackCategory.general,
    subject: asString(map['subject']),
    description: asString(map['description']),
    relatedRef: asString(map['relatedRef']),
    status: FeedbackStatus.tryParseOrOpen(map['status']),
    createdAt: asDateOrNull(map['createdAt']),
  );
}
