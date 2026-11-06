import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/delete_account_flow.dart';
import '../../widgets/edit_profile_sheet.dart';
import '../help/help_screen.dart';
import '../location/location_settings_screen.dart';
import '../preferences/food_preferences_screen.dart';
import '../safety/blocked_users_screen.dart';
import '../safety/my_reports_screen.dart';
import 'account_type_screen.dart';
import 'change_email_sheet.dart';
import 'change_password_sheet.dart';
import 'privacy_settings_screen.dart';

/// Settings — the P1 account surface, kept clean and minimal: every row here
/// is wired to a real Express endpoint. Phone/OTP changes exist server-side
/// but are intentionally not exposed in this release.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to sign back in to continue."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // AppFlow watches the session, so this swaps the whole app to AuthScreen.
      await ref.read(sessionControllerProvider.notifier).signOut();
    }
  }

  Future<void> _confirmLogoutAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out everywhere?'),
        content: const Text(
          'Every signed-in device for this account will be logged out, '
          'including this one. You will need to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out all devices'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(sessionControllerProvider.notifier).logoutAllDevices();
    }
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        children: [
          // ── Account ──────────────────────────────────────────────────────
          Text(
            'Account',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            tileKey: 'settingsAccountType',
            icon: Icons.switch_account_rounded,
            title: 'Account Type',
            subtitle: user == null
                ? null
                : (user.isProfessional
                      ? 'Professional · Public profile'
                      : 'Personal · Private profile'),
            onTap: () => _push(context, const AccountTypeScreen()),
          ),
          _SettingsTile(
            icon: Icons.badge_rounded,
            title: 'Personal Information',
            subtitle: user == null
                ? null
                : (user.email.isEmpty ? user.name : user.email),
            onTap: user == null
                ? null
                : () => showEditProfileSheet(context, user),
          ),
          _SettingsTile(
            icon: Icons.email_rounded,
            title: 'Change Email',
            subtitle: 'Verify the new address with a code',
            onTap: user == null || user.email.isEmpty
                ? null
                : () => showChangeEmailSheet(context, user),
          ),
          _SettingsTile(
            icon: Icons.lock_rounded,
            title: 'Change Password',
            onTap: () => showChangePasswordSheet(context),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Preferences ──────────────────────────────────────────────────
          Text(
            'Preferences',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.restaurant_menu_rounded,
            title: 'Food Preferences',
            subtitle: 'Cuisines, dietary needs, allergies',
            onTap: () => _push(context, const FoodPreferencesScreen()),
          ),
          _SettingsTile(
            icon: Icons.location_on_rounded,
            title: 'Location',
            subtitle: user?.location ?? 'Choose your city',
            onTap: () => _push(context, const LocationSettingsScreen()),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Privacy ──────────────────────────────────────────────────────
          Text(
            'Privacy',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            tileKey: 'settingsPrivacy',
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy & Security',
            subtitle: 'Profile visibility, followers, messaging',
            onTap: () => _push(context, const PrivacySettingsScreen()),
          ),
          _SettingsTile(
            tileKey: 'settingsBlockedUsers',
            icon: Icons.block_rounded,
            title: 'Blocked Users',
            subtitle: 'Who you have blocked — unblock any time',
            onTap: () => _push(context, const BlockedUsersScreen()),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Support (P2 Safety & Trust) ──────────────────────────────
          Text(
            'Support',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            tileKey: 'settingsHelpFeedback',
            icon: Icons.help_outline_rounded,
            title: 'Help & Feedback',
            subtitle: 'FAQs, tickets and contacting support',
            onTap: () => _push(context, const HelpScreen()),
          ),
          _SettingsTile(
            tileKey: 'settingsMyReports',
            icon: Icons.flag_outlined,
            title: 'My Reports',
            subtitle: 'Track what you have flagged and its status',
            onTap: () => _push(context, const MyReportsScreen()),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Session ──────────────────────────────────────────────────────
          Text(
            'Session',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.danger,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.logout_rounded,
            title: 'Log Out',
            titleColor: AppColors.danger,
            onTap: () => _confirmLogout(context, ref),
          ),
          _SettingsTile(
            icon: Icons.devices_rounded,
            title: 'Logout All Devices',
            subtitle: 'Sign out everywhere, including this phone',
            titleColor: AppColors.danger,
            onTap: () => _confirmLogoutAll(context, ref),
          ),
          _SettingsTile(
            icon: Icons.delete_forever_rounded,
            title: 'Delete Account',
            subtitle: 'Permanently remove your account',
            titleColor: AppColors.danger,
            onTap: () => confirmAndDeleteAccount(context, ref),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Version 1.0.0',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String? tileKey;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _SettingsTile({
    this.tileKey,
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey == null ? null : Key(tileKey!),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: titleColor ?? AppColors.textSecondary),
      title: Text(
        title,
        style: AppTextStyles.titleSmall.copyWith(color: titleColor),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textTertiary,
      ),
    );
  }
}
