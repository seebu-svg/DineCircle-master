import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/safety.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/safety_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/data_view.dart';

/// Settings → Privacy → Blocked Users.
///
/// Backed by `GET /users/me/blocked`. Unblocking only lifts the restriction —
/// the server deliberately does not restore follows or conversations, which
/// the explainer text here mirrors.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    BlockedUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unblock ${user.name}?'),
        content: Text(
          'You and ${user.name} will be able to follow each other and join '
          'the same events again. Follows removed by the block are not '
          'restored automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('unblockConfirm_${user.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(safetyRepositoryProvider).unblock(user.id);
      ref.invalidate(blockedUsersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} is no longer blocked.')),
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unblock. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Users')),
      body: DataView<List<BlockedUser>>(
        value: blocked,
        onRetry: () => ref.invalidate(blockedUsersProvider),
        isEmpty: (items) => items.isEmpty,
        emptyMessage: 'You have not blocked anyone yet.',
        builder: (context, items) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.paddingScreen),
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: AppColors.border),
          itemBuilder: (context, index) {
            final user = items[index];
            return ListTile(
              key: Key('blockedUser_${user.id}'),
              contentPadding: EdgeInsets.zero,
              leading: _BlockedAvatar(user: user),
              title: Text(user.name, style: AppTextStyles.titleSmall),
              subtitle: Text(
                user.handle.isEmpty ? '' : '@${user.handle}',
                style: AppTextStyles.bodySmall,
              ),
              trailing: TextButton(
                key: Key('unblockButton_${user.id}'),
                onPressed: () => _unblock(context, ref, user),
                child: const Text('Unblock'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BlockedAvatar extends StatelessWidget {
  const _BlockedAvatar({required this.user});

  final BlockedUser user;

  @override
  Widget build(BuildContext context) {
    // AvatarWidget resolves asset, absolute and API-relative (uploaded)
    // photo paths alike; a bare NetworkImage failed on seeded asset paths
    // and on uploaded photos, which are relative to the API root.
    return AvatarWidget(
      imagePath: user.avatarUrl,
      initials: user.initials,
      size: AppSpacing.avatarSm,
    );
  }
}
