import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/buttons.dart';

/// The premium identity card at the top of the Profile overview.
///
/// Shows the photo (with the camera badge that opens the avatar picker), the
/// name/verification mark, `@handle`, the `city · homeArea` line, a
/// "Member since" capsule and,when they exist,the bio and the Instagram
/// link. Empty fields are omitted rather than rendered as empty boxes.
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.user,
    required this.onAvatarTap,
    required this.onEdit,
  });

  final UserProfile user;
  final VoidCallback onAvatarTap;
  final VoidCallback onEdit;

  /// `city · homeArea`, falling back to `city`, then to nothing at all.
  String get _locationLine {
    final city = (user.location ?? '').trim();
    final area = user.homeArea.trim();
    if (city.isNotEmpty && area.isNotEmpty) return '$city · $area';
    if (city.isNotEmpty) return city;
    if (area.isNotEmpty) return area;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final location = _locationLine;
    final bio = (user.bio ?? '').trim();
    final instagram = user.instagram.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              AppColors.primary.withValues(alpha: 0.12),
              AppColors.surface,
            ),
            AppColors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarWithBadge(user: user, onTap: onAvatarTap),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            style: AppTextStyles.titleLarge.copyWith(
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.isVerified) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const Icon(
                            Icons.verified_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    if (user.handle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${user.handle}',
                        key: const Key('profileHandle'),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _IconLine(
                        icon: Icons.place_rounded,
                        text: location,
                        color: AppColors.textSecondary,
                      ),
                    ],
                    if (user.joinedYear > 0) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _Capsule(text: 'Member since ${user.joinedYear}'),
                    ],
                    // Public/private state of the account, always visible so a
                    // Professional host and a private diner are never confused.
                    const SizedBox(height: AppSpacing.sm),
                    _AccountTypeChip(isProfessional: user.isProfessional),
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
          if (instagram.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _IconLine(
              key: const Key('profileInstagram'),
              icon: Icons.photo_camera_rounded,
              text: 'instagram.com/$instagram',
              color: AppColors.textTertiary,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            text: 'Edit Profile',
            icon: Icons.edit_rounded,
            isFullWidth: true,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// Public/private state of the account: gold "Professional" for a host
/// profile, muted "Private" for a personal one.
class _AccountTypeChip extends StatelessWidget {
  const _AccountTypeChip({required this.isProfessional});

  final bool isProfessional;

  @override
  Widget build(BuildContext context) {
    final tint = isProfessional ? AppColors.gold : AppColors.textTertiary;
    return Container(
      key: const Key('profileAccountTypeChip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isProfessional ? Icons.public_rounded : Icons.lock_rounded,
            size: 11,
            color: tint,
          ),
          const SizedBox(width: 4),
          Text(
            isProfessional ? 'Professional' : 'Private',
            style: AppTextStyles.caption.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 88 px photo with the orange camera badge layered over its corner.
class _AvatarWithBadge extends StatelessWidget {
  const _AvatarWithBadge({required this.user, required this.onTap});

  static const double _size = 88;

  final UserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AvatarWidget(
          imagePath: user.avatarPath,
          initials: user.initials,
          size: _size,
          onTap: onTap,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            key: const Key('profileAvatarEdit'),
            onTap: onTap,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single-line pill, e.g. "Member since 2024".
class _Capsule extends StatelessWidget {
  const _Capsule({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            size: 12,
            color: AppColors.gold,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + text row used for the location and Instagram lines.
class _IconLine extends StatelessWidget {
  const _IconLine({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: AppTextStyles.caption.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The three headline counters. Each cell is a tap target into the surface
/// that owns the number (bookings / tables / saved) instead of one big tap
/// area that always opened My Bookings.
class ProfileStatsStrip extends StatelessWidget {
  const ProfileStatsStrip({
    super.key,
    required this.experiences,
    required this.tablesBooked,
    required this.saved,
    required this.onExperiences,
    required this.onTables,
    required this.onSaved,
  });

  final int experiences;
  final int tablesBooked;
  final int saved;
  final VoidCallback onExperiences;
  final VoidCallback onTables;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              value: '$experiences',
              label: 'Experiences',
              onTap: onExperiences,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatCell(
              value: '$tablesBooked',
              label: 'Tables Booked',
              onTap: onTables,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatCell(value: '$saved', label: 'Saved', onTap: onSaved),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.border,
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tile of the quick-actions grid.
class QuickAction {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.tint = AppColors.primary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Live count rendered under the label when the surface has one.
  final int? count;
  final Color tint;
}

/// Two-column grid of the diner's activity destinations. A trailing odd tile
/// keeps its half-width slot, so three tiles stay evenly spaced.
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += 2) {
      final first = actions[i];
      final second = i + 1 < actions.length ? actions[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _QuickActionTile(action: first)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: second == null
                    ? const SizedBox.shrink()
                    : _QuickActionTile(action: second),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: action.tint.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, size: 18, color: action.tint),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              action.label,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (action.count != null) ...[
              const SizedBox(height: 2),
              Text(
                '${action.count}',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A section of menu rows rendered inside one surface card, hairline-divided.
class ProfileMenuGroup extends StatelessWidget {
  const ProfileMenuGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          const Divider(height: 1, thickness: 1, color: AppColors.border),
        );
      }
      children.add(rows[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.overline.copyWith(color: AppColors.textTertiary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.sm),
        // A Material (not a coloured Container) so the ListTile rows keep
        // their ink splashes and the framework's "invisible ink" assertion
        // stays quiet.
        Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
