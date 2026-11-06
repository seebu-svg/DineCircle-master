import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../models/dinner.dart';
import '../providers/social_provider.dart';
import 'avatar_widget.dart';

/// Dinner card widget
class DinnerCard extends ConsumerWidget {
  final Dinner dinner;
  final VoidCallback? onTap;

  const DinnerCard({super.key, required this.dinner, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The hero image with its overlay, badges and save toggle.
            final image = ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusLg),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    dinner.imagePath ?? 'assets/images/hero_tasting.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.surfaceElevated,
                    ),
                  ),
                  // Gradient overlay
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.imageOverlay,
                    ),
                    child: SizedBox.expand(),
                  ),
                  // Tags
                  if (dinner.isSpecialEvent)
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                        child: Text(
                          'SPECIAL EVENT',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  // Date badge
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Text(
                        dinner.formattedDate,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Save toggle
                  Positioned(
                    bottom: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: _SaveButton(dinnerId: dinner.id),
                  ),
                ],
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The image flexes to absorb the remaining height when the rail
                // constrains the card (so it shrinks instead of overflowing at
                // large text scales); falls back to a fixed 160px block when the
                // parent height is unbounded (e.g. isolated widget tests).
                if (constraints.hasBoundedHeight)
                  Expanded(child: image)
                else
                  SizedBox(
                    width: double.infinity,
                    height: 160,
                    child: image,
                  ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Text(
                        dinner.title,
                        style: AppTextStyles.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Restaurant
                      Text(
                        dinner.restaurant.name,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Host and price
                      Row(
                        children: [
                          AvatarWidget(
                            imagePath: dinner.host.avatarPath,
                            initials: dinner.host.initials,
                            size: AppSpacing.avatarSm,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dinner.host.name,
                                  style: AppTextStyles.labelSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Est. dining Rs ${dinner.pricePerSeat.toStringAsFixed(0)} / person',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Seats left
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: dinner.availableSeats <= 3
                                    ? AppColors.danger.withValues(alpha: 0.2)
                                    : AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm,
                                ),
                              ),
                              child: Text(
                                '${dinner.availableSeats} left',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: dinner.availableSeats <= 3
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
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bookmark button reflecting the live saved state for [dinnerId]; toggles it
/// via the social controller and surfaces server errors as a snackbar.
class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.dinnerId});

  final String dinnerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = ref.watch(isSavedProvider(dinnerId));
    return GestureDetector(
      onTap: () async {
        try {
          if (isSaved) {
            await ref.read(socialControllerProvider).unsave(dinnerId);
          } else {
            await ref.read(socialControllerProvider).save(dinnerId);
          }
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update saved list.')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          color: isSaved ? AppColors.primary : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
