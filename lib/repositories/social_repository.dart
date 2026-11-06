import '../api/api_client.dart';
import '../api/json.dart';

/// Follows, saves and the activity (notifications) feed.
///
/// All of these are real server-backed writes from Phase 3 onward: counters
/// and notifications are maintained in PostgreSQL, so the UI never has to
/// fake a toggle again.
abstract class SocialRepository {
  Future<int> follow(String userId);
  Future<int> unfollow(String userId);

  /// Batched viewer-relative follow state (`GET /social/follow-status`).
  /// Returns `{ userId: bool }` for every id passed in.
  Future<Map<String, bool>> followStatus(List<String> ids);

  Future<void> saveEvent(String eventId);
  Future<void> unsaveEvent(String eventId);

  /// `{ activity: [...], unreadCount: n }` from `GET /activity`.
  Future<({List<Map<String, dynamic>> items, int unreadCount})> activity();

  /// Marks every activity item read (`POST /activity/read`).
  Future<void> markActivityRead();

  /// `{ notifications: [...], unreadCount: n }` from
  /// `GET /users/me/notifications`.
  Future<({List<Map<String, dynamic>> items, int unreadCount})> notifications();
}

class ApiSocialRepository implements SocialRepository {
  ApiSocialRepository(this._client);

  final ApiClient _client;

  @override
  Future<int> follow(String userId) async {
    final body = await _client.postJson('/users/$userId/follow');
    return asInt(asMap(body)['followers']);
  }

  @override
  Future<int> unfollow(String userId) async {
    final body = await _client.deleteJson('/users/$userId/follow');
    return asInt(asMap(body)['followers']);
  }

  @override
  Future<Map<String, bool>> followStatus(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final body = await _client.getJson(
      '/social/follow-status',
      query: {'ids': ids.join(',')},
    );
    final statuses = asMap(asMap(body)['statuses']);
    return {for (final id in ids) id: asBool(statuses[id])};
  }

  @override
  Future<void> saveEvent(String eventId) =>
      _client.postJson('/events/$eventId/save');

  @override
  Future<void> unsaveEvent(String eventId) =>
      _client.deleteJson('/events/$eventId/save');

  @override
  Future<({List<Map<String, dynamic>> items, int unreadCount})>
  activity() async {
    final body = asMap(await _client.getJson('/activity'));
    return (
      items: asMapList(body['activity']),
      unreadCount: asInt(body['unreadCount']),
    );
  }

  @override
  Future<void> markActivityRead() => _client.postJson('/activity/read');

  @override
  Future<({List<Map<String, dynamic>> items, int unreadCount})>
  notifications() async {
    final body = asMap(await _client.getJson('/users/me/notifications'));
    return (
      items: asMapList(body['notifications']),
      unreadCount: asInt(body['unreadCount']),
    );
  }
}
