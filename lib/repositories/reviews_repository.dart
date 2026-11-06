import '../api/api_client.dart';
import '../models/review.dart';
import '../models/user_profile.dart';

/// Abstract interface for review operations
abstract class ReviewsRepository {
  /// Fetch reviews for a specific event
  Future<List<Review>> getEventReviews(String eventId);

  /// Fetch reviews for a specific host
  Future<List<Review>> getHostReviews(String hostId);

  /// Create a new review for an event
  Future<Review> createReview({
    required String eventId,
    required int rating,
    required String comment,
  });
}

/// API-backed implementation of [ReviewsRepository]
class ApiReviewsRepository implements ReviewsRepository {
  final ApiClient api;

  ApiReviewsRepository(this.api);

  UserProfile _parseReviewer(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Anonymous',
      avatarPath: json['avatarUrl'] as String? ?? json['avatar_url'] as String?,
    );
  }

  Review _parseReview(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ??
        json['reviewer'] as Map<String, dynamic>? ??
        <String, dynamic>{};
    return Review(
      id: json['id'] as String,
      reviewer: _parseReviewer(author),
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? json['text'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : json['created_at'] != null
              ? DateTime.parse(json['created_at'] as String)
              : DateTime.now(),
    );
  }

  @override
  Future<List<Review>> getEventReviews(String eventId) async {
    final json = await api.getJson('/reviews', query: {'eventId': eventId});
    final list = json['reviews'] as List<dynamic>? ?? [];
    return list
        .map((e) => _parseReview(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Review>> getHostReviews(String hostId) async {
    final json = await api.getJson('/reviews', query: {'hostId': hostId});
    final list = json['reviews'] as List<dynamic>? ?? [];
    return list
        .map((e) => _parseReview(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Review> createReview({
    required String eventId,
    required int rating,
    required String comment,
  }) async {
    final json = await api.postJson('/events/$eventId/reviews', body: {
      'rating': rating,
      'comment': comment,
    });
    return _parseReview(json as Map<String, dynamic>);
  }
}
