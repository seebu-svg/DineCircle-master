import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../models/offer.dart';

/// A deal / offer card with restaurant name, kind badge, description,
/// conditions, and a "Redeem" CTA button.
///
/// Used in the Offers tab and the Deals highlight section on the All tab.
class DealCard extends StatelessWidget {
  final Offer offer;
  final VoidCallback? onTap;
  final VoidCallback? onRedeem;

  const DealCard({super.key, required this.offer, this.onTap, this.onRedeem});

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: restaurant name + kind badge
            Row(
              children: [
                Flexible(
                  child: Text(
                    offer.restaurantName,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    offer.kindLabel,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Offer name / benefit
            Text(
              offer.name,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (offer.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                offer.description,
                style: AppTextStyles.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // Bottom row: conditions + CTA
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Rs ${offer.pricePerGuest.toStringAsFixed(0)}/guest · min ${offer.minGuests}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Spacer(),
                _RedeemButton(onTap: onRedeem ?? onTap),
              ],
            ),
            // Tags
            if (offer.tags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final tag in offer.tags.take(3))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RedeemButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _RedeemButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(color: AppColors.primary),
        ),
        child: Text(
          'Redeem',
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
        ),
      ),
    );
  }
}
