import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/avatar_widget.dart';

/// Premium conversation row for the inbox list.
///
/// Shows avatar, title, last message preview, relative timestamp, and unread
/// badge. Supports an online indicator dot for direct conversations.
class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDirect = conversation.kind == ConversationKind.direct;
    final other = conversation.otherUser;
    final leadName = other?.name ?? conversation.title;
    final leadAvatar = other?.avatarPath;
    final leadInitials = _initials(leadName);

    final lastMsg = conversation.lastMessage;
    final preview = lastMsg != null
        ? (lastMsg.authorName != null
            ? '${lastMsg.authorName}: ${lastMsg.text}'
            : lastMsg.text)
        : (isDirect ? 'Start a conversation' : '${conversation.participantCount} members');

    final timestamp = lastMsg?.sentAt ?? conversation.updatedAt;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingScreen,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Avatar with optional online dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarWidget(
                  imagePath: leadAvatar,
                  initials: leadInitials,
                  size: AppSpacing.avatarLg,
                ),
                if (isDirect)
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 2),
                      ),
                    ),
                  ),
                if (conversation.isGroupChat && !isDirect)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.bg,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.people_rounded,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          leadName,
                          style: AppTextStyles.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _formatTimestamp(timestamp),
                        style: AppTextStyles.caption.copyWith(
                          color: conversation.unreadCount > 0
                              ? AppColors.primary
                              : AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: conversation.unreadCount > 0
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                            fontWeight: conversation.unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.unreadCount > 0) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusFull),
                          ),
                          constraints: const BoxConstraints(minWidth: 20),
                          child: Text(
                            '${conversation.unreadCount}',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    return name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d';
    }
    return '${dt.day}/${dt.month}';
  }
}
