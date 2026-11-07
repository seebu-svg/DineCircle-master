import '../api/api_client.dart';
import '../api/json.dart';

/// Conversations API, covers the full messaging surface: listing, DM creation,
/// message history, send, read receipts, typing indicators, edit, delete.
abstract class ConversationsRepository {
  /// List the signed-in user's conversations (newest activity first).
  Future<Map<String, dynamic>> listConversations({
    int page = 1,
    int limit = 20,
    String search = '',
    String kind = '',
  });

  /// Create (or retrieve the existing) direct conversation with [otherUserId].
  Future<Map<String, dynamic>> getOrCreateDirect(String otherUserId);

  /// Paginated message history for a conversation.
  Future<List<Map<String, dynamic>>> messages(
    String conversationId, {
    String? before,
    int limit = 50,
  });

  /// Send a message in [conversationId].
  Future<Map<String, dynamic>> sendMessage(
    String conversationId,
    String text, {
    String? parentId,
  });

  /// Mark all messages in [conversationId] as read for the caller.
  Future<void> markRead(String conversationId);

  /// Leave [conversationId] (sets left_at on the participant row).
  Future<void> leave(String conversationId);

  /// Edit a message the caller authored (15-minute window).
  Future<Map<String, dynamic>> editMessage(String messageId, String text);

  /// Soft-delete a message the caller authored.
  Future<void> deleteMessage(String messageId);

  /// Broadcast typing status in [conversationId].
  Future<void> setTyping(String conversationId, bool typing);

  /// Fetch the current typers for [conversationId].
  Future<List<Map<String, dynamic>>> getTypers(String conversationId);
}

class ApiConversationsRepository implements ConversationsRepository {
  ApiConversationsRepository(this._client);

  final ApiClient _client;

  @override
  Future<Map<String, dynamic>> listConversations({
    int page = 1,
    int limit = 20,
    String search = '',
    String kind = '',
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (search.isNotEmpty) query['search'] = search;
    if (kind.isNotEmpty) query['kind'] = kind;

    final body = await _client.getJson('/conversations', query: query);
    return asMap(body);
  }

  @override
  Future<Map<String, dynamic>> getOrCreateDirect(String otherUserId) async {
    final body = await _client.postJson(
      '/conversations/direct',
      body: {'otherUserId': otherUserId},
    );
    return asMap(body);
  }

  @override
  Future<List<Map<String, dynamic>>> messages(
    String conversationId, {
    String? before,
    int limit = 50,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (before != null) query['before'] = before;

    final body = await _client.getJson(
      '/conversations/$conversationId/messages',
      query: query,
    );
    return asMapList(asMap(body)['messages']);
  }

  @override
  Future<Map<String, dynamic>> sendMessage(
    String conversationId,
    String text, {
    String? parentId,
  }) async {
    final payload = <String, dynamic>{'text': text};
    if (parentId != null) payload['parentId'] = parentId;

    final body = await _client.postJson(
      '/conversations/$conversationId/messages',
      body: payload,
    );
    return asMap(asMap(body)['message']);
  }

  @override
  Future<void> markRead(String conversationId) async {
    await _client.postJson('/conversations/$conversationId/read');
  }

  @override
  Future<void> leave(String conversationId) async {
    await _client.postJson('/conversations/$conversationId/leave');
  }

  @override
  Future<Map<String, dynamic>> editMessage(
    String messageId,
    String text,
  ) async {
    final body = await _client.putJson(
      '/messages/$messageId',
      body: {'text': text},
    );
    return asMap(asMap(body)['message']);
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    await _client.deleteJson('/messages/$messageId');
  }

  @override
  Future<void> setTyping(String conversationId, bool typing) async {
    await _client.postJson(
      '/conversations/$conversationId/typing',
      body: {'typing': typing},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getTypers(
    String conversationId,
  ) async {
    final body = await _client.getJson(
      '/conversations/$conversationId/typing',
    );
    return asMapList(asMap(body)['typers']);
  }
}
