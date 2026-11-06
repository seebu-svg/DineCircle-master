import 'user_profile.dart';

/// Review model for dinner/event reviews
class Review {
  final String id;
  final UserProfile reviewer;
  final int rating; // 1-5
  final String comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.reviewer,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  String get formattedDate {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    return '${createdAt.month}/${createdAt.day}/${createdAt.year}';
  }
}
