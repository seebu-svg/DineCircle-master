import 'package:flutter/material.dart';

import '../../models/restaurant.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/media_image.dart';

/// Full-bleed hero for the restaurant profile.
///
/// Painted as a `FlexibleSpaceBar.background`, so it fills the expanded app-bar
/// area exactly: cover art, a three-stop scrim that keeps the toolbar icons and
/// the identity block legible over any photo, then the venue identity at the
/// bottom (name, trust badges, rating, cuisine + area, open status).
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.restaurant,
    required this.isOpen,
    required this.todayLabel,
  });

  final Restaurant restaurant;
  final bool isOpen;

  /// Today's window text (`17:00–23:30`) or `Closed`.
  final String todayLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: AppColors.surfaceElevated,
          child: MediaImage(
            source: restaurant.imagePath,
            fallbackIcon: Icons.storefront_rounded,
            cacheWidth: 900,
          ),
        ),
        // Scrim: dark under the toolbar icons, clear across the photo, opaque
        // at the base so the identity block sits on the page background.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.08),
                AppColors.bg.withValues(alpha: 0.78),
                AppColors.bg,
              ],
              stops: const [0, 0.34, 0.78, 1],
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.paddingScreen,
          right: AppSpacing.paddingScreen,
          bottom: AppSpacing.md,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                restaurant.name,
                style: AppTextStyles.headlineMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (restaurant.partnershipStatus == 'verified' ||
                  restaurant.isPartner) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (restaurant.partnershipStatus == 'verified')
                      const ProfileBadge(
                        label: 'VERIFIED',
                        icon: Icons.verified_rounded,
                        color: AppColors.success,
                      ),
                    if (restaurant.isPartner)
                      const ProfileBadge(
                        label: 'PARTNER',
                        icon: Icons.workspace_premium_rounded,
                        gradient: AppColors.goldGradient,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (restaurant.reviewCount > 0)
                    RatingPill(
                      rating: restaurant.rating,
                      reviewCount: restaurant.reviewCount,
                    )
                  else
                    Text(
                      'No reviews yet',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  Text(
                    restaurant.priceRangeLabel,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (restaurant.openingHours.isNotEmpty)
                    OpeningStatusPill(isOpen: isOpen, todayLabel: todayLabel),
                ],
              ),
              if (restaurant.cuisine.trim().isNotEmpty ||
                  restaurant.locationLine.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    if (restaurant.cuisine.trim().isNotEmpty)
                      restaurant.cuisine.trim(),
                    if (restaurant.locationLine.trim().isNotEmpty)
                      restaurant.locationLine.trim(),
                  ].join(' · '),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Small trust capsule (verified / partner) shown under the venue name.
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({
    super.key,
    required this.label,
    required this.icon,
    this.color,
    this.gradient,
  }) : assert(
          color != null || gradient != null,
          'ProfileBadge needs a color or a gradient.',
        );

  final String label;
  final IconData icon;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final onDark = color == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: onDark ? Colors.black : Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: onDark ? Colors.black : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// `Open now` / `Closed` dot pill with today's hours alongside.
class OpeningStatusPill extends StatelessWidget {
  const OpeningStatusPill({
    super.key,
    required this.isOpen,
    required this.todayLabel,
  });

  final bool isOpen;
  final String todayLabel;

  @override
  Widget build(BuildContext context) {
    final tone = isOpen ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isOpen ? 'Open now' : 'Closed',
            style: AppTextStyles.caption.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isOpen && todayLabel.isNotEmpty && todayLabel != 'Closed') ...[
            const SizedBox(width: 5),
            Text(
              todayLabel,
              style: AppTextStyles.caption.copyWith(
                color: tone.withValues(alpha: 0.78),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Directions / Call / Save / Share, the four things a guest does before
/// deciding to go. Unavailable actions stay visible but dimmed and inert so the
/// row never silently changes shape between venues.
class QuickActionsBar extends StatelessWidget {
  const QuickActionsBar({
    super.key,
    required this.onDirections,
    required this.onCall,
    required this.onSave,
    required this.onShare,
    required this.isSaved,
    required this.isBusy,
    required this.canCall,
    required this.canDirections,
  });

  final VoidCallback onDirections;
  final VoidCallback onCall;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final bool isSaved;
  final bool isBusy;
  final bool canCall;
  final bool canDirections;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          children: [
            _QuickActionTile(
              icon: Icons.directions_rounded,
              label: 'Directions',
              onTap: canDirections ? onDirections : null,
            ),
            _QuickActionTile(
              icon: Icons.phone_rounded,
              label: 'Call',
              onTap: canCall ? onCall : null,
            ),
            _QuickActionTile(
              icon: isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: isSaved ? 'Saved' : 'Save',
              highlighted: isSaved,
              onTap: isBusy ? null : onSave,
              busy: isBusy,
            ),
            _QuickActionTile(
              icon: Icons.share_rounded,
              label: 'Share',
              onTap: onShare,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Expanded(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AppSpacing.avatarMd,
                    height: AppSpacing.avatarMd,
                    decoration: BoxDecoration(
                      color: highlighted
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : AppColors.surfaceHigh,
                      shape: BoxShape.circle,
                      border: highlighted
                          ? Border.all(
                              color: AppColors.primary.withValues(alpha: 0.45),
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(
                            icon,
                            size: 19,
                            color: highlighted
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: AppTextStyles.caption.copyWith(
                      color: highlighted
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
