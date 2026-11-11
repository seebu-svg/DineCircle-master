import 'dart:typed_data';

import 'package:dine_circle/api/dto/tier_dto.dart';
import 'package:dine_circle/api/dto/user_dto.dart';
import 'package:dine_circle/api/api_exception.dart';
import 'package:dine_circle/repositories/session_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:dine_circle/models/booking.dart';
import 'package:dine_circle/models/deal.dart';
import 'package:dine_circle/models/dinner.dart';
import 'package:dine_circle/models/host_models.dart';
import 'package:dine_circle/models/offer.dart';
import 'package:dine_circle/models/restaurant.dart';
import 'package:dine_circle/models/review.dart';
import 'package:dine_circle/models/search.dart';
import 'package:dine_circle/models/user_profile.dart';
import 'package:dine_circle/repositories/bookings_repository.dart';
import 'package:dine_circle/repositories/chat_repository.dart';
import 'package:dine_circle/repositories/deals_repository.dart';
import 'package:dine_circle/repositories/events_repository.dart';
import 'package:dine_circle/repositories/hosts_repository.dart';
import 'package:dine_circle/repositories/offers_repository.dart';
import 'package:dine_circle/repositories/restaurants_repository.dart';
import 'package:dine_circle/repositories/search_repository.dart';
import 'package:dine_circle/repositories/social_repository.dart';
import 'package:dine_circle/repositories/users_repository.dart';
import 'package:dine_circle/repositories/location_repository.dart';
import 'package:dine_circle/repositories/safety_repository.dart';
import 'package:dine_circle/models/saved_location.dart';
import 'package:dine_circle/models/safety.dart';

// ── Fixtures ───────────────────────────────────────────────────────────────

Restaurant fixtureRestaurant({
  String id = 'r1',
  String name = 'Skyline Room',
  bool isPartner = true,
  String partnershipStatus = 'verified',
}) => Restaurant(
  id: id,
  name: name,
  description: 'A stylish tasting venue.',
  cuisine: 'Japanese',
  address: '1 Market St',
  latitude: 0,
  longitude: 0,
  rating: 4.7,
  reviewCount: 12,
  isPartner: isPartner,
  partnershipStatus: partnershipStatus,
);

UserProfile fixtureHost({String id = 'h1', String name = 'Nora Chen'}) =>
    UserProfile(
      id: id,
      name: name,
      dinnersHosted: 8,
      followers: 240,
      following: 42,
      rating: 4.8,
      reviewCount: 5,
      // A host fixture is a Professional account: Host Studio is gated on the
      // account mode, not on the legacy role rung.
      accountType: 'professional',
    );

Dinner fixtureDinner({
  String id = 'e1',
  String title = 'Omakase Night',
  bool featured = false,
  List<MenuItem> menu = const [
    MenuItem(
      id: 'm1',
      name: 'Nigiri Flight',
      description: 'Chef choice',
      price: 0,
    ),
  ],
  List<UserProfile> attendees = const [],
  HostEventStatus hostStatus = HostEventStatus.published,
  String? declineReason,
  DateTime? approvalStaleAt,
}) => Dinner(
  id: id,
  title: title,
  description: 'An intimate chef\u2019s counter dinner.',
  restaurant: fixtureRestaurant(),
  host: fixtureHost(),
  dateTime: DateTime.now().add(const Duration(days: 2)),
  totalSeats: 10,
  bookedSeats: 4,
  pricePerSeat: 120,
  isSpecialEvent: featured,
  menu: menu,
  attendees: attendees,
  hostStatus: hostStatus,
  declineReason: declineReason,
  approvalStaleAt: approvalStaleAt,
);

Review fixtureReview() => Review(
  id: 'rev1',
  reviewer: fixtureHost(id: 'g1', name: 'Sam'),
  rating: 5,
  comment: 'Wonderful evening.',
  createdAt: DateTime.now(),
);

/// A booked ticket built from [dinner]/[user] mirroring what the server returns
/// after a successful join (authoritative total, generated reference).
Booking fixtureBooking({
  String id = 'b1',
  required Dinner dinner,
  required UserProfile user,
  int seats = 2,
  double total = 240,
  BookingStatus status = BookingStatus.confirmed,
}) => Booking(
  id: id,
  dinner: dinner,
  user: user,
  seats: seats,
  subtotal: dinner.pricePerSeat * seats,
  serviceFee: 0,
  totalAmount: total,
  status: status,
  createdAt: DateTime.now(),
  qrCode: 'DC-$id',
  guestName: user.name,
);

// ── Fakes ──────────────────────────────────────────────────────────────────

/// A controllable [EventsRepository]. Returns [events]/[reviews] after an
/// optional [delay], or throws [error] to exercise the failure path.
class FakeEventsRepository implements EventsRepository {
  FakeEventsRepository({
    this.events = const [],
    this.reviews = const [],
    this.mineEvents,
    this.error,
    this.patchError,
    this.patchResult,
    this.delay = Duration.zero,
  });

  final List<Dinner> events;
  final List<Review> reviews;
  final List<Dinner>? mineEvents;
  final Object? error;
  final Object? patchError;

  /// The record a patch answers with. At a venue that requires approval the
  /// server returns the event as `requested` rather than `confirmed`, and the
  /// host copy has to follow the response instead of the intent, so a test has
  /// to be able to say what came back.
  final Dinner? patchResult;
  final Duration delay;

  Future<void> _gate() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<List<Dinner>> feed({
    String? type,
    String? audience,
    bool? featured,
    String? query,
    String? city,
    bool includePast = false,
    double? maxPrice,
    DateTime? from,
    DateTime? to,
    String? sort,
  }) async {
    await _gate();
    feedCalls += 1;
    lastFeedQuery = query;
    lastFeedCity = city;
    lastFeedMaxPrice = maxPrice;
    lastFeedFrom = from;
    lastFeedTo = to;
    lastFeedAudience = audience;
    lastFeedType = type;
    return events;
  }

  int feedCalls = 0;
  String? lastFeedQuery;
  String? lastFeedCity;
  double? lastFeedMaxPrice;
  DateTime? lastFeedFrom;
  DateTime? lastFeedTo;
  String? lastFeedAudience;
  String? lastFeedType;

  @override
  Future<Dinner> byId(String id) async {
    await _gate();
    return events.firstWhere(
      (d) => d.id == id,
      orElse: () =>
          events.isEmpty ? throw StateError('no fixture') : events.first,
    );
  }

  @override
  Future<List<Dinner>> byHost(String hostId) async {
    await _gate();
    return events;
  }

