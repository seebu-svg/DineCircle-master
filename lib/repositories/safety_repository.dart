import '../api/api_client.dart';
import '../api/json.dart';
import '../models/safety.dart';

/// P2 Safety & Trust: blocks, reports and support feedback.
///
/// Every method hits a real endpoint from Phase 2 of the backend work,
/// blocking rules, report duplicate guards and feedback tickets are all
/// enforced server-side, so the client never has to fake or optimise state.
abstract class SafetyRepository {
  /// Blocks [userId]; returns how many mutual follows the server removed.
  Future<int> block(String userId);
  Future<void> unblock(String userId);

  /// Accounts the signed-in user has blocked (`GET /users/me/blocked`).
  Future<List<BlockedUser>> blockedUsers();

  /// Files a report and returns it, including the `RP-…` reference shown to
  /// the user as confirmation.
  Future<ReportItem> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String description = '',
  });

  Future<List<ReportItem>> myReports();

  /// Files a support ticket and returns it, including the `FB-…` ticket.
  Future<FeedbackItem> submitFeedback({
    required FeedbackCategory category,
    required String subject,
    required String description,
    String relatedRef = '',
  });

  Future<List<FeedbackItem>> myFeedback();
}

class ApiSafetyRepository implements SafetyRepository {
  ApiSafetyRepository(this._client);

  final ApiClient _client;

  @override
  Future<int> block(String userId) async {
    final body = await _client.postJson('/users/$userId/block');
    return asInt(asMap(body)['removedFollows']);
  }

  @override
  Future<void> unblock(String userId) =>
      _client.deleteJson('/users/$userId/block');

  @override
  Future<List<BlockedUser>> blockedUsers() async {
    final body = asMap(await _client.getJson('/users/me/blocked'));
    return asMapList(body['blocked']).map(BlockedUser.fromMap).toList();
  }

  @override
  Future<ReportItem> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String description = '',
  }) async {
    final body = await _client.postJson(
      '/reports',
      body: {
        'targetType': targetType.wire,
        'targetId': targetId,
        'reason': reason.wire,
        'description': description,
      },
    );
    return ReportItem.fromMap(asMap(asMap(body)['report']));
  }

  @override
  Future<List<ReportItem>> myReports() async {
    final body = asMap(await _client.getJson('/users/me/reports'));
    return asMapList(body['reports']).map(ReportItem.fromMap).toList();
  }

  @override
  Future<FeedbackItem> submitFeedback({
    required FeedbackCategory category,
    required String subject,
    required String description,
    String relatedRef = '',
  }) async {
    final body = await _client.postJson(
      '/feedback',
      body: {
        'category': category.wire,
        'subject': subject,
        'description': description,
        'relatedRef': relatedRef,
      },
    );
    return FeedbackItem.fromMap(asMap(asMap(body)['feedback']));
  }

  @override
  Future<List<FeedbackItem>> myFeedback() async {
    final body = asMap(await _client.getJson('/users/me/feedback'));
    return asMapList(body['feedback']).map(FeedbackItem.fromMap).toList();
  }
}
