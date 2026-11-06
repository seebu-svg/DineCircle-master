import '../api/api_client.dart';
import '../api/dto/tier_dto.dart';
import '../api/dto/user_dto.dart';
import '../api/json.dart';

/// A resolved session: the bearer token plus the authenticated user's raw
/// profile. The `SessionController` persists the token and derives the current
/// user id/role from this.
class Session {
  const Session({required this.token, required this.user, this.expiresAt});

  final String token;
  final UserDto user;
  final DateTime? expiresAt;
}

/// Result of asking the server to send an OTP to a phone number. In dev the
/// API also returns the generated [devCode] so the UI can hint/autofill it;
/// in production that field is absent and the user reads the SMS/console code.
class OtpChallenge {
  const OtpChallenge({required this.sent, this.devCode, this.expiresAt});

  final bool sent;
  final String? devCode;
  final DateTime? expiresAt;
}

/// Result of starting a verified email change (`POST /auth/change-email`).
/// The new address is only applied after [confirmEmailChange] validates the
/// 6-digit code. No mail provider exists in this prototype, so dev builds
/// surface the code directly through [devCode] (same convention as OTP).
class EmailChangeChallenge {
  const EmailChangeChallenge({
    required this.sent,
    required this.pendingEmail,
    this.devCode,
    this.expiresAt,
  });

  final bool sent;
  final String pendingEmail;
  final String? devCode;
  final DateTime? expiresAt;
}

/// Auth surface: real email + password sign-in/sign-up (the primary
/// first-launch path), session restore, and sign-out. The OTP helpers are kept
/// dormant so phone auth can be re-enabled later without new plumbing.
abstract class SessionRepository {
  Future<Session> signUp({
    required String name,
    required String email,
    required String password,
  });
  Future<Session> login({required String email, required String password});
  Future<OtpChallenge> requestOtp(String phone);
  Future<Session> verifyOtp({required String phone, required String code});
  Future<Session> signIn(String phone);
  Future<UserDto> me();
  Future<void> signOut();

  /// Self-promotion to the host role (`POST /users/me/host`). Returns the
  /// refreshed user so the session can adopt the new role without a second
  /// round-trip.
  Future<UserDto> becomeHost();

  /// Current rung + progress toward Food Influencer (`GET /users/me/tier`).
  Future<TierDto> tier();

  /// Claim Food Influencer status on the same account
  /// (`POST /users/me/influencer`). Throws [ApiException] (403) with the
  /// "not eligible" body when thresholds are unmet; returns the refreshed
  /// user so the session adopts the new role immediately.
  Future<UserDto> becomeInfluencer();

  // ── Account lifecycle (P1) ────────────────────────────────────────────────

  /// `POST /auth/change-password` — verifies the current password server-side
  /// and revokes every OTHER session; the caller's device stays signed in.
  /// Returns the refreshed user for the live session.
  Future<UserDto> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// `POST /auth/change-email` — password-confirmed START of a verified
  /// email change. Does not touch [Session] state; the change only applies
  /// once [confirmEmailChange] succeeds.
  Future<EmailChangeChallenge> requestEmailChange({
    required String email,
    required String password,
  });

  /// `POST /auth/change-email/confirm` — validates the 6-digit code, applies
  /// the new address and revokes other sessions. Returns the refreshed user.
  Future<UserDto> confirmEmailChange({required String code});

  /// `POST /auth/logout-all` — revokes EVERY session, including this device.
  Future<void> logoutAll();

  /// `DELETE /users/me` — password-confirmed account deletion. The server
  /// anonymises the account in place, settles money and revokes all tokens.
  Future<void> deleteAccount({required String password});
}

class ApiSessionRepository implements SessionRepository {
  ApiSessionRepository(this._client);

  final ApiClient _client;

  @override
  Future<Session> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final body = await _client.postJson(
      '/auth/signup',
      body: {'name': name, 'email': email, 'password': password},
    );
    return _sessionFromBody(body);
  }

  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    final body = await _client.postJson(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    return _sessionFromBody(body);
  }

  @override
  Future<OtpChallenge> requestOtp(String phone) async {
    final body = await _client.postJson(
      '/auth/otp/request',
      body: {'phone': phone},
    );
    final map = asMap(body);
    return OtpChallenge(
      sent: asBool(map['sent'], true),
      devCode: asStringOrNull(map['devCode']),
      expiresAt: asDateOrNull(map['expiresAt']),
    );
  }

  @override
  Future<Session> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final body = await _client.postJson(
      '/auth/otp/verify',
      body: {'phone': phone, 'code': code},
    );
    return _sessionFromBody(body);
  }

  @override
  Future<Session> signIn(String phone) async {
    final body = await _client.postJson('/auth/signin', body: {'phone': phone});
    return _sessionFromBody(body);
  }

  Session _sessionFromBody(dynamic body) {
    final map = asMap(body);
    return Session(
      token: asString(map['token']),
      user: UserDto.fromJson(asMap(map['user'])),
      expiresAt: asDateOrNull(map['expiresAt']),
    );
  }

  @override
  Future<UserDto> me() async {
    final body = await _client.getJson('/auth/me');
    return UserDto.fromJson(asMap(asMap(body)['user']));
  }

  @override
  Future<void> signOut() => _client.postJson('/auth/signout');

  @override
  Future<UserDto> becomeHost() async {
    final body = await _client.postJson('/users/me/host');
    return UserDto.fromJson(asMap(asMap(body)['user']));
  }

  @override
  Future<TierDto> tier() async {
    final body = await _client.getJson('/users/me/tier');
    return TierDto.fromJson(asMap(body));
  }

  @override
  Future<UserDto> becomeInfluencer() async {
    final body = await _client.postJson('/users/me/influencer');
    return UserDto.fromJson(asMap(asMap(body)['user']));
  }

  @override
  Future<UserDto> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final body = await _client.postJson(
      '/auth/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    return UserDto.fromJson(asMap(asMap(body)['user']));
  }

  @override
  Future<EmailChangeChallenge> requestEmailChange({
    required String email,
    required String password,
  }) async {
    final body = await _client.postJson(
      '/auth/change-email',
      body: {'email': email, 'password': password},
    );
    final map = asMap(body);
    return EmailChangeChallenge(
      sent: asBool(map['sent'], true),
      pendingEmail: asString(map['email']),
      devCode: asStringOrNull(map['devCode']),
      expiresAt: asDateOrNull(map['expiresAt']),
    );
  }

  @override
  Future<UserDto> confirmEmailChange({required String code}) async {
    final body = await _client.postJson(
      '/auth/change-email/confirm',
      body: {'code': code},
    );
    return UserDto.fromJson(asMap(asMap(body)['user']));
  }

  @override
  Future<void> logoutAll() => _client.postJson('/auth/logout-all');

  @override
  Future<void> deleteAccount({required String password}) =>
      _client.deleteJson('/users/me', body: {'password': password});
}
