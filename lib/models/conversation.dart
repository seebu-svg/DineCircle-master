import 'user_profile.dart';

/// Conversation kind — maps to the server-side CHECK constraint.
enum ConversationKind { eventGroup, direct, partner }

ConversationKind _parseKind(String raw) {
  switch (raw) {
    case 'event_group':
      return ConversationKind.eventGroup;
    case 'direct':
      return ConversationKind.direct;
    case 'partner':
      return ConversationKind.partner;
    default:
      return ConversationKind.eventGroup;
  }
}

/// A conversation in the messaging system.
///
/// Backed by the `conversations` table. Each row carries a [kind] that
/// determines membership rules: event_group conversations are scoped to a
/// dinner event, direct conversations are 1-to-1 DMs, and partner
/// conversations link a host with a venue.
class Conversation {
  final String id;
  final ConversationKind kind;
  final String? eventId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final LastMessage? lastMessage;
  final int unreadCount;
  final int participantCount;

  /// For direct conversations, the other user's profile (null for groups).
  final UserProfile? otherUser;

  const Conversation({
    required this.id,
    required this.kind,
    this.eventId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.participantCount = 0,
    this.otherUser,
  });

  bool get isGroupChat => kind != ConversationKind.direct;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversation && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Slim last-message preview shown in the inbox row.
class LastMessage {
  final String text;
  final DateTime? sentAt;
  final String? authorId;
  final String? authorName;

  const LastMessage({
    required this.text,
    this.sentAt,
    this.authorId,
    this.authorName,
  });
}

/// A chat message within a conversation.
class ChatMessage {
  final String id;
  final String? authorId;
  final String text;
  final DateTime sentAt;
  final bool isSystem;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? parentId;
  final List<String> readBy;
  final UserProfile? author;

  const ChatMessage({
    required this.id,
    this.authorId,
    required this.text,
    required this.sentAt,
    this.isSystem = false,
    this.editedAt,
    this.deletedAt,
    this.parentId,
    this.readBy = const [],
    this.author,
  });

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
}

/// Build a [Conversation] from a JSON map returned by the API.
Conversation conversationFromJson(Map<String, dynamic> json) {
  final lastMsg = json['lastMessage'];
  final other = json['otherUser'];
  return Conversation(
    id: json['id'] as String? ?? '',
    kind: _parseKind(json['kind'] as String? ?? 'event_group'),
    eventId: json['eventId'] as String?,
    title: json['title'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    lastMessage: lastMsg is Map<String, dynamic>
        ? LastMessage(
            text: lastMsg['text'] as String? ?? '',
            sentAt: DateTime.tryParse(lastMsg['sentAt'] as String? ?? ''),
            authorId: lastMsg['authorId'] as String?,
            authorName: lastMsg['authorName'] as String?,
          )
        : null,
    unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    participantCount: (json['participantCount'] as num?)?.toInt() ?? 0,
    otherUser: other is Map<String, dynamic>
        ? UserProfile(
            id: other['id'] as String? ?? '',
            name: other['name'] as String? ?? '',
            avatarPath: other['avatarUrl'] as String?,
          )
        : null,
  );
}

/// Build a [ChatMessage] from a JSON map returned by the API.
ChatMessage chatMessageFromJson(Map<String, dynamic> json) {
  final authorJson = json['author'];
  final author = authorJson is Map<String, dynamic>
      ? UserProfile(
          id: authorJson['id'] as String? ?? '',
          name: authorJson['name'] as String? ?? 'Member',
          avatarPath: authorJson['avatarUrl'] as String?,
        )
      : null;

  return ChatMessage(
    id: json['id'] as String? ?? '',
    authorId: json['authorId'] as String?,
    text: json['text'] as String? ?? '',
    sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
    isSystem: json['isSystem'] as bool? ?? false,
    editedAt: DateTime.tryParse(json['editedAt'] as String? ?? ''),
    deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    parentId: json['parentId'] as String?,
    readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? const [],
    author: author,
  );
}
