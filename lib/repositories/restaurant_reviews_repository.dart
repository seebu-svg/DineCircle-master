import '../models/restaurant_review.dart';
import '../api/api_client.dart';
import '../api/json.dart';

/// Restaurant reviews, read and write.
abstract class RestaurantReviewsRepository {
  /// Fetch reviews for a restaurant (public, paginated).
  Future<RestaurantReviewFeed> fetch(String restaurantId, {int limit = 20, int offset = 0});

  /// Submit a review (requires completed reservation).
  Future<RestaurantReview> submit(String restaurantId, {required double rating, required String text});
}

class ApiRestaurantReviewsRepository implements RestaurantReviewsRepository {
  ApiRestaurantReviewsRepository(this._client);

  final ApiClient _client;

  @override
  Future<RestaurantReviewFeed> fetch(String restaurantId, {int limit = 20, int offset = 0}) async {
    final body = await _client.getJson(
      '/restaurants/$restaurantId/reviews',
      query: {'limit': limit, 'offset': offset},
    );
    final map = asMap(body);
    final reviews = asMapList(map['reviews']).map(_reviewFromJson).toList();
    final aggregate = asMap(map['aggregate']);
    return RestaurantReviewFeed(
      reviews: reviews,
      aggregate: RestaurantReviewAggregate(
        rating: asDouble(aggregate['rating']),
        count: asInt(aggregate['count']),
      ),
    );
  }

  @override
  Future<RestaurantReview> submit(String restaurantId, {required double rating, required String text}) async {
    final body = await _client.postJson(
      '/restaurants/$restaurantId/reviews',
      body: {'rating': rating, 'text': text},
    );
    return _reviewFromJson(asMap(asMap(body)['review']));
  }

  RestaurantReview _reviewFromJson(Map<String, dynamic> json) {
    return RestaurantReview(
      id: asString(json['id']),
      authorId: asString(json['authorId']),
      authorName: asString(json['authorName']),
      restaurantId: asString(json['restaurantId']),
      rating: asDouble(json['rating']),
      text: asString(json['text']),
      partnerReply: asStringOrNull(json['partnerReply']),
      partnerRepliedAt: asDateOrNull(json['partnerRepliedAt']),
      createdAt: DateTime.parse(asString(json['createdAt'])),
    );
  }
}