  @override
  Future<List<Dinner>> byVenue(String venueId) async {
    await _gate();
    return events;
  }

  @override
  Future<List<Review>> reviewsFor(String eventId) async {
    await _gate();
    return reviews;
  }

  int publishCalls = 0;
  int cancelEventCalls = 0;
  int submitReviewCalls = 0;
  int patchEventCalls = 0;
  int mineCalls = 0;
  NewDinnerDraft? lastPublish;
  bool? lastPublishAsDraft;
  Map<String, dynamic>? lastPatch;
  String? lastPatchId;

  @override
  Future<Dinner> publish(NewDinnerDraft draft, {bool asDraft = false}) async {
    await _gate();
    publishCalls += 1;
    lastPublish = draft;
    lastPublishAsDraft = asDraft;
    return events.isEmpty ? fixtureDinner(id: 'new') : events.first;
  }

  @override
  Future<List<Dinner>> mine() async {
    await _gate();
    mineCalls += 1;
    return mineEvents ?? events;
  }

  @override
  Future<Dinner> patchEvent(String id, Map<String, dynamic> patch) async {
    await _gate();
    if (patchError != null) throw patchError!;
    patchEventCalls += 1;
    lastPatchId = id;
    lastPatch = patch;
    if (patchResult != null) return patchResult!;
    if (events.any((d) => d.id == id)) {
      return events.firstWhere((d) => d.id == id);
    }
    return fixtureDinner(id: id);
  }

  @override
  Future<void> cancelEvent(String id) async {
    await _gate();
    cancelEventCalls += 1;
  }

  @override
  Future<void> submitReview(
    String eventId, {
    required double rating,
    required String text,
  }) async {
    await _gate();
    submitReviewCalls += 1;
  }

  @override
  Future<List<Map<String, dynamic>>> savedEvents() async {
    await _gate();
    return const [];
  }
}

class FakeRestaurantsRepository implements RestaurantsRepository {
  FakeRestaurantsRepository({
    this.restaurants = const [],
    this.detailEvents = const [],
    this.error,
    this.followedRestaurants = const [],
  });

  final List<Restaurant> restaurants;
  final List<Dinner> detailEvents;
  final Object? error;

  /// What `GET /me/followed-restaurants` returns (Saved → Restaurants tab).
  final List<Restaurant> followedRestaurants;
  int followingCalls = 0;

  Future<void> _gate() async {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<List<Restaurant>> following() async {
    await _gate();
    followingCalls += 1;
    return followedRestaurants;
  }

  @override
  Future<List<Restaurant>> list({
    bool? partner,
    String? query,
    String? tag,
    String? city,
  }) async {
    await _gate();
    listCalls += 1;
    lastListQuery = query;
    lastListTag = tag;
    lastListCity = city;
    return restaurants;
  }

  int listCalls = 0;
  String? lastListQuery;
  String? lastListTag;
  String? lastListCity;

  @override
  Future<List<Restaurant>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 25,
  }) async {
    await _gate();
    return restaurants.where((r) => r.hasCoordinates).toList();
  }

  @override
  Future<RestaurantDetail> byId(String id) async {
    await _gate();
    return RestaurantDetail(
      restaurant: restaurants.firstWhere(
        (r) => r.id == id,
        orElse: () =>
            restaurants.isEmpty ? fixtureRestaurant(id: id) : restaurants.first,
      ),
      events: detailEvents,
    );
  }

  /// Last follow state the screen asked the server to persist, for asserting
  /// the Save/Unsave quick action without a network.
  bool followed = false;
  int followCalls = 0;

  @override
  Future<bool> setFollowing(String id, bool following) async {
    await _gate();
    followCalls += 1;
    followed = following;
    return following;
  }
}

class FakeUsersRepository implements UsersRepository {
  FakeUsersRepository({
    this.meResult,
    this.profileResult,
    this.profileError,
    this.discoverResult,
    this.followersResult,
    this.followingResult,
  });

  final UserProfile? meResult;
  final HostProfile? profileResult;
  final Object? profileError;
  // Callbacks so a refetch after follow/unfollow invalidation can reflect the
  // fake social state instead of a frozen snapshot.
  final List<RosterUser> Function()? discoverResult;
  final List<RosterUser> Function()? followersResult;
  final List<RosterUser> Function()? followingResult;

  int updateMeCalls = 0;
  int patchSettingsCalls = 0;
  Map<String, dynamic>? lastSettingsPatch;

  /// When set, [patchSettings] throws this (e.g. a 409 taken username).
  Object? settingsError;
  int discoverCalls = 0;
  String? lastDiscoverQuery;

  @override
  Future<List<RosterUser>> discover({
    String? query,
    int limit = 20,
    int offset = 0,
  }) async {
    discoverCalls += 1;
    lastDiscoverQuery = query;
    return discoverResult?.call() ?? const [];
  }

