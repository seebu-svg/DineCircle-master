import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Data item describing a discovery occasion (Date Night, Celebrations, etc.).
///
/// Used by [OccasionCard] for presentation and by the Explore screen to map
/// taps to the appropriate [EventFilter] combination.
class OccasionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String assetImage;

  /// Optional venue tag the occasion maps to on the Explore screen. Tapping
  /// the card sets this tag on the Restaurants tab so the filter is backed by
  /// real venue data rather than a hard-coded listing.
  final String? venueTag;

  const OccasionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.assetImage,
    this.venueTag,
  });
}

/// A tappable occasion discovery card (160 × 150).
///
/// Shows a background image with a dark gradient overlay, an accent-tinted icon,
/// the occasion title and subtitle at the bottom. Used in a horizontal scroll
/// on the Discover "All" tab.
class OccasionCard extends StatelessWidget {
  final OccasionItem item;
  final VoidCallback? onTap;

  const OccasionCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: item.title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 160,
          height: 150,
          margin: const EdgeInsets.only(right: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            image: DecorationImage(
              image: AssetImage(item.assetImage),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              // Dark gradient overlay for text legibility
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: AppColors.imageOverlay,
                  ),
                ),
              ),
              // Content pinned to bottom-left
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, color: item.accent, size: 20),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
