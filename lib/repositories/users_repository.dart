import 'dart:convert';
import 'dart:typed_data';

import '../models/dinner.dart';
import '../models/review.dart';
import '../models/user_profile.dart';
import '../api/api_client.dart';
import '../api/dto/user_dto.dart';
import '../api/json.dart';
import '../api/mappers/mappers.dart';

/// A public host profile: the user, their upcoming hosted events, recent
/// reviews and whether the signed-in viewer already follows them.
class HostProfile {
  const HostProfile({
    required this.user,
    this.hostedUpcoming = const [],
    this.reviews = const [],
    this.viewerFollows = false,
  });

  final UserProfile user;
  final List<Dinner> hostedUpcoming;
  final List<Review> reviews;
  final bool viewerFollows;
}

/// A roster/discovery row: a profile plus the viewer's follow state, straight
/// from `GET /users`, `/users/:id/followers` or `/users/:id/following` (P0-3).
class RosterUser {
  const RosterUser({required this.user, this.isFollowing = false});

  final UserProfile user;
  final bool isFollowing;
}

/// Advisory answer to `GET /users/handle-available`.
///
/// `reason` mirrors the server's vocabulary: `null` when claimable, otherwise
/// `taken`, `reserved` (`deleted_` prefix) or `invalid` (fails the username
/// pattern). The server's 409 on `PATCH /users/me` stays authoritative.
class HandleAvailability {
  const HandleAvailability({
    required this.handle,
    required this.available,
    this.reason,
  });

  final String handle;
  final bool available;
  final String? reason;

  /// Message to render beside a rejected username.
  String get message {
    switch (reason) {
      case 'taken':
        return 'That username is taken';
      case 'reserved':
        return 'That username is reserved';
      case 'invalid':
        return 'Use 3–30 letters, numbers, _ or .';
      default:
        return 'That username is unavailable';
    }
  }
}

/// An upcoming hosted experience that prevents switching back to a Personal
/// account. Mirrors one row of `blockers` on `GET /users/me/account-type`.
class AccountTypeBlocker {
  const AccountTypeBlocker({
    required this.id,
    required this.title,
    this.startAt,
    this.status = '',
  });

  final String id;
  final String title;
  final DateTime? startAt;
  final String status;
}

/// The signed-in account's mode plus what currently blocks leaving Professional.
class AccountTypeStatus {
  const AccountTypeStatus({
    this.accountType = 'personal',
    this.professionalSince,
    this.blockers = const [],
  });

  final String accountType;
  final DateTime? professionalSince;
  final List<AccountTypeBlocker> blockers;

  bool get isProfessional => accountType == 'professional';
  bool get canSwitchToPersonal => blockers.isEmpty;
}

abstract class UsersRepository {
  Future<UserProfile> me();
  Future<HostProfile> profile(String id);

  /// People-screen discovery list (`GET /users`), optionally searched.
  Future<List<RosterUser>> discover({
    String? query,
    int limit = 20,
    int offset = 0,
  });

  /// Accounts that follow [id] (`GET /users/:id/followers`).
  Future<List<RosterUser>> followers(
    String id, {
    int limit = 20,
    int offset = 0,
  });

  /// Accounts [id] follows (`GET /users/:id/following`).
  Future<List<RosterUser>> following(
    String id, {
    int limit = 20,
    int offset = 0,
  });

  /// Edits the signed-in profile (`PATCH /users/me`). The server requires a
  /// name and city; bio/tastes fall back to empty when omitted.
  Future<UserProfile> updateMe({
    required String name,
    required String city,
    String bio = '',
    List<String> tastes = const [],
  });

  /// Whether [handle] is still claimable (`GET /users/handle-available`).
  /// Advisory only: the `PATCH` 409 remains the authority.
  Future<HandleAvailability> handleAvailability(String handle);

  /// Partial settings write to `PATCH /users/me` carrying only the keys the
  /// caller owns — home area, dietary/allergy lists, privacy toggles. The
  /// endpoint validates each field and leaves every other column untouched,
  /// so a Settings screen can never blank an unrelated field.
  Future<UserProfile> patchSettings(Map<String, dynamic> patch);

  /// Replaces the profile photo (`PUT /users/me/avatar`). [bytes] must be a
  /// JPEG, PNG or WebP of at most 512 KB; the server sniffs the real type.
  ///
  /// [onProgress] receives 0..1 while the body uploads so the picker can show
  /// a determinate bar instead of an indeterminate spinner.
  Future<UserProfile> uploadAvatar(
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  });

  /// Removes the profile photo (`DELETE /users/me/avatar`) — back to initials.
  Future<UserProfile> removeAvatar();

  /// Current account mode + the upcoming experiences that block a downgrade
  /// (`GET /users/me/account-type`).
  Future<AccountTypeStatus> accountTypeStatus();

  /// Switches the SAME account between `personal` and `professional`
  /// (`POST /users/me/account-type`). Returns the server's authoritative user
  /// row so the session can be republished in one round trip. Throws
  /// [ApiException] 409 with the server's sentence when upcoming experiences
  /// block a downgrade.
  Future<UserProfile> setAccountType(String accountType);
}

