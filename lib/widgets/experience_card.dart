import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../models/dinner.dart';
import 'avatar_widget.dart';
import 'media_image.dart';

/// A curated experience card for vertical lists.
///
/// Shows a 100 x 100 cover image on the left and a content column on the right
/// with title, host, venue + date, price, remaining seats, and a reserve CTA.
/// Replaces the repetitive DinnerCard horizontal scrollers in the Explore feed.
class ExperienceCard extends StatelessWidget {
  final Dinner dinner;
  final VoidCallback? onTap;
  final VoidCallback? onReserve;

  const ExperienceCard({
    super.key,
    required this.dinner,
    this.onTap,
    this.onReserve,
  });

  @override
  Widget build(BuildContext context) {
    final seatsLeft = dinner.availableSeats;
    final isLow = seatsLeft <= 3 && seatsLeft > 0;
    final isFull = seatsLeft <= 0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: SizedBox(
                width: 100,
                height: 100,
                child: MediaImage(
                  source: dinner.imagePath,
                  fallbackIcon: Icons.local_dining_rounded,
                  cacheWidth: 300,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Content column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    dinner.title,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Host
                  Row(
                    children: [
                      AvatarWidget(
                        imagePath: dinner.host.avatarPath,
                        initials: dinner.host.initials,
                        size: AppSpacing.avatarXs,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          dinner.host.name,
                          style: AppTextStyles.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Venue + date
                  Text(
                    '${dinner.restaurant.name} · ${dinner.formattedDate}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Price + seats
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Est. dining Rs ${dinner.pricePerSeat.toStringAsFixed(0)} / person',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      if (!isFull)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isLow
                                  ? AppColors.danger.withValues(alpha: 0.2)
                                  : AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                            ),
                            child: Text(
                              '$seatsLeft left',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: isLow
                                    ? AppColors.danger
                                    : AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Reserve CTA, separate bottom row
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _ReserveButton(
                      isFull: isFull,
                      onTap: onReserve ?? onTap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small CTA button at the bottom-right of an [ExperienceCard].
class _ReserveButton extends StatelessWidget {
  final bool isFull;
  final VoidCallback? onTap;

  const _ReserveButton({required this.isFull, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isFull ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isFull
              ? AppColors.surfaceElevated
              : AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: isFull ? AppColors.border : AppColors.primary,
          ),
        ),
        child: Text(
          isFull ? 'Full' : 'Reserve',
          style: AppTextStyles.labelSmall.copyWith(
            color: isFull ? AppColors.textTertiary : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
