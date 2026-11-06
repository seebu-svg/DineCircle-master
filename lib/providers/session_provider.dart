import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/mappers/mappers.dart';
import '../api/dto/tier_dto.dart';
import '../models/user_profile.dart';
import '../repositories/session_repository.dart';
import '../repositories/users_repository.dart';
import 'api_client_provider.dart';

const String _tokenKey = 'dinecircle.auth.token';

/// The resolved sign-in state the rest of the app keys off.
class AppSession {
  const AppSession({
    required this.signedIn,
    this.userId,
    this.role = 'user',
    this.accountType = 'personal',
    this.user,
  });

  factory AppSession.signedOut() => const AppSession(signedIn: false);

  factory AppSession.fromProfile(UserProfile profile) => AppSession(
    signedIn: true,
    userId: profile.id,
    role: profile.role,
    accountType: profile.accountType,
    user: profile,
  );

  final bool signedIn;
  final String? userId;
  final String role;

  /// `personal` (private, default) or `professional` (public + Host Studio).
  final String accountType;
  final UserProfile? user;
}

/// Owns the bearer token: restores it from secure storage on launch, and swaps
/// it for a fresh one when the user signs up or signs in with email + password.
class SessionController extends AsyncNotifier<AppSession> {
  @override
  Future<AppSession> build() => _bootstrap();

  /// Restores a stored token and validates it with `GET /auth/me`. Any failure
  /// (no token, or a rejected/expired token) resolves to a signed-out session.
  Future<AppSession> _bootstrap() async {
    final storage = ref.read(secureStorageProvider);
    final client = ref.read(apiClientProvider);

    final stored = await storage.read(key: _tokenKey);
    if (stored == null || stored.isEmpty) {
      return AppSession.signedOut();
    }

    client.token = stored;
    try {
      final me = await ref.read(sessionRepositoryProvider).me();
      return AppSession.fromProfile(Mappers.userFromDto(me));
    } catch (_) {
      // Token rejected/expired — clear it and drop to signed-out.
      await storage.delete(key: _tokenKey);
      client.token = null;
      return AppSession.signedOut();
    }
  }

  /// Persists a freshly-minted session: installs the bearer token on the
  /// client, writes it to secure storage, and publishes the signed-in state.
  Future<void> _adoptSession(Session session) async {
    ref.read(apiClientProvider).token = session.token;
    await ref
        .read(secureStorageProvider)
        .write(key: _tokenKey, value: session.token);
    state = AsyncData(
      AppSession.fromProfile(Mappers.userFromDto(session.user)),
    );
  }

