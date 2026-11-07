import '../json.dart';

/// Parsed `GET /users/me/tier` envelope: the account's current rung on the
/// single-account growth ladder (diner → host → influencer) plus progress
/// toward the influencer thresholds. Values arrive as ints or decimals, so
/// both maps are normalized to double.
class TierDto {
  const TierDto({
    required this.tier,
    this.eligible = false,
    this.progress = const {},
    this.thresholds = const {},
  });

  /// `diner` | `host` | `influencer` | `partner`.
  final String tier;

  /// True only for a host whose metrics meet every influencer threshold,
  /// drives the "Claim influencer status" button on the Profile tier card.
  final bool eligible;

  /// Current metrics: followers / eventsHosted / rating / ratingCount.
  final Map<String, double> progress;

  /// Server-side thresholds: minFollowers / minEventsHosted / minRating /
  /// minRatingCount. Kept on the response so the UI never hardcodes them.
  final Map<String, double> thresholds;

  static Map<String, double> _numbers(Map<String, dynamic> json) => {
    for (final entry in json.entries) entry.key: asDouble(entry.value),
  };

  static TierDto fromJson(Map<String, dynamic> json) => TierDto(
    tier: asString(json['tier'], 'diner'),
    eligible: asBool(json['eligible']),
    progress: _numbers(asMap(json['progress'])),
    thresholds: _numbers(asMap(json['thresholds'])),
  );
}
