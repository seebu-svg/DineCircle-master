import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Primary button widget
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        elevation: 0,
      ),
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : _ButtonContent(icon: icon, text: text),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// Secondary button widget
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isFullWidth;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isFullWidth = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      child: _ButtonContent(icon: icon, text: text),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// Icon + label row shared by [PrimaryButton] and [SecondaryButton].
///
/// A button can be placed in a very narrow slot (e.g. three actions sharing a
/// 320px-wide row). The fixed button padding then leaves less room than the
/// icon and its gap alone occupy, which used to overflow the row. The icon is
/// therefore dropped once the label would no longer get a usable width, so the
/// label always ellipsizes inside the available space instead.
class _ButtonContent extends StatelessWidget {
  static const double _iconSize = 20;

  /// Minimum content width (icon + gap + a few label characters) required to
  /// keep the icon. Below this the icon is removed and the label takes over.
  static const double _minWidthForIcon =
      _iconSize + AppSpacing.sm + AppSpacing.sm * 3;

  final IconData? icon;
  final String text;

  const _ButtonContent({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final showIcon =
            icon != null &&
            (!maxWidth.isFinite || maxWidth >= _minWidthForIcon);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[
              Icon(icon, size: _iconSize),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(
                text,
                style: AppTextStyles.button,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
