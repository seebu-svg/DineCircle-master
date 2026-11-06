import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/conversation.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/avatar_widget.dart';

/// Premium message bubble for the conversation-mode chat screen.
///
/// Supports:
/// - Outgoing gradient vs incoming surface styling
/// - Read receipt indicators (single/double check)
/// - Edited / deleted message labels
/// - Long-press action menu (reply, copy, edit, delete, report)
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showAuthor;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showAuthor = false,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onReport,
  });

  String get _time {
    final t = message.sentAt;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) return _buildDeletedBubble(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (showAuthor)
              AvatarWidget(
                imagePath: message.author?.avatarPath,
                initials: _initials(message.author?.name ?? ''),
                size: AppSpacing.avatarSm,
              )
            else
              const SizedBox(width: AppSpacing.avatarSm),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showActions(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isMe ? AppColors.primaryGradient : null,
                  color: isMe ? null : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(AppSpacing.radiusLg),
                    topRight: const Radius.circular(AppSpacing.radiusLg),
                    bottomLeft: Radius.circular(
                      isMe ? AppSpacing.radiusLg : AppSpacing.radiusXs,
                    ),
                    bottomRight: Radius.circular(
                      isMe ? AppSpacing.radiusXs : AppSpacing.radiusLg,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe && showAuthor && message.author != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          message.author!.name,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (message.isEdited && isMe)
                      // "Edited" label above text for outgoing
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            'edited',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white54,
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    Text(
                      message.text,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isMe ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Time + read receipt row
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isMe && message.isEdited) ...[
                          Text(
                            'edited',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _time,
                          style: AppTextStyles.caption.copyWith(
                            color: isMe
                                ? Colors.white54
                                : AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          _ReadCheck(readBy: message.readBy),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }

  Widget _buildDeletedBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) const SizedBox(width: AppSpacing.avatarSm + AppSpacing.sm),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  'This message was deleted',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }

  void _showActions(BuildContext context) {
    final actions = <BottomSheetAction>[
      BottomSheetAction(
        icon: Icons.copy_rounded,
        label: 'Copy',
        onTap: () {
          Clipboard.setData(ClipboardData(text: message.text));
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied to clipboard')),
          );
        },
      ),
    ];

    if (onReply != null) {
      actions.insert(
        0,
        BottomSheetAction(
          icon: Icons.reply_rounded,
          label: 'Reply',
          onTap: () {
            Navigator.pop(context);
            onReply?.call();
          },
        ),
      );
    }

    if (isMe) {
      if (onEdit != null) {
        actions.add(BottomSheetAction(
          icon: Icons.edit_rounded,
          label: 'Edit',
          onTap: () {
            Navigator.pop(context);
            onEdit?.call();
          },
        ));
      }
      if (onDelete != null) {
        actions.add(BottomSheetAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          labelColor: AppColors.danger,
          onTap: () {
            Navigator.pop(context);
            onDelete?.call();
          },
        ));
      }
    } else {
      if (onReport != null) {
        actions.add(BottomSheetAction(
          icon: Icons.flag_outlined,
          label: 'Report',
          labelColor: AppColors.danger,
          onTap: () {
            Navigator.pop(context);
            onReport?.call();
          },
        ));
      }
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: actions
                .map((a) => ListTile(
                      leading: Icon(a.icon, color: a.labelColor),
                      title: Text(
                        a.label,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: a.labelColor,
                        ),
                      ),
                      onTap: a.onTap,
                    ))
                .toList(),
          ),
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
}

/// Small action descriptor for the long-press bottom sheet.
class BottomSheetAction {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  const BottomSheetAction({
    required this.icon,
    required this.label,
    this.labelColor,
    required this.onTap,
  });
}

/// Read receipt check marks: single grey tick (sent), double grey (delivered),
/// double blue (read by at least one person).
class _ReadCheck extends StatelessWidget {
  const _ReadCheck({required this.readBy});

  final List<String> readBy;

  @override
  Widget build(BuildContext context) {
    final hasRead = readBy.isNotEmpty;
    final color = hasRead ? AppColors.info : Colors.white54;

    if (hasRead) {
      // Double check — read
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 12, color: color),
          const SizedBox(width: 1),
          Icon(Icons.check_rounded, size: 12, color: color),
        ],
      );
    }
    // Single check — sent/delivered
    return Icon(Icons.check_rounded, size: 12, color: color);
  }
}

/// Date separator widget shown between message groups.
class DateSeparator extends StatelessWidget {
  final DateTime date;

  const DateSeparator({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label =
          '${date.day} ${_monthName(date.month)} ${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[month - 1];
  }
}
