import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/user_profile.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/buttons.dart';
import '../../widgets/edit_profile_sheet.dart';

/// One short step that turns the current account into a Professional one.
///
/// Deliberately a single screen rather than a wizard: the only thing the user
/// has to understand is that the SAME account also gets a public host profile,
/// and that nothing about their bookings, history or login changes.
class ProfessionalOnboardingScreen extends ConsumerStatefulWidget {
  const ProfessionalOnboardingScreen({super.key});

  @override
  ConsumerState<ProfessionalOnboardingScreen> createState() =>
      _ProfessionalOnboardingScreenState();
}

class _ProfessionalOnboardingScreenState
    extends ConsumerState<ProfessionalOnboardingScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .switchAccountType('professional');
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not switch account type. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Become a Professional')),
      body: SafeArea(
        child: user == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                      children: [
                        const _Header(),
                        const SizedBox(height: AppSpacing.lg),
                        _PublicProfilePreview(user: user),
                        const SizedBox(height: AppSpacing.lg),
                        const _CheckRow(
                          icon: Icons.public_rounded,
                          title: 'Public profile',
                          body:
                              'Your name, photo, bio and hosted experiences '
                              'become visible to everyone on DineCircle.',
                        ),
                        const _CheckRow(
                          icon: Icons.storefront_rounded,
                          title: 'Host Studio',
                          body:
                              'Create and publish dining experiences, manage '
                              'guests and see basic insights.',
                        ),
                        const _CheckRow(
                          icon: Icons.sync_alt_rounded,
                          title: 'Same account, same login',
                          body:
                              'Your reservations, joined experiences, saved '
                              'places and followers stay exactly as they are.',
                        ),
                        const _CheckRow(
                          icon: Icons.lock_open_rounded,
                          title: 'Switch back any time',
                          body:
                              'You can return to a Personal account from '
                              'Settings whenever you have no upcoming '
                              'experiences.',
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _error!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.paddingScreen,
                      AppSpacing.md,
                      AppSpacing.paddingScreen,
                      AppSpacing.md,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        top: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: PrimaryButton(
                      key: const Key('professionalActivate'),
                      text: 'Switch to Professional',
                      isLoading: _busy,
                      onPressed: _busy ? null : _activate,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: AppColors.gold,
            size: 28,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Host dining experiences',
          style: AppTextStyles.headlineSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'A Professional account is the same DineCircle account you already '
          'use. It just adds a public host profile and Host Studio.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// What other people will see once the account goes public, built from the
/// profile the user already filled in (no second profile to maintain).
class _PublicProfilePreview extends StatelessWidget {
  const _PublicProfilePreview({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final bio = (user.bio ?? '').trim();
    final city = (user.location ?? '').trim();
    final handle = user.handle.trim();
    final instagram = user.instagram.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        color: AppColors.surfaceElevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarWidget(
                imagePath: user.avatarPath,
                initials: user.initials,
                size: AppSpacing.avatarLg,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (handle.isNotEmpty)
                      Text(
                        '@$handle',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.public_rounded,
                      size: 12,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Public',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              bio,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (city.isNotEmpty || instagram.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (city.isNotEmpty) _MetaChip(icon: Icons.place_rounded, label: city),
                if (instagram.isNotEmpty)
                  _MetaChip(
                    icon: Icons.photo_camera_rounded,
                    label: '@$instagram',
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('professionalEditPublicProfile'),
              onPressed: () => showEditProfileSheet(context, user),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit public details'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: AppColors.success),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
