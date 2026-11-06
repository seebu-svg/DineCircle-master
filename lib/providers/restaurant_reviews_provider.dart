import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant_review.dart';
import 'api_client_provider.dart';

/// Provider for fetching restaurant reviews.
final restaurantReviewsProvider =
    FutureProvider.family<RestaurantReviewFeed, String>((ref, restaurantId) {
  return ref
      .watch(restaurantReviewsRepositoryProvider)
      .fetch(restaurantId);
});
