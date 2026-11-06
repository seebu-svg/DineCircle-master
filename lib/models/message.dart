import 'user_profile.dart';
import 'dinner.dart';

/// Message model
class Message {
  final String id;
  final String content;
  final UserProfile sender;
  final DateTime timestamp;
  final bool isRead;

  const Message({
    required this.id,
    required this.content,
    required this.sender,
    required this.timestamp,
    this.isRead = false,
  });
}

/// Chat conversation model
class ChatConversation {
  final String id;
  final String title;
  final Dinner? dinner;
  final List<UserProfile> participants;
  final Message? lastMessage;
  final int unreadCount;
  final bool isGroupChat;

  const ChatConversation({
    required this.id,
    required this.title,
    this.dinner,
    required this.participants,
    this.lastMessage,
    this.unreadCount = 0,
    this.isGroupChat = false,
  });

  String get formattedTime {
    if (lastMessage == null) return '';
    final now = DateTime.now();
    final difference = now.difference(lastMessage!.timestamp);

    if (difference.inDays == 0) {
      return '${lastMessage!.timestamp.hour.toString().padLeft(2, '0')}:${lastMessage!.timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${lastMessage!.timestamp.day}/${lastMessage!.timestamp.month}';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatConversation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
