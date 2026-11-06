import 'package:flutter/material.dart';

import '../../models/public_menu.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/media_image.dart';

/// Visual identity for one dietary tag.
///
/// Partners author these tags as free text, so the mapping covers the values the
/// Partner App actually produces (`vegetarian`, `vegan`, `spicy`, `seafood`,
/// `gluten-free`, `contains-nuts`, `dairy-free`, `halal`) and falls back to a
/// neutral chip for anything else rather than hiding the tag.
class DietaryTagStyle {
  const DietaryTagStyle(this.color, this.icon, this.label);

  final Color color;
  final IconData icon;

  /// Display label; defaults to the title-cased raw tag.
  final String label;

  static const _known = <String, DietaryTagStyle>{
    'vegetarian': DietaryTagStyle(AppColors.success, Icons.eco_rounded, 'Veg'),
    'vegan': DietaryTagStyle(AppColors.success, Icons.spa_rounded, 'Vegan'),
    'spicy': DietaryTagStyle(AppColors.danger, Icons.local_fire_department_rounded, 'Spicy'),
    'seafood': DietaryTagStyle(AppColors.info, Icons.set_meal_rounded, 'Seafood'),
    'gluten-free': DietaryTagStyle(AppColors.warning, Icons.grass_rounded, 'Gluten free'),
    'contains-nuts': DietaryTagStyle(AppColors.warning, Icons.warning_amber_rounded, 'Nuts'),
    'dairy-free': DietaryTagStyle(AppColors.info, Icons.water_drop_rounded, 'Dairy free'),
    'halal': DietaryTagStyle(AppColors.gold, Icons.verified_rounded, 'Halal'),
  };

  static DietaryTagStyle of(String tag) {
    final key = tag.trim().toLowerCase();
    return _known[key] ?? DietaryTagStyle(AppColors.info, Icons.verified_rounded, _titleCase(key));
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value
        .split(RegExp(r'[\s_-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}

/// Square dish photo with a branded placeholder when the venue uploaded none.
///
/// Menu photos arrive either as repo-relative asset paths (seeded venues) or as
/// remote URLs (partner uploads), and are frequently empty; [MediaImage] covers
/// all three cases. Assets are decoded at device resolution to keep long menus
/// cheap on low-end Android devices.
class DishPhoto extends StatelessWidget {
  const DishPhoto({super.key, required this.source, this.size = 92, this.radius = AppSpacing.radiusMd});

  final String? source;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: MediaImage(
            source: source,
            fallbackIcon: Icons.restaurant_menu_rounded,
            cacheWidth: (size * dpr).round(),
          ),
        ),
      ),
    );
  }
}

/// Compact dietary badge. Doubles as the tappable filter chip when [onTap] is
/// supplied, which keeps the read-only card badges and the filter row visually
/// identical.
class DietaryChip extends StatelessWidget {
  const DietaryChip({
    super.key,
    required this.tag,
    this.selected = false,
    this.onTap,
    this.count,
    this.showIcon = true,
  });

  final String tag;
  final bool selected;
  final VoidCallback? onTap;

  /// Optional item count rendered next to the label in the filter row.
  final int? count;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final style = DietaryTagStyle.of(tag);
    final filled = selected;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          Icon(style.icon, size: 11, color: filled ? AppColors.bg : style.color),
          const SizedBox(width: 4),
        ],
        Text(
          style.label.toUpperCase(),
          style: AppTextStyles.caption.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: filled ? AppColors.bg : style.color,
            letterSpacing: 0.2,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text(
            '$count',
            style: AppTextStyles.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: (filled ? AppColors.bg : style.color).withValues(alpha: 0.75),
            ),
          ),
        ],
      ],
    );

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? style.color : style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: filled ? style.color : style.color.withValues(alpha: 0.28)),
      ),
      child: content,
    );

    if (onTap == null) return pill;
    return Semantics(
      button: true,
      selected: selected,
      label: '${style.label} filter',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: pill,
      ),
    );
  }
}

/// Compact, image-first dish row used by every menu section.
///
/// Content is bounded (`maxLines` + ellipsis) and the layout flexes instead of
/// fixing a height, so a 1.3–2.0 accessibility text scale grows the card rather
/// than clipping it.
class DishCard extends StatelessWidget {
  const DishCard({super.key, required this.item, this.onTap});

  final PublicMenuItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tags = item.normalizedDietaryTags;
    return Semantics(
      button: true,
      label: '${item.name}, ${item.formattedPrice}',
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: AppColors.primary.withValues(alpha: 0.06),
            highlightColor: AppColors.primary.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DishPhoto(source: item.photoUrl),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: AppTextStyles.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.description,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final tag in tags) DietaryChip(tag: tag),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.formattedPrice,
                                style: AppTextStyles.titleSmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppColors.textTertiary,
                            ),
                          ],
                        ),
                      ],
                    ),
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
