import 'package:flutter/material.dart';

import '../../models/dinner.dart';
import '../../models/restaurant.dart';
import '../detail/dinner_detail_screen.dart';
import 'restaurant_detail_screen.dart';

/// Canonical entry point for every surface that opens a restaurant profile:
/// nearby list, search results, QR scan, deep link.
///
/// Pass [seed] when the caller already has a slim `Restaurant` (instant paint
/// while `/restaurants/:id` hydrates). Pass [id] when the caller only knows
/// the venue id (QR scan, deep link, manual code entry) — the profile will
/// show a skeleton until the fetch resolves.
///
/// [onDinnerTap] overrides how an experience row opens; it defaults to pushing
/// [DinnerDetailScreen] so every entry point gets working experience taps
/// without each caller wiring its own handler.
Future<T?> openRestaurantProfile<T extends Object?>(
  BuildContext context, {
  Restaurant? seed,
  String? id,
  void Function(Dinner dinner)? onDinnerTap,
}) {
  assert(
    seed != null || (id != null && id.isNotEmpty),
    'openRestaurantProfile: provide a seed or an id.',
  );
  return Navigator.push<T>(
    context,
    MaterialPageRoute<T>(
      builder: (routeContext) => RestaurantDetailScreen(
        restaurant: seed,
        restaurantId: id,
        onDinnerTap:
            onDinnerTap ??
            (dinner) => Navigator.push(
              routeContext,
              MaterialPageRoute(
                builder: (_) => DinnerDetailScreen(dinner: dinner),
              ),
            ),
      ),
    ),
  );
}
