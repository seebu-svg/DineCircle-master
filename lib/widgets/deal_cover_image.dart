import 'package:flutter/material.dart';

import 'media_image.dart';

/// Cover art for a deal, rendered from the server's `coverImage` value.
///
/// The deals feed coalesces `restaurant_deals.image_url` with the venue's
/// `cover_image`, and both columns have historically carried repo-relative
/// asset paths (`assets/images/dish_steak.png`) while newer partner uploads
/// store remote URLs. [MediaImage] picks the right loader per source and always
/// degrades to a branded placeholder tile instead of throwing when the image is
/// missing.
///
/// Wrap it in a sized/clipped parent (as the deal cards and detail hero do);
/// the widget itself fills that box.
class DealCoverImage extends StatelessWidget {
  const DealCoverImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
  });

  /// Raw `coverImage` string from a [Deal]; may be null or empty.
  final String? source;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return MediaImage(source: source, fit: fit);
  }
}
