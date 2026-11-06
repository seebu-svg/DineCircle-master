import '../json.dart';

/// The author block attached to a review payload (list and profile reviews).
class ReviewAuthorDto {
  const ReviewAuthorDto({this.id, this.name = '', this.handle, this.avatarUrl});

  final String? id;
  final String name;
  final String? handle;
  final String? avatarUrl;

  static ReviewAuthorDto fromJson(Map<String, dynamic> json) => ReviewAuthorDto(
    id: asStringOrNull(json['id']),
    name: asString(json['name']),
    handle: asStringOrNull(json['handle']),
    avatarUrl: asStringOrNull(json['avatarUrl']),
  );
}

/// A review from `/reviews` or the `reviews` array on `/users/:id`.
class ReviewDto {
  const ReviewDto({
    required this.id,
    this.eventId,
    this.eventTitle,
    this.rating = 0,
    this.text = '',
    this.createdAt,
    required this.author,
  });

  final String id;
  final String? eventId;
  final String? eventTitle;
  final int rating;
  final String text;
  final DateTime? createdAt;
  final ReviewAuthorDto author;

  static ReviewDto fromJson(Map<String, dynamic> json) => ReviewDto(
    id: asString(json['id']),
    eventId: asStringOrNull(json['eventId']),
    eventTitle: asStringOrNull(json['eventTitle']),
    rating: asInt(json['rating']),
    text: asString(json['text']),
    createdAt: asDateOrNull(json['createdAt']),
    author: ReviewAuthorDto.fromJson(asMap(json['author'])),
  );
}
