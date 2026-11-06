import '../json.dart';
import 'restaurant_dto.dart' show VenueEventDto;
import 'review_dto.dart';

/// A user/profile payload from `/auth/me`, `/users/me`, `/users/:id` and the
/// `user` object returned by sign-in. `handle`/`role` are extra API facts that
/// the domain model folds into derived flags.
class UserDto {
  const UserDto({
    required this.id,
    required this.name,
    this.handle = '',
    this.city = '',
    this.bio = '',
    this.followers = 0,
    this.following = 0,
    this.dinnersHosted = 0,
    this.dinnersJoined = 0,
    this.rating = 0,
    this.reviewCount = 0,
    this.avatarUrl,
    this.badges = const [],
    this.tastes = const [],
    this.accentHex,
    this.joinedYear = 0,
    this.role = 'user',
    this.accountType = 'personal',
    this.professionalSince,
    this.instagram = '',
    this.isFollowing = false,
    this.isVerified = false,
    this.email = '',
    this.homeArea = '',
    this.dietary = const [],
    this.allergies = const [],
    this.showFollowList = true,
    this.showActivity = true,
    this.dmFromFollowersOnly = false,
    this.allowTagging = true,
  });

  final String id;
  final String name;
  final String handle;
  final String city;
  final String bio;
  final int followers;
  final int following;
  final int dinnersHosted;
  final int dinnersJoined;
  final double rating;
  final int reviewCount;
  final String? avatarUrl;
  final List<String> badges;
  final List<String> tastes;
  final String? accentHex;
  final int joinedYear;
  final String role;

  /// Customer account mode: `personal` (private, the default) or
  /// `professional` (public host profile + Host Studio). Orthogonal to [role].
  final String accountType;

  /// When the account first went Professional; null if it never has.
  final DateTime? professionalSince;

  /// Bare Instagram username (no `@`), empty when the user has not linked one.
  final String instagram;

  /// Viewer-relative follow state, present on `/users` discovery and
  /// follower/following roster rows.
  final bool isFollowing;

  /// Verified flag as issued by the server (`isVerified`), already folded with
  /// the `badges` fallback in [fromJson]. Influencer status implies verified.
  final bool isVerified;

  /// Login address from `/auth/me` (empty on public roster payloads, which
  /// never carry PII).
  final String email;

  // ── Account & Settings (P1) ── server-owned preferences the Settings
  // screens read straight off the session bootstrap.
  final String homeArea;
  final List<String> dietary;
  final List<String> allergies;
  final bool showFollowList;
  final bool showActivity;
  final bool dmFromFollowersOnly;
  final bool allowTagging;

  // Growth ladder on one account: diner ('user') → host → influencer. An
  // influencer keeps every host capability, so `isHost` covers both rungs.
  bool get isHost => role == 'host' || role == 'influencer';
  bool get isInfluencer => role == 'influencer';
  bool get isPartnerAdmin => role == 'partner_admin';
  bool get isSuperAdmin => role == 'super_admin';

  /// Whether the account is in its public, Host-Studio-enabled mode.
  bool get isProfessional => accountType == 'professional';

  static UserDto fromJson(Map<String, dynamic> json) => UserDto(
    id: asString(json['id']),
    name: asString(json['name']),
    handle: asString(json['handle']),
    city: asString(json['city']),
    bio: asString(json['bio']),
    followers: asInt(json['followers']),
    following: asInt(json['following']),
    dinnersHosted: asInt(json['dinnersHosted']),
    dinnersJoined: asInt(json['dinnersJoined']),
    rating: asDouble(json['rating']),
    reviewCount: asInt(json['reviewCount']),
    avatarUrl: asStringOrNull(json['avatarUrl']),
    badges: asStringList(json['badges']),
    tastes: asStringList(json['tastes']),
    accentHex: asStringOrNull(json['accentHex']),
    joinedYear: asInt(json['joinedYear']),
    role: asString(json['role'], 'user'),
    // Absent on older payloads (and on public roster rows from a pre-migration
    // server): fall back to the private default rather than guessing.
    accountType: asString(json['accountType'], 'personal'),
    professionalSince: asDateOrNull(json['professionalSince']),
    instagram: asString(json['instagram']).replaceFirst(RegExp(r'^@+'), ''),
    isFollowing: asBool(json['isFollowing']),
    // Server sends the resolved flag; fall back to the legacy 'verified'
    // badge so payloads predating the tier endpoints still light the UI.
    isVerified:
        asBool(json['isVerified']) ||
        asStringList(json['badges']).contains('verified'),
    email: asString(json['email']),
    homeArea: asString(json['homeArea']),
    dietary: asStringList(json['dietary']),
    allergies: asStringList(json['allergies']),
    showFollowList: asBool(json['showFollowList'], true),
    showActivity: asBool(json['showActivity'], true),
    dmFromFollowersOnly: asBool(json['dmFromFollowersOnly']),
    allowTagging: asBool(json['allowTagging'], true),
  );
}

/// Parsed `/users/:id` envelope: the profile plus follow state, hosted
/// upcoming events and recent reviews.
class UserProfileDto {
  const UserProfileDto({
    required this.user,
    this.viewerFollows = false,
    this.hostedUpcoming = const [],
    this.reviews = const [],
  });

  final UserDto user;
  final bool viewerFollows;
  final List<VenueEventDto> hostedUpcoming;
  final List<ReviewDto> reviews;

  static UserProfileDto fromJson(Map<String, dynamic> json) => UserProfileDto(
    user: UserDto.fromJson(asMap(json['user'])),
    viewerFollows: asBool(json['viewerFollows']),
    hostedUpcoming: asMapList(json['hostedUpcoming'])
        .map(VenueEventDto.fromJson)
        .toList(),
    reviews: asMapList(json['reviews']).map(ReviewDto.fromJson).toList(),
  );
}
