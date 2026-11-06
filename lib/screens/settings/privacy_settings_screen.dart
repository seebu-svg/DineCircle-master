import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../safety/blocked_users_screen.dart';

/// P1-4 Privacy & Security — the four server-backed visibility toggles,
/// each written immediately through `PATCH /users/me` (partial payload,
/// only the flipped key). `showFollowList` and `showActivity` are enforced
/// server-side on the roster/activity endpoints; a failed write rolls the
/// switch back so the UI never claims a state the database rejected.
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  bool _savingAny = false;

  Future<void> _write(String key, bool value) async {
    if (_savingAny) return;
    setState(() => _savingAny = true);
    try {
      await ref.read(sessionControllerProvider.notifier).updateSettings({
        key: value,
      });
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAny = false);
    }
    // The session republishes on success, so the switches re-read the
    // authoritative values from currentUserProvider automatically.
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Privacy & Security')),
        body: const Center(child: Text('Sign in to manage privacy.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        children: [
          Text('Profile visibility', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          _ToggleTile(
            keyName: 'showFollowListSwitch',
            title: 'Show followers & following',
            subtitle: 'Let others see who you follow and who follows you on your profile.',
            value: user.showFollowList,
            onChanged: (v) => _write('showFollowList', v),
          ),
          _ToggleTile(
            keyName: 'showActivitySwitch',
            title: 'Show my activity',
            subtitle: 'Your bookings and hosting appear in friends\u2019 activity feeds.',
            value: user.showActivity,
            onChanged: (v) => _write('showActivity', v),
          ),
          _ToggleTile(
            keyName: 'allowTaggingSwitch',
            title: 'Allow tagging',
            subtitle: 'Hosts and friends can tag you in dinners and reviews.',
            value: user.allowTagging,
            onChanged: (v) => _write('allowTagging', v),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Messaging', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          _ToggleTile(
            keyName: 'dmFollowersOnlySwitch',
            title: 'Messages from followers only',
            subtitle:
                'Only people you follow back can start a chat with you. '
                'Event group chats are always available to attendees.',
            value: user.dmFromFollowersOnly,
            onChanged: (v) => _write('dmFromFollowersOnly', v),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Blocked accounts', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            key: const Key('privacyBlockedUsersRow'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block_rounded, color: AppColors.danger),
            title: Text('Blocked Users', style: AppTextStyles.titleSmall),
            subtitle: Text(
              'You have full control — review or undo any block.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'These settings apply across devices — they are stored on your '
            'account, not on this phone.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String keyName;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: Key(keyName),
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: AppTextStyles.titleSmall),
      subtitle: Text(
        subtitle,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