class ApiUsersRepository implements UsersRepository {
  ApiUsersRepository(this._client);

  final ApiClient _client;

  @override
  Future<UserProfile> me() async {
    final body = await _client.getJson('/users/me');
    return Mappers.userFromDto(UserDto.fromJson(asMap(asMap(body)['user'])));
  }

  @override
  Future<HostProfile> profile(String id) async {
    final body = await _client.getJson('/users/$id');
    final dto = UserProfileDto.fromJson(asMap(body));
    final user = Mappers.userFromDto(dto.user);
    final hosted = dto.hostedUpcoming
        .map((e) => Mappers.dinnerFromVenueEvent(e, host: user))
        .toList();
    final reviews = dto.reviews.map(Mappers.reviewFromDto).toList();
    return HostProfile(
      user: user,
      hostedUpcoming: hosted,
      reviews: reviews,
      viewerFollows: dto.viewerFollows,
    );
  }

  List<RosterUser> _roster(dynamic body) => asMapList(asMap(body)['users'])
      .map(UserDto.fromJson)
      .map(
        (dto) => RosterUser(
          user: Mappers.userFromDto(dto),
          isFollowing: dto.isFollowing,
        ),
      )
      .toList();

  @override
  Future<List<RosterUser>> discover({
    String? query,
    int limit = 20,
    int offset = 0,
  }) async {
    final body = await _client.getJson(
      '/users',
      query: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return _roster(body);
  }

  @override
  Future<List<RosterUser>> followers(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async {
    final body = await _client.getJson(
      '/users/$id/followers',
      query: {'limit': limit, 'offset': offset},
    );
    return _roster(body);
  }

  @override
  Future<List<RosterUser>> following(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async {
    final body = await _client.getJson(
      '/users/$id/following',
      query: {'limit': limit, 'offset': offset},
    );
    return _roster(body);
  }

  @override
  Future<UserProfile> updateMe({
    required String name,
    required String city,
    String bio = '',
    List<String> tastes = const [],
  }) async {
    final body = await _client.patchJson(
      '/users/me',
      body: {'name': name, 'city': city, 'bio': bio, 'tastes': tastes},
    );
    return Mappers.userFromDto(UserDto.fromJson(asMap(asMap(body)['user'])));
  }

  @override
  Future<HandleAvailability> handleAvailability(String handle) async {
    final body = await _client.getJson(
      '/users/handle-available',
      query: {'handle': handle},
    );
    final map = asMap(body);
    return HandleAvailability(
      handle: asString(map['handle']),
      available: asBool(map['available']),
      reason: asStringOrNull(map['reason']),
    );
  }

  @override
  Future<UserProfile> patchSettings(Map<String, dynamic> patch) async {
    final body = await _client.patchJson('/users/me', body: patch);
    return Mappers.userFromDto(UserDto.fromJson(asMap(asMap(body)['user'])));
  }

  @override
  Future<UserProfile> uploadAvatar(
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    final body = await _client.putJson(
      '/users/me/avatar',
      body: {'image': base64Encode(bytes)},
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total <= 0) return;
              onProgress((sent / total).clamp(0.0, 1.0));
            },
    );
    return Mappers.userFromDto(UserDto.fromJson(asMap(asMap(body)['user'])));
  }

  @override
  Future<UserProfile> removeAvatar() async {
    final body = await _client.deleteJson('/users/me/avatar');
    return Mappers.userFromDto(UserDto.fromJson(asMap(asMap(body)['user'])));
  }

  @override
  Future<AccountTypeStatus> accountTypeStatus() async {
    final map = asMap(await _client.getJson('/users/me/account-type'));
    return AccountTypeStatus(
      accountType: asString(map['accountType'], 'personal'),
      professionalSince: asDateOrNull(map['professionalSince']),
      blockers: asMapList(map['blockers'])
          .map(
            (row) => AccountTypeBlocker(
              id: asString(row['id']),
              title: asString(row['title']),
              startAt: asDateOrNull(row['startAt']),
              status: asString(row['status']),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<UserProfile> setAccountType(String accountType) async {
    final body = await _client.postJson(
      '/users/me/account-type',
      body: {'accountType': accountType},
    );
    return Mappers.userFromDto(UserDto.fromJson(asMap(asMap(body)['user'])));
  }
}
