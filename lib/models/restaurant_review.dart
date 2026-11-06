/// A customer review for a restaurant.
class RestaurantReview {
  const RestaurantReview({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.restaurantId,
    required this.rating,
    required this.text,
    this.partnerReply,
    this.partnerRepliedAt,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String restaurantId;
  final double rating;
  final String text;
  final String? partnerReply;
  final DateTime? partnerRepliedAt;
  final DateTime createdAt;

  bool get hasPartnerReply => partnerReply != null && partnerReply!.isNotEmpty;
}

/// Aggregate rating for a restaurant.
class RestaurantReviewAggregate {
  const RestaurantReviewAggregate({
    required this.rating,
    required this.count,
  });

  final double rating;
  final int count;
}

/// Feed of reviews plus aggregate.
class RestaurantReviewFeed {
  const RestaurantReviewFeed({
    required this.reviews,
    required this.aggregate,
  });

  final List<RestaurantReview> reviews;
  final RestaurantReviewAggregate aggregate;

  bool get isEmpty => reviews.isEmpty;
}