  /// Creates an email + password account, then signs the user straight in.
  /// Throws [ApiException] (surfaced inline by the AuthScreen) on failure; a
  /// failed attempt leaves the current state untouched.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final session = await ref
        .read(sessionRepositoryProvider)
        .signUp(name: name, email: email, password: password);
    await _adoptSession(session);
  }

  /// Signs in with email + password. Throws [ApiException] on bad credentials;
  /// a failure leaves the current state untouched.
  Future<void> login({required String email, required String password}) async {
    final session = await ref
        .read(sessionRepositoryProvider)
        .login(email: email, password: password);
    await _adoptSession(session);
  }

  /// Re-reads `/auth/me` and republishes the session, picking up any profile or
  /// role change made elsewhere (e.g. after [promoteToHost]).
  Future<void> refresh() async {
    final me = await ref.read(sessionRepositoryProvider).me();
    final profile = Mappers.userFromDto(me);
    state = AsyncData(AppSession.fromProfile(profile));
  }

  /// Promotes the signed-in diner to a host (`POST /users/me/host`) so they can
  /// publish dinners. Refreshes the session on success; throws [ApiException]
  /// (surfaced by the caller) when the account already holds a publishing role.
  Future<void> promoteToHost() async {
    final updated = await ref.read(sessionRepositoryProvider).becomeHost();
    state = AsyncData(AppSession.fromProfile(Mappers.userFromDto(updated)));
  }

  /// Switches the SAME account between `personal` and `professional`
  /// (`POST /users/me/account-type`) and republishes the session, so every
  /// gate (Host Studio, profile badge, host discovery) updates at once.
  ///
  /// Throws [ApiException] (409 with a human sentence) when upcoming hosted
  /// experiences block a switch back to Personal — the caller surfaces it.
  Future<void> switchAccountType(String accountType) async {
    final updated = await ref
        .read(usersRepositoryProvider)
        .setAccountType(accountType);
    state = AsyncData(AppSession.fromProfile(updated));
    // Blockers and the "Professional since" line are server-owned facts.
    ref.invalidate(accountTypeStatusProvider);
  }

  /// Claims Food Influencer status on the same account
  /// (`POST /users/me/influencer`). Refreshes the session; [tierProvider]
  /// recomputes on its own once the role leaves `host`. Throws
  /// [ApiException] (403 "Not eligible yet") when the server-side thresholds
  /// are unmet, for the caller to surface.
  Future<void> promoteToInfluencer() async {
    final updated = await ref
        .read(sessionRepositoryProvider)
        .becomeInfluencer();
    state = AsyncData(AppSession.fromProfile(Mappers.userFromDto(updated)));
  }

  /// Edits the signed-in profile (`PATCH /users/me`) and republishes the
  /// session so [currentUserProvider] and the profile screen reflect the new
  /// name/bio/city/tastes immediately. Throws [ApiException] for the caller to
  /// surface inline.
  Future<void> updateProfile({
    required String name,
    required String city,
    String bio = '',
    List<String> tastes = const [],
  }) async {
    final updated = await ref
        .read(usersRepositoryProvider)
        .updateMe(name: name, city: city, bio: bio, tastes: tastes);
    state = AsyncData(_carryEmail(updated));
  }

  // ── Account lifecycle (P1) ────────────────────────────────────────────────

  /// Partial settings write (`PATCH /users/me`) for the Settings screens —
  /// privacy toggles, food preferences, home locale. Republishes the session
  /// with the server's authoritative row so tiles reflect the saved state.
  /// Throws [ApiException] (validation) for the caller to surface/roll back.
  Future<void> updateSettings(Map<String, dynamic> patch) async {
    final updated = await ref
        .read(usersRepositoryProvider)
        .patchSettings(patch);
    state = AsyncData(_carryEmail(updated));
  }

  /// Uploads a new profile photo (`PUT /users/me/avatar`) and republishes the
  /// session with the server's versioned avatar URL. [onProgress] receives the
  /// sent/total ratio (0..1) so the picker can render a determinate bar.
  /// Throws [ApiException] (413 too large / 415 unsupported type) for the
  /// caller to surface.
  Future<void> uploadAvatar(
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    final updated = await ref
        .read(usersRepositoryProvider)
        .uploadAvatar(bytes, onProgress: onProgress);
    state = AsyncData(_carryEmail(updated));
  }

  /// Removes the profile photo (`DELETE /users/me/avatar`); the UI falls back
  /// to the initials avatar.
  Future<void> removeAvatar() async {
    final updated = await ref.read(usersRepositoryProvider).removeAvatar();
    state = AsyncData(_carryEmail(updated));
  }

  /// `POST /auth/change-password`. The server verifies the current password
  /// and revokes every OTHER session; this device stays signed in, so a
  /// successful call only refreshes the published profile. Throws
  /// [ApiException] (401 wrong current password) for the sheet to surface.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final updated = await ref
        .read(sessionRepositoryProvider)
        .changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
    state = AsyncData(AppSession.fromProfile(Mappers.userFromDto(updated)));
  }

  /// Starts a verified email change (`POST /auth/change-email`). Returns the
  /// challenge; in dev builds it carries [EmailChangeChallenge.devCode] since
  /// no mail provider is wired. State is untouched until the code confirms.
  Future<EmailChangeChallenge> requestEmailChange({
    required String email,
    required String password,
  }) => ref
      .read(sessionRepositoryProvider)
      .requestEmailChange(email: email, password: password);

  /// Completes the email change (`POST /auth/change-email/confirm`). Applies
  /// the new login handle to the live session; other devices are signed out.
  /// Throws [ApiException] (401 bad/expired code) for the caller to surface.
  Future<void> confirmEmailChange({required String code}) async {
    final updated = await ref
        .read(sessionRepositoryProvider)
        .confirmEmailChange(code: code);
    state = AsyncData(AppSession.fromProfile(Mappers.userFromDto(updated)));
  }

  /// `POST /auth/logout-all`, then clears the local token. Every device —
  /// including this one — lands back on the sign-in screen.
  Future<void> logoutAllDevices() async {
    try {
      await ref.read(sessionRepositoryProvider).logoutAll();
    } catch (_) {
      // Even if the call fails we must not keep a possibly-still-valid token.
    }
    final client = ref.read(apiClientProvider);
    client.token = null;
    await ref.read(secureStorageProvider).delete(key: _tokenKey);
    state = const AsyncData(AppSession(signedIn: false));
  }

  /// `DELETE /users/me` with password confirmation, then clears local state.
  /// The server settles money (cancels/refunds live bookings) and anonymises
  /// the account; a failure (401 wrong password) throws for the dialog and
  /// leaves the session untouched.
  Future<void> deleteAccount({required String password}) async {
    await ref.read(sessionRepositoryProvider).deleteAccount(password: password);
    final client = ref.read(apiClientProvider);
    client.token = null;
    await ref.read(secureStorageProvider).delete(key: _tokenKey);
    state = const AsyncData(AppSession(signedIn: false));
  }

  /// Wraps a `/users/me` write result in a session, carrying over the login
  /// email: that payload intentionally omits PII, so a settings write must
  /// never blank the address `/auth/me` supplied.
  AppSession _carryEmail(UserProfile updated) {
    final current = state.valueOrNull?.user;
    final hydrated = current != null && updated.email.isEmpty
        ? updated.copyWith(email: current.email)
        : updated;
    return AppSession.fromProfile(hydrated);
  }

  // ── Phone + OTP (dormant; not wired into the first-launch UI) ──────────────

  /// Asks the server to text a code to [phone]. Returns the challenge, which
  /// carries a dev-only `devCode` for hinting/autofill. Does not touch state.
  Future<OtpChallenge> requestOtp(String phone) =>
      ref.read(sessionRepositoryProvider).requestOtp(phone);

  /// Exchanges a phone + 6-digit code for a session and persists the token.
  Future<void> verifyOtp({required String phone, required String code}) async {
    final session = await ref
        .read(sessionRepositoryProvider)
        .verifyOtp(phone: phone, code: code);
    await _adoptSession(session);
  }

  /// Signs in with an explicit phone via the MVP `/auth/signin` (kept for tests
  /// and demos).
  Future<void> signIn(String phone) async {
    state = const AsyncLoading();
    final session = await ref.read(sessionRepositoryProvider).signIn(phone);
    await _adoptSession(session);
  }

  Future<void> signOut() async {
    final client = ref.read(apiClientProvider);
    try {
      await ref.read(sessionRepositoryProvider).signOut();
    } catch (_) {
      // Best-effort: always clear local state even if the server call fails.
    }
    client.token = null;
    await ref.read(secureStorageProvider).delete(key: _tokenKey);
    state = const AsyncData(AppSession(signedIn: false));
  }

  /// Called by [ApiClient] when any request returns 401.
  void handleUnauthorized() {
    ref.read(apiClientProvider).token = null;
    ref.read(secureStorageProvider).delete(key: _tokenKey);
    state = const AsyncData(AppSession(signedIn: false));
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, AppSession>(SessionController.new);

/// Convenience view of the signed-in profile (null until session is ready).
final currentUserIdProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session.valueOrNull?.userId;
});

