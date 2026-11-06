import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/booking.dart';
import '../models/host_models.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';
import 'users_provider.dart';

/// Headline earnings + activity for a host (`GET /hosts/:id/summary`).
final hostSummaryProvider = FutureProvider.family<HostSummary, String>(
  (ref, hostId) => ref.watch(hostsRepositoryProvider).summary(hostId),
);

/// The signed-in host's own summary. Null id → never resolves to a network call.
final myHostSummaryProvider = FutureProvider<HostSummary?>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return null;
  return ref.watch(hostSummaryProvider(id).future);
});

/// One earnings line per hosted event (`GET /hosts/:id/payouts`).
final hostPayoutsProvider = FutureProvider.family<List<HostPayout>, String>(
  (ref, hostId) => ref.watch(hostsRepositoryProvider).payouts(hostId),
);

final myHostPayoutsProvider = FutureProvider<List<HostPayout>>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const [];
  return ref.watch(hostPayoutsProvider(id).future);
});

/// Net revenue / seats per month (`GET /hosts/:id/trend`).
final hostTrendProvider = FutureProvider.family<List<HostTrendPoint>, String>(
  (ref, hostId) => ref.watch(hostsRepositoryProvider).trend(hostId),
);

final myHostTrendProvider = FutureProvider<List<HostTrendPoint>>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const [];
  return ref.watch(hostTrendProvider(id).future);
});

/// A host's guest list for one event (`GET /bookings?eventId=`). Server
/// restricts this to the event's host, so non-owners get an error the caller
/// surfaces rather than another host's bookings.
final eventGuestsProvider = FutureProvider.family<List<Booking>, String>((
  ref,
  eventId,
) {
  final me = ref.watch(currentUserProvider);
  if (me == null) return const [];
  return ref.watch(bookingsRepositoryProvider).guestsFor(eventId, me);
});

/// Per-event analytics rows (`GET /hosts/:id/performance`).
final hostPerformanceProvider =
    FutureProvider.family<List<HostEventStat>, String>(
      (ref, hostId) => ref.watch(hostsRepositoryProvider).performance(hostId),
    );

final myHostPerformanceProvider = FutureProvider<List<HostEventStat>>((
  ref,
) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const [];
  return ref.watch(hostPerformanceProvider(id).future);
});

/// eventId → pending guest-request count, derived from the live performance
/// rows so the Events-tab badge needs no `MockData.pendingRequestsFor`.
final myHostPendingRequestsProvider = Provider<Map<String, int>>((ref) {
  final stats = ref.watch(myHostPerformanceProvider).valueOrNull ?? const [];
  return {
    for (final s in stats)
      if (s.pending > 0) s.eventId: s.pending,
  };
});

/// Venues the host has held tables at (`GET /hosts/:id/partners`).
final hostPartnersProvider = FutureProvider.family<List<HostPartner>, String>(
  (ref, hostId) => ref.watch(hostsRepositoryProvider).partners(hostId),
);

final myHostPartnersProvider = FutureProvider<List<HostPartner>>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const [];
  return ref.watch(hostPartnersProvider(id).future);
});

/// Collaboration invitations (`GET /hosts/:id/invites`).
final hostInvitesProvider =
    FutureProvider.family<List<CollaborationInvite>, String>(
      (ref, hostId) => ref.watch(hostsRepositoryProvider).invites(hostId),
    );

final myHostInvitesProvider = FutureProvider<List<CollaborationInvite>>((
  ref,
) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const [];
  return ref.watch(hostInvitesProvider(id).future);
});

/// The host's simulated wallet ledger (`GET /hosts/:id/wallet`).
final hostWalletProvider = FutureProvider.family<Wallet?, String>(
  (ref, hostId) => ref.watch(hostsRepositoryProvider).wallet(hostId),
);

final myWalletProvider = FutureProvider<Wallet?>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return null;
  return ref.watch(hostWalletProvider(id).future);
});

/// The signed-in host's withdrawal history, derived from [myWalletProvider].
final myHostWithdrawalsProvider = Provider<List<Withdrawal>>((ref) {
  return ref.watch(myWalletProvider).valueOrNull?.withdrawals ?? const [];
});

// ── Phase 2: Analytics ──────────────────────────────────────────────────────

/// Period filter state for the analytics screen.
final analyticsPeriodProvider = StateProvider<String>((ref) => '30d');

/// Unified analytics for a host + period (`GET /hosts/:id/analytics?period=`).
final hostAnalyticsProvider =
    FutureProvider.family<HostAnalytics, ({String hostId, String period})>(
  (ref, params) =>
      ref.watch(hostsRepositoryProvider).analytics(params.hostId, period: params.period),
);

/// The signed-in host's own analytics, driven by [analyticsPeriodProvider].
final myHostAnalyticsProvider = FutureProvider<HostAnalytics?>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return null;
  final period = ref.watch(analyticsPeriodProvider);
  return ref.watch(hostAnalyticsProvider((hostId: id, period: period)).future);
});

// ── Phase 3: Collaborations ─────────────────────────────────────────────────

/// All collaborations (incoming + outgoing) for a host.
final hostCollaborationsProvider =
    FutureProvider.family<List<CollaborationInvite>, String>(
  (ref, hostId) =>
      ref.watch(hostsRepositoryProvider).collaborations(hostId),
);

final myHostCollaborationsProvider =
    FutureProvider<List<CollaborationInvite>>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const [];
  return ref.watch(hostCollaborationsProvider(id).future);
});

/// Discoverable verified partner restaurants for a host.
final hostDiscoverPartnersProvider =
    FutureProvider.family<List<DiscoverablePartner>, String>(
  (ref, hostId) =>
      ref.watch(hostsRepositoryProvider).discoverPartners(hostId),
);

final myHostDiscoverPartnersProvider =
    FutureProvider<List<DiscoverablePartner>>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return const [];
  return ref.watch(hostDiscoverPartnersProvider(id).future);
});

/// Promotable events + follower count for a host.
final hostPromotableEventsProvider = FutureProvider.family<
    ({List<PromotableEvent> events, int followerCount}), String>(
  (ref, hostId) =>
      ref.watch(hostsRepositoryProvider).promotableEvents(hostId),
);

final myHostPromotableEventsProvider =
    FutureProvider<({List<PromotableEvent> events, int followerCount})>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) return (events: <PromotableEvent>[], followerCount: 0);
  return ref.watch(hostPromotableEventsProvider(id).future);
});
