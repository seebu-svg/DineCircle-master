import 'package:flutter/material.dart';

import '../../models/public_menu.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/media_image.dart';
import 'menu_dish_card.dart';

/// Opens the read-only dish details sheet.
///
/// DineCircle does not take orders or payments here: the sheet exists so a
/// guest can read everything the restaurant published about a dish — photo,
/// portion description, dietary tags, price — before ordering with a server.
Future<void> showDishDetail(
  BuildContext context, {
  required PublicMenuItem item,
  required String sectionName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceElevated,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXxl),
      ),
    ),
    builder: (context) => _DishDetailSheet(item: item, sectionName: sectionName),
  );
}

class _DishDetailSheet extends StatelessWidget {
  const _DishDetailSheet({required this.item, required this.sectionName});

  final PublicMenuItem item;
  final String sectionName;

  @override
  Widget build(BuildContext context) {
    final tags = item.normalizedDietaryTags;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final hasPhoto = (item.photoUrl ?? '').trim().isNotEmpty;

    return ConstrainedBox(
      // Cap the sheet so a long description scrolls instead of covering the
      // whole screen on a short Android viewport.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Photo ────────────────────────────────────────────────────────
            if (hasPhoto)
              Stack(
                children: [
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: MediaImage(
                      source: item.photoUrl,
                      fallbackIcon: Icons.restaurant_menu_rounded,
                      cacheWidth: (MediaQuery.sizeOf(context).width * dpr).round(),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.surfaceElevated.withValues(alpha: 0.85),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.45, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: const _CloseButton(),
                  ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.paddingScreen,
                  AppSpacing.md,
                  AppSpacing.paddingScreen,
                  0,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                    ),
                    const Spacer(),
                    const _CloseButton(),
                  ],
                ),
              ),

            // ── Name, section, price ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paddingScreen,
                AppSpacing.md,
                AppSpacing.paddingScreen,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sectionName.toUpperCase(),
                    style: AppTextStyles.overline.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(item.name, style: AppTextStyles.headlineMedium),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: Text(
                          item.formattedPrice,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.bg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      item.description,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final tag in tags) DietaryChip(tag: tag)],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.restaurant_rounded,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Served at the restaurant. Ask your server for today\'s '
                          'availability — DineCircle does not process orders or payments.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close dish details',
      child: Material(
        color: AppColors.bg.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.close_rounded, size: 18, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
