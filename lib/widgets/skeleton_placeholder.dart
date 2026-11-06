import 'package:flutter/material.dart';

/// A single shimmer-style block used while data loads.
///
/// Intentionally non-animating: a repeating animation would hang
/// `pumpAndSettle()` in widget tests, and the loading state is transient
/// anyway. A soft, static silhouette reads as "loading" without that cost.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 10,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A vertical stack of skeleton rows approximating a loading list.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 4, this.itemHeight = 120});

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      // Shrink to content height so the skeleton is safe inside an
      // unbounded parent (e.g. a DataView loading state nested in a
      // SingleChildScrollView/Column), where a fill-viewport ListView
      // would throw "Vertical viewport was given unbounded height".
      shrinkWrap: true,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: itemHeight, radius: 16),
          const SizedBox(height: 10),
          const SkeletonBox(width: 160, height: 14),
          const SizedBox(height: 8),
          const SkeletonBox(width: 96, height: 12),
        ],
      ),
    );
  }
}
