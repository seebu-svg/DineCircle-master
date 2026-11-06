import 'package:flutter/material.dart';

import '../../models/deal.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/deal_cover_image.dart';
import '../deals/deal_ui.dart';

/// Premium deal card for the Explore screen.
///
/// Shows a cover image with discount badge, restaurant name, deal title,
/// urgency indicator and a "View Deal" action. Tapping the card fires [onTap]
/// (typically opens the deal detail); tapping the venue line fires [onVenueTap].
class ExploreDealCard extends StatelessWidget {
  const ExploreDealCard({
    super.key,
    required this.deal,
    this.onTap,
    this.onVenueTap,
  });

  final Deal deal;
  final VoidCallback? onTap;
  final VoidCallback? onVenueTap;

  @override
  Widget build(BuildContext context) {
    final urgency = DealUi.urgencyLabel(deal);
    return Semantics(
      button: true,
      label: '${deal.kindLabel} at ${deal.restaurantName}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cover art with badge ──
              SizedBox(
                height: 110,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DealCoverImage(source: deal.coverImage),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black38, Colors.transparent],
                          stops: [0.0, 0.5],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                      child: DealBadge(deal: deal, onDark: true),
                    ),
                    if (urgency != null)
                      Positioned(
                        top: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                          ),
                          child: Text(
                            urgency,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Content ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deal.restaurantName,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        deal.title,
                        style: AppTextStyles.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // "View Deal" action row
                      Row(
                        children: [
                          if (deal.city != null &&
                              deal.city!.trim().isNotEmpty) ...[
                            Icon(
                              Icons.location_on_outlined,
                              size: 12,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                deal.city!,
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                          ] else
                            const Spacer(),
                          Text(
                            'View Deal',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
