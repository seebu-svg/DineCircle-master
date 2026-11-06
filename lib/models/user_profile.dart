import 'package:flutter/material.dart';

/// A social media profile link on a user profile
enum SocialPlatform { instagram, tiktok, youtube, website }

extension SocialPlatformX on SocialPlatform {
  String get label {
    switch (this) {
      case SocialPlatform.instagram:
        return 'Instagram';
      case SocialPlatform.tiktok:
        return 'TikTok';
      case SocialPlatform.youtube:
        return 'YouTube';
      case SocialPlatform.website:
        return 'Website';
    }
  }

  IconData get icon {
    switch (this) {
      case SocialPlatform.instagram:
        return Icons.photo_camera_rounded;
      case SocialPlatform.tiktok:
        return Icons.music_note_rounded;
      case SocialPlatform.youtube:
        return Icons.play_circle_rounded;
      case SocialPlatform.website:
        return Icons.language_rounded;
    }
  }
}

/// A social media link (handle or URL) attached to a profile
class SocialLink {
  final SocialPlatform platform;
  final String handle;

  const SocialLink({required this.platform, required this.handle});
}

/// User profile model
class UserProfile {
  final String id;
  final String name;

  /// Public username (no `@`), unique per account. Empty for locally-built
  /// profiles that never came from the server.
  final String handle;
  final String? bio;
  final String? avatarPath;
  final String? coverImagePath;
  final int dinnersHosted;
  final int dinnersAttended;
  final int followers;
  final int following;
  final double rating;
  final int reviewCount;
  final bool isVerified;
  final bool isInfluencer;
  final bool isRestaurantPartner;
  final List<String> interests;
  final String? location;
  final List<SocialLink> socialLinks;

  /// Server role (`user` | `host` | `partner_admin` | `super_admin`). Drives
  /// the publish/host gate; defaults to `user` for locally-built profiles.
  final String role;

  /// Customer account mode: `personal` (private, default) or `professional`
  /// (public host profile + Host Studio). This — not [role] — decides whether
  /// Host Studio is available, so switching back to Personal never destroys a
  /// host's role, badges or history.
  final String accountType;

  /// When the account first went Professional; null if it never has. Kept
  /// after switching back, so the profile can still show "Professional since".
  final DateTime? professionalSince;

  /// Year the account joined (`users.joined_year`); 0 when unknown, so the
  /// profile never claims a false "member since" date.
  final int joinedYear;

  // ── Account & Settings (P1) ──────────────────────────────────────────────
  /// Login email (only present on the signed-in user's own payloads).
  final String email;

  /// Preferred dining area / neighbourhood within [location].
  final String homeArea;

  /// Dietary preferences (`Halal`, `Vegan`, …) and allergy labels persisted
  /// through `PATCH /users/me`.
  final List<String> dietary;
  final List<String> allergies;

  /// Privacy toggles mirrored from the server (`showFollowList`, etc). The
  /// roster/activity surfaces gate on the server side; these drive the
  /// Privacy & Security screen's initial state.
  final bool showFollowList;
  final bool showActivity;
  final bool dmFromFollowersOnly;
  final bool allowTagging;

  const UserProfile({
    required this.id,
    required this.name,
    this.handle = '',
    this.bio,
    this.avatarPath,
    this.coverImagePath,
    this.dinnersHosted = 0,
    this.dinnersAttended = 0,
    this.followers = 0,
    this.following = 0,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.isVerified = false,
    this.isInfluencer = false,
    this.isRestaurantPartner = false,
    this.interests = const [],
    this.location,
    this.socialLinks = const [],
    this.role = 'user',
    this.accountType = 'personal',
    this.professionalSince,
    this.joinedYear = 0,
    this.email = '',
    this.homeArea = '',
    this.dietary = const [],
    this.allergies = const [],
    this.showFollowList = true,
    this.showActivity = true,
    this.dmFromFollowersOnly = false,
    this.allowTagging = true,
  });

  /// Whether this account holds a publishing role (host/influencer/admin).
  /// Necessary but no longer sufficient for Host Studio — see [isProfessional].
  bool get hasHostingRole => role != 'user';

  /// Whether the account is in its public, Host-Studio-enabled mode.
  bool get isProfessional => accountType == 'professional';

  /// The linked Instagram username, or empty when none is set.
  String get instagram => socialLinks
      .where((l) => l.platform == SocialPlatform.instagram)
      .map((l) => l.handle)
      .firstWhere((h) => h.isNotEmpty, orElse: () => '');

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final first = parts.isEmpty ? '' : parts.first;
    return first.isEmpty ? '?' : first.substring(0, 1).toUpperCase();
  }

  /// [clearAvatar] resets [avatarPath] to null (back to initials), which the
  /// `??` fallbacks below could not express.
  UserProfile copyWith({
    String? id,
    String? name,
    String? handle,
    String? bio,
    String? avatarPath,
    bool clearAvatar = false,
    String? coverImagePath,
    int? dinnersHosted,
    int? dinnersAttended,
    int? followers,
    int? following,
    double? rating,
    int? reviewCount,
    bool? isVerified,
    bool? isInfluencer,
    bool? isRestaurantPartner,
    List<String>? interests,
    String? location,
    List<SocialLink>? socialLinks,
    String? role,
    String? accountType,
    DateTime? professionalSince,
    int? joinedYear,
    String? email,
    String? homeArea,
    List<String>? dietary,
    List<String>? allergies,
    bool? showFollowList,
    bool? showActivity,
    bool? dmFromFollowersOnly,
    bool? allowTagging,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      handle: handle ?? this.handle,
      bio: bio ?? this.bio,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      coverImagePath: coverImagePath ?? this.coverImagePath,
      dinnersHosted: dinnersHosted ?? this.dinnersHosted,
      dinnersAttended: dinnersAttended ?? this.dinnersAttended,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isVerified: isVerified ?? this.isVerified,
      isInfluencer: isInfluencer ?? this.isInfluencer,
      isRestaurantPartner: isRestaurantPartner ?? this.isRestaurantPartner,
      interests: interests ?? this.interests,
      location: location ?? this.location,
      socialLinks: socialLinks ?? this.socialLinks,
      role: role ?? this.role,
      accountType: accountType ?? this.accountType,
      professionalSince: professionalSince ?? this.professionalSince,
      joinedYear: joinedYear ?? this.joinedYear,
      email: email ?? this.email,
      homeArea: homeArea ?? this.homeArea,
      dietary: dietary ?? this.dietary,
      allergies: allergies ?? this.allergies,
      showFollowList: showFollowList ?? this.showFollowList,
      showActivity: showActivity ?? this.showActivity,
      dmFromFollowersOnly: dmFromFollowersOnly ?? this.dmFromFollowersOnly,
      allowTagging: allowTagging ?? this.allowTagging,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
