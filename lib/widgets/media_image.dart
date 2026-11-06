import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Image loader that accepts both storage shapes DineCircle's API returns.
///
/// Every media column in the backend (`cover_image`, `photo_url`, gallery
/// entries, deal images) has historically carried repo-relative asset paths
/// (`assets/images/dish_steak.png`) while newer partner uploads store remote
/// URLs, and older rows may be empty. This widget picks the right loader per
/// source and always degrades to a branded placeholder tile instead of
/// throwing, so a missing photo never blanks a card or a hero.
///
/// Wrap it in a sized/clipped parent; the widget itself fills that box.
class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.restaurant_rounded,
    this.cacheWidth,
  });

  /// Raw media value from the API; may be null or empty.
  final String? source;
  final BoxFit fit;

  /// Icon painted by the placeholder when no image is available.
  final IconData fallbackIcon;

  /// Decode the remote image at this logical width to bound memory on lists.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final value = source?.trim() ?? '';
    if (value.isEmpty) return _fallback();
    if (value.startsWith('http')) {
      // Placeholder paints underneath so a slow remote image never flashes a
      // blank region.
      return Stack(
        fit: StackFit.expand,
        children: [
          _fallback(),
          Image.network(
            value,
            fit: fit,
            cacheWidth: cacheWidth,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (context, error, stackTrace) => _fallback(),
          ),
        ],
      );
    }
    return Image.asset(
      value,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stackTrace) => _fallback(),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surfaceElevated, AppColors.surfaceHigh],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(fallbackIcon, color: AppColors.textTertiary),
      ),
    );
  }
}