  @override
  Future<List<RosterUser>> followers(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async => followersResult?.call() ?? const [];

  @override
  Future<List<RosterUser>> following(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async => followingResult?.call() ?? const [];

  @override
  Future<UserProfile> me() async =>
      meResult ?? fixtureHost(id: 'me', name: 'Me');

  @override
  Future<UserProfile> updateMe({
    required String name,
    required String city,
    String bio = '',
    List<String> tastes = const [],
  }) async {
    updateMeCalls += 1;
    final base = meResult ?? fixtureHost(id: 'me', name: 'Me');
    return base.copyWith(
      name: name,
      location: city,
      bio: bio,
      interests: tastes,
    );
  }

  /// Mirrors the server's partial `PATCH /users/me`: only the keys actually
  /// sent are merged onto the stored profile; everything else survives.
  @override
  Future<UserProfile> patchSettings(Map<String, dynamic> patch) async {
    patchSettingsCalls += 1;
    lastSettingsPatch = patch;
    final settingsErr = settingsError;
    if (settingsErr != null) throw settingsErr;
    final base = meResult ?? fixtureHost(id: 'me', name: 'Me');
    final instagram = patch['instagram'] as String?;
    return base.copyWith(
      name: patch['name'] as String?,
      handle: patch['handle'] as String?,
      bio: patch['bio'] as String?,
      socialLinks: instagram == null
          ? null
          : instagram.isEmpty
          ? const []
          : [SocialLink(platform: SocialPlatform.instagram, handle: instagram)],
      location: patch['city'] as String?,
      homeArea: patch['homeArea'] as String?,
      interests: patch['tastes'] as List<String>?,
      dietary: patch['dietary'] as List<String>?,
      allergies: patch['allergies'] as List<String>?,
      showFollowList: patch['showFollowList'] as bool?,
      showActivity: patch['showActivity'] as bool?,
      dmFromFollowersOnly: patch['dmFromFollowersOnly'] as bool?,
      allowTagging: patch['allowTagging'] as bool?,
    );
  }

  int uploadAvatarCalls = 0;
  int removeAvatarCalls = 0;
  Uint8List? lastAvatarBytes;

  /// When set, avatar writes throw this instead of succeeding.
  Object? avatarError;

  /// Usernames the advisory pre-check reports as already claimed.
  Set<String> takenHandles = {};
  int handleAvailabilityCalls = 0;
  String? lastHandleQuery;

  @override
  Future<HandleAvailability> handleAvailability(String handle) async {
    handleAvailabilityCalls += 1;
    lastHandleQuery = handle;
    final normalised = handle.trim().toLowerCase();
    final taken = takenHandles.contains(normalised);
    return HandleAvailability(
      handle: normalised,
      available: !taken,
      reason: taken ? 'taken' : null,
    );
  }

  @override
  Future<UserProfile> uploadAvatar(
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    uploadAvatarCalls += 1;
    lastAvatarBytes = bytes;
    onProgress?.call(0.5);
    final e = avatarError;
    if (e != null) throw e;
    onProgress?.call(1);
    final base = meResult ?? fixtureHost(id: 'me', name: 'Me');
    return base.copyWith(
      avatarPath: '/public/avatars/${base.id}?v=$uploadAvatarCalls',
    );
  }

  @override
  Future<UserProfile> removeAvatar() async {
    removeAvatarCalls += 1;
    final e = avatarError;
    if (e != null) throw e;
    final base = meResult ?? fixtureHost(id: 'me', name: 'Me');
    return base.copyWith(clearAvatar: true);
  }

  @override
  Future<HostProfile> profile(String id) async {
    final e = profileError;
    if (e != null) throw e;
    return profileResult ??
        HostProfile(
          user: fixtureHost(id: id),
          hostedUpcoming: const [],
        );
  }

  // ── Account type ──────────────────────────────────────────────────────────

  /// Backs `GET /users/me/account-type`; null means "whatever the signed-in
  /// profile says, with no blockers".
  AccountTypeStatus? accountTypeStatusResult;

  /// When set, [setAccountType] throws this (e.g. the server's 409 while an
  /// upcoming experience is still live).
  Object? accountTypeError;

  int accountTypeStatusCalls = 0;
  int setAccountTypeCalls = 0;
  String? lastAccountType;

  @override
  Future<AccountTypeStatus> accountTypeStatus() async {
    accountTypeStatusCalls += 1;
    final preset = accountTypeStatusResult;
    if (preset != null) return preset;
    final base = meResult ?? fixtureHost(id: 'me', name: 'Me');
    return AccountTypeStatus(accountType: base.accountType);
  }

  @override
  Future<UserProfile> setAccountType(String accountType) async {
    setAccountTypeCalls += 1;
    lastAccountType = accountType;
    final err = accountTypeError;
    if (err != null) throw err;
    final base = meResult ?? fixtureHost(id: 'me', name: 'Me');
    return base.copyWith(
      accountType: accountType,
      // Mirrors the server: going Professional promotes a plain diner 
      // to the host role, going Personal leaves the role alone.
      role: accountType == 'professional' && base.role == 'user'
          ? 'host'
          : base.role,
    );
  }
}

/// A pure-Dart stand-in for [FlutterSecureStorage] so tests never hit the
/// platform channel. Every method is routed through [noSuchMethod] to avoid
/// restating the platform type's long option-parameter signatures.
class InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #read:
        return Future<String?>.value(_data[named[#key] as String]);
      case #write:
        final key = named[#key] as String;
        final value = named[#value] as String?;
        if (value == null) {
          _data.remove(key);
        } else {
          _data[key] = value;
        }
        return Future<void>.value();
      case #delete:
        _data.remove(named[#key] as String);
        return Future<void>.value();
      case #deleteAll:
        _data.clear();
        return Future<void>.value();
      case #containsKey:
        return Future<bool>.value(_data.containsKey(named[#key] as String));
      case #readAll:
        return Future<Map<String, String>>.value(Map<String, String>.of(_data));
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

/// A controllable [SessionRepository]. Successful calls return a [Session]
/// carrying [user] (or a default diner) and the token `fake-token`; when [error]
/// is set every method throws it to exercise the failure path.
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({
    this.user,
    this.error,
    this.tierResponse,
    this.changePasswordError,
    this.emailChangeError,
    this.deleteAccountError,
  });

  UserDto? user;
  Object? error;

  /// Backs [tier]; defaults to an eligible host one claim away from influencer.
  TierDto? tierResponse;

  /// Optional per-endpoint failures for the P1 lifecycle methods, so a test
  /// can exercise "wrong password" without breaking every other call.
  final Object? changePasswordError;
  final Object? emailChangeError;
  final Object? deleteAccountError;

  int meCalls = 0;
  int signUpCalls = 0;
  int loginCalls = 0;
  int signOutCalls = 0;
  int becomeHostCalls = 0;
  int tierCalls = 0;
  int becomeInfluencerCalls = 0;

  int changePasswordCalls = 0;
  String? lastCurrentPassword;
  String? lastNewPassword;
  int requestEmailChangeCalls = 0;
  String? lastRequestedEmail;
  int confirmEmailChangeCalls = 0;
  String? lastConfirmedCode;
  int logoutAllCalls = 0;
  int deleteAccountCalls = 0;
  String? lastDeletePassword;

  UserDto get _dto =>
      user ?? const UserDto(id: 'u1', name: 'Test Diner', role: 'user');

  Session get _session => Session(
    token: 'fake-token',
    user: _dto,
    expiresAt: DateTime.now().add(const Duration(days: 30)),
  );

  @override
  Future<Session> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    signUpCalls += 1;
    _maybeThrow();
    return _session;
  }

  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    loginCalls += 1;
    _maybeThrow();
    return _session;
  }

  @override
  Future<UserDto> me() async {
    meCalls += 1;
    _maybeThrow();
    return _dto;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    _maybeThrow();
  }

  @override
  Future<OtpChallenge> requestOtp(String phone) async {
    _maybeThrow();
    return const OtpChallenge(sent: true, devCode: '123456');
  }

  @override
  Future<Session> verifyOtp({
    required String phone,
    required String code,
  }) async {
    _maybeThrow();
    return _session;
  }

  @override
  Future<Session> signIn(String phone) async {
    _maybeThrow();
    return _session;
  }

  @override
  Future<UserDto> becomeHost() async {
    becomeHostCalls += 1;
    _maybeThrow();
    return UserDto(
      id: _dto.id,
      name: _dto.name,
      handle: _dto.handle,
      city: _dto.city,
      bio: _dto.bio,
      role: 'host',
    );
  }

  @override
  Future<TierDto> tier() async {
    tierCalls += 1;
    _maybeThrow();
    return tierResponse ??
        const TierDto(
          tier: 'host',
          eligible: true,
          progress: {
            'followers': 80,
            'eventsHosted': 4,
            'rating': 4.5,
            'ratingCount': 6,
          },
          thresholds: {
            'minFollowers': 50,
            'minEventsHosted': 3,
            'minRating': 4.0,
            'minRatingCount': 3,
          },
        );
  }

  UserDto _dtoWithEmail(String email) => UserDto(
    id: _dto.id,
    name: _dto.name,
    handle: _dto.handle,
    city: _dto.city,
    bio: _dto.bio,
    followers: _dto.followers,
    following: _dto.following,
    dinnersHosted: _dto.dinnersHosted,
    dinnersJoined: _dto.dinnersJoined,
    rating: _dto.rating,
    reviewCount: _dto.reviewCount,
    avatarUrl: _dto.avatarUrl,
    badges: _dto.badges,
    tastes: _dto.tastes,
    accentHex: _dto.accentHex,
    joinedYear: _dto.joinedYear,
    role: _dto.role,
    isVerified: _dto.isVerified,
    email: email,
    homeArea: _dto.homeArea,
    dietary: _dto.dietary,
    allergies: _dto.allergies,
    showFollowList: _dto.showFollowList,
    showActivity: _dto.showActivity,
    dmFromFollowersOnly: _dto.dmFromFollowersOnly,
    allowTagging: _dto.allowTagging,
  );

  void _maybeThrow({Object? specific}) {
    final e = specific ?? error;
    if (e != null) throw e;
  }

  @override
  Future<UserDto> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls += 1;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    _maybeThrow(specific: changePasswordError);
    return _dto;
  }

  @override
  Future<EmailChangeChallenge> requestEmailChange({
    required String email,
    required String password,
  }) async {
    requestEmailChangeCalls += 1;
    lastRequestedEmail = email;
    _maybeThrow(specific: emailChangeError);
    return EmailChangeChallenge(
      sent: true,
      pendingEmail: email,
      devCode: '654321',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<UserDto> confirmEmailChange({required String code}) async {
    confirmEmailChangeCalls += 1;
    lastConfirmedCode = code;
    _maybeThrow(specific: emailChangeError);
    // Mirror the server: only the minted dev code confirms.
    if (code != '654321') {
      throw const ApiException(
        ApiErrorKind.unauthorized,
        message: 'That code is not right. Try again.',
        statusCode: 401,
      );
    }
    return _dtoWithEmail(lastRequestedEmail ?? 'new@example.com');
  }

  @override
  Future<void> logoutAll() async {
    logoutAllCalls += 1;
    _maybeThrow();
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    deleteAccountCalls += 1;
    lastDeletePassword = password;
    _maybeThrow(specific: deleteAccountError);
  }

  @override
  Future<UserDto> becomeInfluencer() async {
    becomeInfluencerCalls += 1;
    _maybeThrow();
    return UserDto(
      id: _dto.id,
      name: _dto.name,
      handle: _dto.handle,
      city: _dto.city,
      bio: _dto.bio,
      role: 'influencer',
      isVerified: true,
    );
  }
}

/// A controllable [BookingsRepository]. [join] returns [nextBooking] (or a
/// fixture derived from the booked dinner) and records the call so tests can
/// assert checkout fires exactly one join; [mine] backs [getMine].
class FakeBookingsRepository implements BookingsRepository {
  FakeBookingsRepository({this.mine = const [], this.nextBooking, this.error});

  final List<Booking> mine;
  final Booking? nextBooking;
  final Object? error;

  int joinCalls = 0;
  int cancelCalls = 0;
  int checkInCalls = 0;
  int approveCalls = 0;
  int declineCalls = 0;
  int guestsForCalls = 0;
  int refreshSecretCalls = 0;
  String? lastPromo;
  int lastSeats = 0;
  String lastPaymentLabel = Booking.kDefaultPaymentMethod;
  String? lastGuestName;
  String? lastGuestEmail;
  String? lastGuestPhone;
  String? lastApprovedId;
  String? lastDeclinedId;

  void _maybeThrow() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<List<Booking>> getMine(UserProfile currentUser) async {
    _maybeThrow();
    return mine;
  }

  @override
  Future<Booking> join({
    required Dinner dinner,
    required UserProfile user,
    required int seats,
    String? promoCode,
    String paymentLabel = Booking.kDefaultPaymentMethod,
    String? guestName,
    String? guestEmail,
    String? guestPhone,
  }) async {
    _maybeThrow();
    joinCalls += 1;
    lastGuestName = guestName;
    lastGuestEmail = guestEmail;
    lastGuestPhone = guestPhone;
    lastSeats = seats;
    lastPromo = promoCode;
    lastPaymentLabel = paymentLabel;
    return nextBooking ??
        fixtureBooking(
          dinner: dinner,
          user: user,
          seats: seats,
          total: dinner.pricePerSeat * seats,
        );
  }

  @override
  Future<void> cancelBooking(String bookingId) async {
    _maybeThrow();
    cancelCalls += 1;
  }

  @override
  Future<String> refreshPaymentSecret(String bookingId) async {
    _maybeThrow();
    refreshSecretCalls += 1;
    return 'pi_fake_refresh_secret';
  }

  @override
  Future<void> checkIn(String bookingId) async {
    _maybeThrow();
    checkInCalls += 1;
  }

  @override
  Future<List<Booking>> guestsFor(
    String eventId,
    UserProfile currentUser,
  ) async {
    _maybeThrow();
    guestsForCalls += 1;
    return mine;
  }

  /// Approves a pending seat request. Returns a confirmed booking (built from
  /// [nextBooking] when supplied, so a test can drive the reloaded guest list),
  /// mirroring the server's `POST /bookings/:id/approve` ack.
  @override
  Future<Booking> approveRequest(
    String bookingId,
    UserProfile currentUser,
  ) async {
    _maybeThrow();
    approveCalls += 1;
    lastApprovedId = bookingId;
    return nextBooking ??
        fixtureBooking(
          id: bookingId,
          dinner: fixtureDinner(),
          user: currentUser,
          status: BookingStatus.confirmed,
        );
  }

  /// Declines a pending seat request; returns the cancelled booking the host's
  /// guest list re-reads after `POST /bookings/:id/decline`.
  @override
  Future<Booking> declineRequest(
    String bookingId,
    UserProfile currentUser,
  ) async {
    _maybeThrow();
    declineCalls += 1;
    lastDeclinedId = bookingId;
    return nextBooking ??
        fixtureBooking(
          id: bookingId,
          dinner: fixtureDinner(),
          user: currentUser,
          status: BookingStatus.cancelled,
        );
  }
}

/// A controllable [SocialRepository] tracking follow/save toggles and a
/// turnable activity feed.
class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository({
    this.activityItems = const [],
    this.unreadCount = 0,
    this.error,
  });

  final List<Map<String, dynamic>> activityItems;
  final int unreadCount;
  final Object? error;

  final Set<String> following = {};
  final Set<String> saved = {};
  int markReadCalls = 0;

  void _maybeThrow() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<int> follow(String userId) async {
    _maybeThrow();
    following.add(userId);
    return following.length;
  }

  @override
  Future<int> unfollow(String userId) async {
    _maybeThrow();
    following.remove(userId);
    return following.length;
  }

  @override
  Future<Map<String, bool>> followStatus(List<String> ids) async => {
    for (final id in ids) id: following.contains(id),
  };

  @override
  Future<void> saveEvent(String eventId) async {
    _maybeThrow();
    saved.add(eventId);
  }

  @override
  Future<void> unsaveEvent(String eventId) async {
    _maybeThrow();
    saved.remove(eventId);
  }

  @override
  Future<({List<Map<String, dynamic>> items, int unreadCount})>
  activity() async {
    _maybeThrow();
    return (items: activityItems, unreadCount: unreadCount);
  }

  @override
  Future<void> markActivityRead() async {
    _maybeThrow();
    markReadCalls += 1;
  }

  @override
  Future<({List<Map<String, dynamic>> items, int unreadCount})>
  notifications() async {
    _maybeThrow();
    return (items: activityItems, unreadCount: unreadCount);
  }
}

/// A controllable [ChatRepository] that appends sent messages to [threadOf].
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.threads = const {}, this.error});

  final Map<String, List<Map<String, dynamic>>> threads;
  final Object? error;

  int sendCalls = 0;

  void _maybeThrow() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<List<Map<String, dynamic>>> thread(String eventId) async {
    _maybeThrow();
    return threads[eventId] ?? const [];
  }

  @override
  Future<Map<String, dynamic>> send(String eventId, String text) async {
    _maybeThrow();
    sendCalls += 1;
    final msg = {'id': 'm$sendCalls', 'authorId': 'me', 'text': text};
    (threads[eventId] ??= []).add(msg);
    return msg;
  }
}

/// A diner-facing deal fixture for the Offers feed.
Offer fixtureOffer({
  String id = 'o1',
  String name = 'Date Night Tasting',
  String restaurantId = 'r1',
  String restaurantName = 'Skyline Room',
  String city = 'Karachi',
  double pricePerGuest = 120,
  int minGuests = 2,
  String kind = 'couple',
}) => Offer(
  id: id,
  name: name,
  description: 'A mock deal for widget tests.',
  restaurantId: restaurantId,
  restaurantName: restaurantName,
  city: city,
  pricePerGuest: pricePerGuest,
  minGuests: minGuests,
  kind: kind,
);

/// A controllable [OffersRepository]. [feed] records the last query args and
/// returns the supplied offers/promos, or throws [error] for the failure path.
class FakeOffersRepository implements OffersRepository {
  FakeOffersRepository({
    this.offers = const [],
    this.promos = const [],
    this.error,
  });

  final List<Offer> offers;
  final List<PromoCode> promos;
  final Object? error;

  int feedCalls = 0;
  String? lastFeedCity;
  String? lastFeedKind;

  @override
  Future<OfferFeed> feed({String? city, String kind = 'all'}) async {
    final e = error;
    if (e != null) throw e;
    feedCalls += 1;
    lastFeedCity = city;
    lastFeedKind = kind;
    return OfferFeed(offers: offers, promos: promos);
  }
}

/// A collaboration invite fixture with full lifecycle support.
CollaborationInvite fixtureInvite({
  String id = 'i1',
  String title = 'Rooftop Sunset Series',
  bool isAccepted = false,
  String status = 'invited',
  String proposedBy = 'restaurant',
  String? experienceId,
}) => CollaborationInvite(
  id: id,
  restaurant: fixtureRestaurant(id: 'r1', name: 'Skyline Rooftop'),
  title: title,
  message: 'Co-host a seasonal series with us.',
  receivedAt: DateTime.now(),
  isAccepted: isAccepted,
  status: status,
  proposedBy: proposedBy,
  experienceId: experienceId,
);

/// A unified analytics fixture mirroring what the server returns.
HostAnalytics fixtureAnalytics({
  int totalEventsHosted = 4,
  int totalBookings = 28,
  int totalSeatsReserved = 52,
  double grossRevenue = 4200,
  double hostNetEarnings = 3780,
  int seatsSold = 52,
  double averageSeatFillRate = 0.82,
  double averageRating = 4.7,
  int reviewCount = 12,
  int upcomingCount = 2,
  int completedCount = 2,
  int totalViews = 4770,
  double conversionRate = 3.2,
  List<HostEventStat>? topPerformingEvents,
  List<HostTrendPoint>? trend,
  List<HostEventStat>? performance,
}) => HostAnalytics(
  totalEventsHosted: totalEventsHosted,
  totalBookings: totalBookings,
  totalSeatsReserved: totalSeatsReserved,
  grossRevenue: grossRevenue,
  hostNetEarnings: hostNetEarnings,
  seatsSold: seatsSold,
  averageSeatFillRate: averageSeatFillRate,
  averageRating: averageRating,
  reviewCount: reviewCount,
  upcomingCount: upcomingCount,
  completedCount: completedCount,
  totalViews: totalViews,
  conversionRate: conversionRate,
  topPerformingEvents: topPerformingEvents ?? const [],
  trend: trend ?? const [],
  performance: performance ?? const [],
);

/// A discoverable restaurant partner fixture.
DiscoverablePartner fixtureDiscoverablePartner({
  String id = 'dp1',
  String name = 'Sakura Garden',
  String neighborhood = 'Clifton',
  String city = 'Karachi',
  double rating = 4.6,
  int reviewCount = 38,
  List<String> cuisines = const ['Japanese'],
}) => DiscoverablePartner(
  id: id,
  name: name,
  coverImage: null,
  neighborhood: neighborhood,
  city: city,
  rating: rating,
  reviewCount: reviewCount,
  cuisines: cuisines,
);

/// A promotable event fixture.
PromotableEvent fixturePromotableEvent({
  String id = 'pe1',
  String title = 'Chef\u2019s Table Experience',
  String restaurantName = 'Skyline Rooftop',
  int seatsTotal = 12,
  int seatsBooked = 7,
}) => PromotableEvent(
  id: id,
  title: title,
  coverImage: null,
  startAt: DateTime.now().add(const Duration(days: 5)),
  seatsTotal: seatsTotal,
  seatsBooked: seatsBooked,
  seatsLeft: seatsTotal - seatsBooked,
  pricePerSeat: 150,
  restaurantName: restaurantName,
);

/// One analytics row for the host performance list.
HostEventStat fixtureEventStat({
  String eventId = 'e1',
  String title = 'Omakase Under the Stars',
  int views = 2840,
  int bookings = 6,
  int pending = 1,
  int checkedIn = 3,
}) => HostEventStat(
  eventId: eventId,
  title: title,
  coverImage: 'assets/images/dish_sushi.png',
  views: views,
  seatsBooked: bookings,
  bookings: bookings,
  pending: pending,
  checkedIn: checkedIn,
);

/// A controllable [HostsRepository]. Reads return the supplied fixtures; the
/// two writes ([respondToInvite] and [requestWithdrawal]) mutate in-memory
/// state and record their arguments so controller tests can assert the wallet
/// and invitation lifecycle without a network. An over-balance withdrawal
/// throws the same validation [ApiException] the server returns.
class FakeHostsRepository implements HostsRepository {
  FakeHostsRepository({
    this.summaryResult,
    this.payoutRows = const [],
    this.trendPoints = const [],
    this.performanceRows = const [],
    this.partnerRows = const [],
    List<CollaborationInvite> invites = const [],
    double initialAvailable = 0,
    double initialLifetimeNet = 0,
    this.error,
    this.analyticsResult,
    List<CollaborationInvite> collaborations = const [],
    this.discoverablePartners = const [],
    this.promotableEventRows = const [],
    this.followerCount = 240,
  }) : _invites = List<CollaborationInvite>.of(invites),
       _collaborations = List<CollaborationInvite>.of(collaborations),
       _available = initialAvailable,
       _lifetimeNet = initialLifetimeNet;

  final HostSummary? summaryResult;
  final List<HostPayout> payoutRows;
  final List<HostTrendPoint> trendPoints;
  final List<HostEventStat> performanceRows;
  final List<HostPartner> partnerRows;
  final Object? error;

  /// When set, [analytics] returns this instead of a derived default.
  final HostAnalytics? analyticsResult;

  final List<CollaborationInvite> _invites;
  final List<CollaborationInvite> _collaborations;
  final List<DiscoverablePartner> discoverablePartners;
  final List<PromotableEvent> promotableEventRows;
  final int followerCount;
  final List<Withdrawal> _withdrawals = [];
  double _available;
  final double _lifetimeNet;

  int respondCalls = 0;
  int withdrawalCalls = 0;
  String? lastRespondInviteId;
  bool? lastRespondAccept;

  /// The note the host chose to send with a decline, so a test can prove the
  /// app actually asks for one instead of declining silently.
  String? lastRespondReason;
  double? lastWithdrawAmount;
  String? lastWithdrawMethod;

  // ── Collaboration tracking ──────────────────────────────────────────────
  int analyticsCalls = 0;
  String? lastAnalyticsPeriod;
  int collaborationsCalls = 0;
  int sendProposalCalls = 0;
  String? lastProposalRestaurantId;
  String? lastProposalTitle;
  String? lastProposalMessage;

  /// The draft a proposal was sent on top of, for either direction.
  String? lastProposalExperienceId;
  int cancelProposalCalls = 0;
  String? lastCancelCollabId;
  int completeProposalCalls = 0;
  String? lastCompleteCollabId;
  String? lastCompleteExperienceId;
  int discoverPartnersCalls = 0;
  int promotableEventsCalls = 0;
  int promoteEventCalls = 0;
  String? lastPromotedEventId;

  List<CollaborationInvite> get currentInvites => List.unmodifiable(_invites);
  List<CollaborationInvite> get currentCollaborations =>
      List.unmodifiable(_collaborations);
  double get availableBalance => _available;

  void _maybeThrow() {
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<HostSummary> summary(String hostId) async {
    _maybeThrow();
    return summaryResult ??
        HostSummary(
          earned: _lifetimeNet,
          inTransit: 0,
          scheduled: 0,
          netTotal: _lifetimeNet,
          lifetimeGross: _lifetimeNet,
          commissionTotal: 0,
          seatsSold: 0,
          averageSeatPrice: 0,
          hostedCount: performanceRows.length,
          upcomingCount: 0,
          averageFillRate: 0,
          available: _available,
        );
  }

  @override
  Future<List<HostPayout>> payouts(String hostId) async {
    _maybeThrow();
    return payoutRows;
  }

  @override
  Future<List<HostTrendPoint>> trend(String hostId) async {
    _maybeThrow();
    return trendPoints;
  }

  @override
  Future<List<HostEventStat>> performance(String hostId) async {
    _maybeThrow();
    return performanceRows;
  }

  @override
  Future<List<HostPartner>> partners(String hostId) async {
    _maybeThrow();
    return partnerRows;
  }

  @override
  Future<List<CollaborationInvite>> invites(String hostId) async {
    _maybeThrow();
    return List.unmodifiable(_invites);
  }

  @override
  Future<CollaborationInvite> respondToInvite(
    String hostId,
    String inviteId,
    bool accept, {
    String? reason,
  }) async {
    _maybeThrow();
    respondCalls += 1;
    lastRespondInviteId = inviteId;
    lastRespondAccept = accept;
    lastRespondReason = reason;
    final index = _invites.indexWhere((i) => i.id == inviteId);
    if (index == -1) throw StateError('unknown invite $inviteId');
    final flipped = _invites[index].copyWith(isAccepted: accept);
    _invites[index] = flipped;
    return flipped;
  }

  @override
  Future<Wallet> wallet(String hostId) async {
    _maybeThrow();
    return _wallet();
  }

  @override
  Future<Wallet> requestWithdrawal({
    required String hostId,
    required double amount,
    required String method,
  }) async {
    _maybeThrow();
    withdrawalCalls += 1;
    lastWithdrawAmount = amount;
    lastWithdrawMethod = method;
    if (amount > _available) {
      throw ApiException(
        ApiErrorKind.validation,
        message: 'Amount exceeds available balance',
      );
    }
    _available -= amount;
    _withdrawals.insert(
      0,
      Withdrawal(
        id: 'w${_withdrawals.length + 1}',
        amount: amount,
        method: method,
        status: 'requested',
        date: DateTime.now(),
      ),
    );
    return _wallet();
  }

  Wallet _wallet() => Wallet(
    available: _available,
    lifetimeNet: _lifetimeNet,
    pendingWithdrawals: _withdrawals.fold(0, (sum, w) => sum + w.amount),
    withdrawals: List.unmodifiable(_withdrawals),
  );

  // ── Phase 2: Analytics ──────────────────────────────────────────────────

  @override
  Future<HostAnalytics> analytics(String hostId, {String period = 'all'}) async {
    _maybeThrow();
    analyticsCalls += 1;
    lastAnalyticsPeriod = period;
    return analyticsResult ??
        fixtureAnalytics(
          performance: performanceRows,
          trend: trendPoints,
          topPerformingEvents: performanceRows,
        );
  }

  // ── Phase 3: Collaborations ─────────────────────────────────────────────

  @override
  Future<List<CollaborationInvite>> collaborations(String hostId) async {
    _maybeThrow();
    collaborationsCalls += 1;
    // Merge invites + collaborations for a unified view.
    final seen = <String>{};
    final merged = <CollaborationInvite>[];
    for (final c in _collaborations) {
      if (seen.add(c.id)) merged.add(c);
    }
    for (final i in _invites) {
      if (seen.add(i.id)) merged.add(i);
    }
    return merged;
  }

  @override
  Future<CollaborationInvite> sendProposal({
    required String hostId,
    required String restaurantId,
    required String title,
    required String message,
    String? experienceId,
  }) async {
    _maybeThrow();
    sendProposalCalls += 1;
    lastProposalRestaurantId = restaurantId;
    lastProposalTitle = title;
    lastProposalMessage = message;
    lastProposalExperienceId = experienceId;
    final invite = fixtureInvite(
      id: 'new-proposal',
      title: title,
      status: 'invited',
      proposedBy: 'host',
      experienceId: experienceId,
    );
    _collaborations.add(invite);
    return invite;
  }

  @override
  Future<CollaborationInvite> cancelProposal({
    required String hostId,
    required String collabId,
  }) async {
    _maybeThrow();
    cancelProposalCalls += 1;
    lastCancelCollabId = collabId;
    final index = _collaborations.indexWhere((c) => c.id == collabId);
    if (index == -1) {
      // Return a synthetic cancelled invite if not found in local state.
      return fixtureInvite(
        id: collabId,
        status: 'cancelled',
        proposedBy: 'host',
      );
    }
    final updated = _collaborations[index].copyWith(
      status: 'cancelled',
      isAccepted: false,
    );
    _collaborations[index] = updated;
    return updated;
  }

  @override
  Future<CollaborationInvite> completeProposal({
    required String hostId,
    required String collabId,
    String? experienceId,
  }) async {
    _maybeThrow();
    completeProposalCalls += 1;
    lastCompleteCollabId = collabId;
    lastCompleteExperienceId = experienceId;
    final index = _collaborations.indexWhere((c) => c.id == collabId);
    if (index == -1) {
      return fixtureInvite(
        id: collabId,
        status: 'completed',
        proposedBy: 'host',
        experienceId: 'exp-$collabId',
      );
    }
    final updated = _collaborations[index].copyWith(
      status: 'completed',
      experienceId: 'exp-$collabId',
    );
    _collaborations[index] = updated;
    return updated;
  }

  // ── Phase 3: Discovery & Promote ────────────────────────────────────────

  @override
  Future<List<DiscoverablePartner>> discoverPartners(String hostId) async {
    _maybeThrow();
    discoverPartnersCalls += 1;
    return discoverablePartners;
  }

  @override
  Future<({List<PromotableEvent> events, int followerCount})> promotableEvents(
    String hostId,
  ) async {
    _maybeThrow();
    promotableEventsCalls += 1;
    return (events: promotableEventRows, followerCount: followerCount);
  }

  @override
  Future<void> promoteEvent(String hostId, String eventId) async {
    _maybeThrow();
    promoteEventCalls += 1;
    lastPromotedEventId = eventId;
  }
}

// ── Fake LocationRepository ────────────────────────────────────────────────

class FakeLocationRepository implements LocationRepository {
  List<SavedLocation> _saved = [];
  final List<ServiceCity> _cities;

  FakeLocationRepository({
    List<ServiceCity>? cities,
    List<SavedLocation>? initial,
  }) : _cities = cities ?? const [],
       _saved = initial ?? [];

  @override
  Future<List<ServiceCity>> supportedCities() async => _cities;

  @override
  Future<List<SavedLocation>> savedLocations() async => _saved;

  @override
  Future<SavedLocation> saveLocation(SavedLocation location) async {
    _saved = [..._saved.where((l) => l.id != location.id), location];
    return location;
  }

  @override
  Future<void> deleteLocation(String id) async {
    _saved = _saved.where((l) => l.id != id).toList();
  }
}

// ── Fake SafetyRepository ──────────────────────────────────────────────────

class FakeSafetyRepository implements SafetyRepository {
  FakeSafetyRepository({
    this.blocked = const [],
    this.reports = const [],
    this.feedback = const [],
  });

  final List<BlockedUser> blocked;
  final List<ReportItem> reports;
  final List<FeedbackItem> feedback;

  int blockCalls = 0;
  int unblockCalls = 0;
  int reportCalls = 0;
  int feedbackCalls = 0;

  @override
  Future<int> block(String userId) async {
    blockCalls++;
    return 0;
  }

  @override
  Future<void> unblock(String userId) async {
    unblockCalls++;
  }

  @override
  Future<List<BlockedUser>> blockedUsers() async => blocked;

  @override
  Future<ReportItem> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String description = '',
  }) async {
    reportCalls++;
    return ReportItem(
      id: 'r_new',
      reference: 'RP-TEST',
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      description: description,
      status: ReportStatus.pending,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<ReportItem>> myReports() async => reports;

  @override
  Future<FeedbackItem> submitFeedback({
    required FeedbackCategory category,
    required String subject,
    required String description,
    String relatedRef = '',
  }) async {
    feedbackCalls++;
    return FeedbackItem(
      id: 'f_new',
      ticket: 'FB-TEST',
      category: category,
      subject: subject,
      description: description,
      relatedRef: relatedRef,
      status: FeedbackStatus.open,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<List<FeedbackItem>> myFeedback() async => feedback;
}

// ── Universal search ───────────────────────────────────────────────────────

/// A live-shaped deal. [endsAt] defaults a week out so `isActive` holds.
Deal fixtureDeal({
  String id = 'd1',
  String restaurantId = 'r1',
  String restaurantName = 'Skyline Room',
  String title = '20% off dinner',
  String description = 'Weeknight dinner for two',
  String kind = 'percent',
  double value = 20,
  DateTime? endsAt,
  String? city = 'Karachi',
  String? coverImage = 'assets/images/dish_steak.png',
}) => Deal(
  id: id,
  restaurantId: restaurantId,
  restaurantName: restaurantName,
  title: title,
  description: description,
  kind: kind,
  value: value,
  startsAt: DateTime.now().subtract(const Duration(days: 1)),
  endsAt: endsAt ?? DateTime.now().add(const Duration(days: 7)),
  city: city,
  coverImage: coverImage,
);

/// A cross-venue dish hit, mirroring `SearchResponseDto.menu[i]`.
MenuItemHit fixtureMenuItem({
  String id = 'm1',
  String name = 'Truffle Sushi',
  String restaurantId = 'r1',
  String restaurantName = 'Skyline Room',
  String sectionName = 'Sushi',
  double price = 1450,
  String photoUrl = 'assets/images/dish_sushi.png',
  String neighborhood = 'Clifton',
  String city = 'Karachi',
}) => MenuItemHit(
  id: id,
  name: name,
  restaurantId: restaurantId,
  restaurantName: restaurantName,
  sectionName: sectionName,
  price: price,
  photoUrl: photoUrl,
  restaurantNeighborhood: neighborhood,
  restaurantCity: city,
);

/// A controllable [SearchRepository].
///
/// Fixtures page locally so "load more" exercises the same append path as the
/// endpoint, and every call is counted so the debounce, the no-refetch and the
/// retry guarantees are all assertable.
class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({
    this.restaurants = const [],
    this.menu = const [],
    this.deals = const [],
    this.experiences = const [],
    this.hosts = const [],
    this.suggestions = const [],
    this.error,
  });

  final List<Restaurant> restaurants;
  final List<MenuItemHit> menu;
  final List<Deal> deals;
  final List<Dinner> experiences;
  final List<UserProfile> hosts;
  final List<SearchSuggestion> suggestions;

  /// When set, every call rethrows it (drives the error + retry tests).
  final Object? error;

  int searchCalls = 0;
  int suggestCalls = 0;
  SearchFilters? lastFilters;
  int lastPage = 0;

  /// Makes exactly the next `search` call fail, then recovers.
  bool failNext = false;

  @override
  Future<SearchResults> search(
    SearchFilters filters, {
    Set<SearchCategory> categories = const {
      SearchCategory.restaurants,
      SearchCategory.menu,
      SearchCategory.deals,
      SearchCategory.experiences,
      SearchCategory.hosts,
    },
    int page = 1,
    int limit = 10,
  }) async {
    searchCalls++;
    lastFilters = filters;
    lastPage = page;
    if (failNext) {
      failNext = false;
      throw const ApiException(
        ApiErrorKind.network,
        message: 'Could not reach DineCircle.',
      );
    }
    if (error != null) throw error!;

    final offset = (page - 1) * limit;
    List<T> slice<T>(List<T> all) => all.skip(offset).take(limit).toList();
    bool more(int total, int returned) => offset + returned < total;

    final pageRestaurants = slice(restaurants);
    final pageMenu = slice(menu);
    final pageDeals = slice(deals);
    final pageExperiences = slice(experiences);
    final pageHosts = slice(hosts);

    return SearchResults(
      query: filters.query,
      page: page,
      limit: limit,
      restaurants: pageRestaurants,
      menuItems: pageMenu,
      deals: pageDeals,
      experiences: pageExperiences,
      hosts: pageHosts,
      counts: {
        SearchCategory.restaurants: restaurants.length,
        SearchCategory.menu: menu.length,
        SearchCategory.deals: deals.length,
        SearchCategory.experiences: experiences.length,
        SearchCategory.hosts: hosts.length,
      },
      hasMore: {
        SearchCategory.restaurants: more(
          restaurants.length,
          pageRestaurants.length,
        ),
        SearchCategory.menu: more(menu.length, pageMenu.length),
        SearchCategory.deals: more(deals.length, pageDeals.length),
        SearchCategory.experiences: more(
          experiences.length,
          pageExperiences.length,
        ),
        SearchCategory.hosts: more(hosts.length, pageHosts.length),
      },
    );
  }

  @override
  Future<List<SearchSuggestion>> suggest(String query) async {
    suggestCalls++;
    if (error != null) throw error!;
    final term = query.trim().toLowerCase();
    return suggestions
        .where((row) => row.text.toLowerCase().contains(term))
        .toList();
  }
}

/// A server-backed deals feed: [query] filters the whole fixture set, exactly
/// as `/api/deals?q=` does, so a match beyond the first page is still found.
class FakeDealsRepository implements DealsRepository {
  FakeDealsRepository({this.deals = const [], this.error});

  final List<Deal> deals;
  final Object? error;

  int feedCalls = 0;
  String? lastCity;
  String? lastKind;
  String? lastQuery;

  @override
  Future<List<Deal>> feed({String? city, String? kind, String? query}) async {
    feedCalls++;
    lastCity = city;
    lastKind = kind;
    lastQuery = query;
    if (error != null) throw error!;
    final term = (query ?? '').trim().toLowerCase();
    final typed = kind == null || kind.isEmpty
        ? deals
        : deals.where((deal) => deal.kind == kind).toList();
    if (term.isEmpty) return typed;
    return typed
        .where(
          (deal) =>
              deal.title.toLowerCase().contains(term) ||
              deal.restaurantName.toLowerCase().contains(term) ||
              deal.description.toLowerCase().contains(term),
        )
        .toList();
  }

  @override
  Future<List<Deal>> forRestaurant(String restaurantId) async =>
      deals.where((deal) => deal.restaurantId == restaurantId).toList();
}

// Stand-in for a suggestions fixture.
SearchSuggestion fixtureSuggestion(
  String text, {
  SuggestionKind kind = SuggestionKind.restaurant,
  String? refId,
}) => SearchSuggestion(text: text, kind: kind, refId: refId);
