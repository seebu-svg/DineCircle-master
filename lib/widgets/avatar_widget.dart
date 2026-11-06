import 'package:flutter/material.dart';

import '../api/app_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Resolves an avatar reference to an [ImageProvider]:
///   * `http(s)://…`            → network image as-is;
///   * `/public/avatars/<id>…`  → uploaded photo, relative to the API root;
///   * anything else            → a bundled asset (seed data / mock fixtures).
/// Returns null for an empty reference so callers fall back to initials.
ImageProvider? avatarImageProvider(String? path) {
  final ref = path?.trim() ?? '';
  if (ref.isEmpty) return null;
  if (ref.startsWith('http://') || ref.startsWith('https://')) {
    return NetworkImage(ref);
  }
  if (ref.startsWith('/')) {
    return NetworkImage('${AppConfig.apiUrl}$ref');
  }
  return AssetImage(ref);
}

/// Avatar widget with gradient fallback. A missing, broken or still-loading
/// photo renders the initials gradient instead of an empty circle.
class AvatarWidget extends StatelessWidget {
  final String? imagePath;
  final String? initials;
  final double size;
  final int gradientIndex;
  final VoidCallback? onTap;

  const AvatarWidget({
    super.key,
    this.imagePath,
    this.initials,
    this.size = AppSpacing.avatarMd,
    this.gradientIndex = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final provider = avatarImageProvider(imagePath);
    final fallback = _InitialsFill(
      initials: initials,
      size: size,
      gradientIndex: gradientIndex,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: ClipOval(
          child: provider == null
              ? fallback
              : Image(
                  image: provider,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, wasSync) =>
                      wasSync || frame != null ? child : fallback,
                  errorBuilder: (context, error, stack) => fallback,
                ),
        ),
      ),
    );
  }
}

class _InitialsFill extends StatelessWidget {
  const _InitialsFill({
    required this.initials,
    required this.size,
    required this.gradientIndex,
  });

  final String? initials;
  final double size;
  final int gradientIndex;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors
            .avatarGradients[gradientIndex % AppColors.avatarGradients.length],
      ),
      child: SizedBox.expand(
        child: initials == null
            ? null
            : Center(
                child: Text(
                  initials!,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: Colors.white,
                    fontSize: size * 0.4,
                  ),
                ),
              ),
      ),
    );
  }
}
