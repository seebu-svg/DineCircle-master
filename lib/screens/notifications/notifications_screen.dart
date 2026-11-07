import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/notification_item.dart';
import '../../providers/social_provider.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/data_view.dart';

/// Notifications screen, unified alerts surface combining activity feed,
/// upcoming-booking reminders and followed-venue offers.
///
/// Backed by `GET /users/me/notifications` (computed on read, no cron).
/// "Mark all read" hits `POST /activity/read` for the activity subset.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Text('Notifications', maxLines: 1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all read',
            color: AppColors.primary,
            onPressed: () => ref.read(socialControllerProvider).markAllRead(),
          ),
        ],
      ),
      body: DataView<List<NotificationItem>>(
        value: notificationsAsync,
        onRetry: () => ref.invalidate(notificationsProvider),
        isEmpty: (data) => data.isEmpty,
        emptyWidget: const EmptyStateView(
          icon: Icons.notifications_none_rounded,
          message: "You're all caught up.",
        ),
        builder: (context, notifications) => ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: notification.isRead
                    ? null
                    : AppColors.surface.withValues(alpha: 0.5),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getNotificationColor(notification)
                          .withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getNotificationIcon(notification),
                      color: _getNotificationColor(notification),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: AppTextStyles.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          notification.message,
                          style: AppTextStyles.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          notification.formattedTime,
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  // Avatar if user
                  if (notification.user != null)
                    AvatarWidget(
                      imagePath: notification.user!.avatarPath,
                      initials: notification.user!.initials,
                      size: AppSpacing.avatarSm,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _getNotificationIcon(NotificationItem n) {
    // Per-kind leading icon, overrides the legacy type-based mapping.
    switch (n.itemKind) {
      case NotificationItemKind.reminder:
        return Icons.calendar_today_rounded;
      case NotificationItemKind.offer:
        return Icons.local_offer_rounded;
      case NotificationItemKind.activity:
        break;
    }
    switch (n.type) {
      case NotificationType.bookingConfirmed:
        return Icons.check_circle_rounded;
      case NotificationType.bookingCancelled:
        return Icons.cancel_rounded;
      case NotificationType.newAttendee:
      case NotificationType.followRequest:
        return Icons.person_add_rounded;
      case NotificationType.dinnerReminder:
        return Icons.event_rounded;
      case NotificationType.message:
        return Icons.message_rounded;
      case NotificationType.hostEarnings:
        return Icons.payments_rounded;
      case NotificationType.specialOffer:
        return Icons.local_offer_rounded;
      case NotificationType.review:
        return Icons.star_rounded;
    }
  }

  Color _getNotificationColor(NotificationItem n) {
    switch (n.itemKind) {
      case NotificationItemKind.reminder:
        return AppColors.warning;
      case NotificationItemKind.offer:
        return AppColors.gold;
      case NotificationItemKind.activity:
        break;
    }
    switch (n.type) {
      case NotificationType.bookingConfirmed:
        return AppColors.success;
      case NotificationType.bookingCancelled:
        return AppColors.danger;
      case NotificationType.newAttendee:
      case NotificationType.followRequest:
        return AppColors.info;
      case NotificationType.dinnerReminder:
        return AppColors.warning;
      case NotificationType.message:
        return AppColors.primary;
      case NotificationType.hostEarnings:
        return AppColors.success;
      case NotificationType.specialOffer:
        return AppColors.gold;
      case NotificationType.review:
        return AppColors.gold;
    }
  }
}
