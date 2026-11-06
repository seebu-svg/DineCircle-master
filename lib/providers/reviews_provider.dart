import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/review.dart';
import '../repositories/reviews_repository.dart';
import 'api_client_provider.dart';

/// Provider for the [ReviewsRepository] instance
final reviewsRepositoryProvider = Provider<ReviewsRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return ApiReviewsRepository(api);
});

/// Provider for event reviews
final eventReviewsProvider =
    FutureProvider.family<List<Review>, String>((ref, eventId) async {
  final repo = ref.watch(reviewsRepositoryProvider);
  return repo.getEventReviews(eventId);
});

/// Provider for host reviews
final hostReviewsProvider =
    FutureProvider.family<List<Review>, String>((ref, hostId) async {
  final repo = ref.watch(reviewsRepositoryProvider);
  return repo.getHostReviews(hostId);
});

/// Controller for creating reviews
final reviewControllerProvider = Provider((ref) {
  final repo = ref.watch(reviewsRepositoryProvider);
  return ReviewController(repo, ref);
});

class ReviewController {
  final ReviewsRepository _repo;
  final Ref _ref;

  ReviewController(this._repo, this._ref);

  /// Create a new review for an event
  Future<Review> createReview({
    required String eventId,
    required int rating,
    required String comment,
  }) async {
    final review = await _repo.createReview(
      eventId: eventId,
      rating: rating,
      comment: comment,
    );

    // Invalidate related providers to refresh UI
    _ref.invalidate(eventReviewsProvider(eventId));

    return review;
  }
}
