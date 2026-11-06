import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/conversations_repository.dart';
import '../repositories/deals_repository.dart';
import '../repositories/events_repository.dart';
import '../repositories/hosts_repository.dart';
import '../repositories/offers_repository.dart';
import '../repositories/restaurants_repository.dart';
import '../repositories/safety_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/social_repository.dart';
import '../repositories/location_repository.dart';
import '../repositories/reservations_repository.dart';
import '../repositories/search_repository.dart';
import '../repositories/public_menu_repository.dart';
import '../repositories/restaurant_reviews_repository.dart';
import '../repositories/users_repository.dart';
import 'session_provider.dart';

/// Secure key-value store used to persist the bearer token.
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

/// The single shared HTTP client. Widget tests override the repository
/// providers below rather than this, so no test ever touches the network.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  client.onUnauthorized = () =>
      ref.read(sessionControllerProvider.notifier).handleUnauthorized();
  return client;
});

// ── Repositories (interface type → Dio-backed impl) ──────────────────────────

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => ApiSessionRepository(ref.watch(apiClientProvider)),
);

final eventsRepositoryProvider = Provider<EventsRepository>(
  (ref) => ApiEventsRepository(ref.watch(apiClientProvider)),
);

final restaurantsRepositoryProvider = Provider<RestaurantsRepository>(
  (ref) => ApiRestaurantsRepository(ref.watch(apiClientProvider)),
);

final offersRepositoryProvider = Provider<OffersRepository>(
  (ref) => ApiOffersRepository(ref.watch(apiClientProvider)),
);

final dealsRepositoryProvider = Provider<DealsRepository>(
  (ref) => ApiDealsRepository(ref.watch(apiClientProvider)),
);

final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => ApiUsersRepository(ref.watch(apiClientProvider)),
);

final bookingsRepositoryProvider = Provider<BookingsRepository>(
  (ref) => ApiBookingsRepository(ref.watch(apiClientProvider)),
);

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => ApiSocialRepository(ref.watch(apiClientProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ApiChatRepository(ref.watch(apiClientProvider)),
);

final conversationsRepositoryProvider = Provider<ConversationsRepository>(
  (ref) => ApiConversationsRepository(ref.watch(apiClientProvider)),
);

final hostsRepositoryProvider = Provider<HostsRepository>(
  (ref) => ApiHostsRepository(ref.watch(apiClientProvider)),
);

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => ApiSafetyRepository(ref.watch(apiClientProvider)),
);

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => ApiLocationRepository(ref.watch(apiClientProvider)),
);

final reservationsRepositoryProvider = Provider<ReservationsRepository>(
  (ref) => ApiReservationsRepository(ref.watch(apiClientProvider)),
);

final publicMenuRepositoryProvider = Provider<PublicMenuRepository>(
  (ref) => ApiPublicMenuRepository(ref.watch(apiClientProvider)),
);

final restaurantReviewsRepositoryProvider = Provider<RestaurantReviewsRepository>(
  (ref) => ApiRestaurantReviewsRepository(ref.watch(apiClientProvider)),
);

/// Universal search (`/search` + `/search/suggest`).
final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => ApiSearchRepository(ref.watch(apiClientProvider)),
);
