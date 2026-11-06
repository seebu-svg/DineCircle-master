import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/safety.dart';
import 'api_client_provider.dart';
import 'session_provider.dart';

/// P2 Safety & Trust read providers.
///
/// Lists are always server-authoritative: screens call these, and after a
/// successful block/report/feedback write the caller invalidates the relevant
/// provider so the next read re-fetches from PostgreSQL.

/// Accounts the signed-in user has blocked (`GET /users/me/blocked`).
final blockedUsersProvider = FutureProvider<List<BlockedUser>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref.watch(safetyRepositoryProvider).blockedUsers();
});

/// The user's own submitted reports with live statuses.
final myReportsProvider = FutureProvider<List<ReportItem>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref.watch(safetyRepositoryProvider).myReports();
});

/// The user's own support tickets with live statuses.
final myFeedbackProvider = FutureProvider<List<FeedbackItem>>((ref) async {
  if (!ref.watch(authReadyProvider)) return const [];
  return ref.watch(safetyRepositoryProvider).myFeedback();
});