/// True once the bearer token is bootstrapped. Data providers watch this so
/// they short-circuit to empty while loading, then recompute with auth applied.
final authReadyProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session.valueOrNull?.signedIn ?? false;
});

/// The signed-in user's server role (`user`/`host`/`influencer`/
/// `partner_admin`/`super_admin`), or `user` while signed out/loading.
final currentRoleProvider = Provider<String>((ref) {
  return ref.watch(sessionControllerProvider).valueOrNull?.role ?? 'user';
});

/// The signed-in user's account mode: `personal` (private, default) or
/// `professional` (public + Host Studio).
final accountTypeProvider = Provider<String>((ref) {
  return ref.watch(sessionControllerProvider).valueOrNull?.accountType ??
      'personal';
});

/// Whether Host Studio is available to this account.
///
/// Account-type driven on purpose: a Personal account has no Host Studio even
/// if it holds the host role from an earlier stint, and switching back is
/// therefore never destructive. The server enforces the same rule.
final canHostProvider = Provider<bool>(
  (ref) => ref.watch(accountTypeProvider) == 'professional',
);

/// Server-owned detail behind the Account Type screen: when the account first
/// went Professional and which upcoming experiences currently block a switch
/// back to Personal. Read once per screen visit; invalidated on every switch.
final accountTypeStatusProvider = FutureProvider<AccountTypeStatus>((ref) {
  if (!ref.watch(authReadyProvider)) return const AccountTypeStatus();
  return ref.read(usersRepositoryProvider).accountTypeStatus();
});

/// Growth-ladder status for the Profile tier card. Only fetched for hosts —
/// diners see the Become-a-host prompt instead, and influencers/partners have
/// nothing left to claim — so every other rung short-circuits to null.
final tierProvider = FutureProvider<TierDto?>((ref) async {
  if (!ref.watch(authReadyProvider)) return null;
  if (ref.watch(currentRoleProvider) != 'host') return null;
  return ref.read(sessionRepositoryProvider).tier();
});
