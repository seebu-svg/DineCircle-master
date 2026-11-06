import 'package:flutter/material.dart';

/// The DineCircle mark: the orange arc, the "D" and the fork.
///
/// `assets/images/brand_mark.png` is projected from the authored lockup in
/// `assets/branding/dinecircle_master.png` by
/// `tool/branding/generate_brand_assets.py`, which crops the mark out of the
/// lockup and keys its dark field to alpha. Drawing the asset (instead of the
/// gradient badge + Material fork glyph it replaced) keeps the logo inside the
/// app identical to the launcher icon, and lets the mark sit on any background.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96, this.semanticLabel = 'DineCircle'});

  /// Height and width of the mark, in logical pixels.
  final double size;

  /// Semantics label, or null to keep the mark decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/brand_mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
    );
  }
}
