import '../api/api_client.dart';
import '../api/json.dart';

/// Event-group chat over the REST endpoints (`/events/:id/messages`).
///
/// Phase 3 deliberately polls instead of holding a Socket.IO connection; the
/// server rooms are ready for a realtime client in Phase 3b.
abstract class ChatRepository {
  /// Raw message maps, oldest first. Server enforces host/booked-guest
  /// membership, so a 403 here means the viewer is not in the thread.
  Future<List<Map<String, dynamic>>> thread(String eventId);

  Future<Map<String, dynamic>> send(String eventId, String text);
}

class ApiChatRepository implements ChatRepository {
  ApiChatRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Map<String, dynamic>>> thread(String eventId) async {
    final body = await _client.getJson('/events/$eventId/messages');
    return asMapList(asMap(body)['messages']);
  }

  @override
  Future<Map<String, dynamic>> send(String eventId, String text) async {
    final body = await _client.postJson(
      '/events/$eventId/messages',
      body: {'text': text},
    );
    return asMap(asMap(body)['message']);
  }
}
