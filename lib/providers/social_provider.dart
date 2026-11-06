import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/mappers/mappers.dart';
import '../models/dinner.dart';
import '../models/notification_item.dart';
import '../repositories/social_repository.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';

/// The events the signed-in user has bookmarked (`GET /me/saved`).
final savedEventsProvider = FutureProvider<List<Dinner>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  final rows = await ref.watch(eventsRepositoryProvider).savedEvents();
  return rows.map(Mappers.dinnerFromSavedRow).toList();
});

/// Whether a given event is in the signed-in user's saved list. Derives from
/// [savedEventsProvider] so save/unsave invalidate the source and every card
/// re-renders from the authoritative server state.
final isSavedProvider = Provider.family<bool, String>((ref, eventId) {
  final saved = ref.watch(savedEventsProvider).valueOrNull ?? const <Dinner>[];
  return saved.any((d) => d.id == eventId);
});

/// The activity (notifications) feed, newest first.
/// Kept for backward compatibility — new code should use [notificationsProvider].
final activityProvider = FutureProvider<List<NotificationItem>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  final result = await ref.watch(socialRepositoryProvider).activity();
  return result.items.map(Mappers.notificationFromActivityRow).toList();
});

/// Unified notifications feed — unions activity, reminders and offers
/// (`GET /users/me/notifications`).
final notificationsProvider = FutureProvider<List<NotificationItem>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  final result = await ref.watch(socialRepositoryProvider).notifications();
  return result.items.map(Mappers.notificationFromUnifiedRow).toList();
});

/// Count of unread activity items — drives the Home bell badge.
final unreadActivityCountProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(authReadyProvider)) return 0;
  final result = await ref.watch(socialRepositoryProvider).activity();
  return result.unreadCount;
});

/// Mutation surface for saves and marking activity read. Each call
/// hits the server then invalidates the affected read providers so the UI
/// re-renders from the authoritative response — no optimistic fakes.
class SocialController {
  SocialController(this._ref);

  final Ref _ref;

  SocialRepository get _repo => _ref.read(socialRepositoryProvider);

  Future<void> save(String eventId) async {
    await _repo.saveEvent(eventId);
    _ref.invalidate(savedEventsProvider);
  }

  Future<void> unsave(String eventId) async {
    await _repo.unsaveEvent(eventId);
    _ref.invalidate(savedEventsProvider);
  }

  /// Marks every activity item read and refreshes the badge/feed.
  Future<void> markAllRead() async {
    await _repo.markActivityRead();
    _ref.invalidate(unreadActivityCountProvider);
    _ref.invalidate(activityProvider);
  }
}

final socialControllerProvider = Provider<SocialController>(
  (ref) => SocialController(ref),
);
