import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/dinner.dart';
import '../../models/restaurant.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/restaurants_provider.dart';
import '../../providers/social_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/data_view.dart';
import '../../widgets/media_image.dart';
import '../detail/dinner_detail_screen.dart';
import '../restaurant_detail/restaurant_profile_route.dart';

/// Saved screen, everything the signed-in diner has bookmarked.
///
/// Two server-backed tabs:
///   * **Experiences**: `GET /me/saved` through [savedEventsProvider].
///   * **Restaurants**: `GET /me/followed-restaurants` through
///     [followedVenuesProvider]; unfollowing from here removes the row.
///
/// [initialTab] lets the Profile activity shortcuts deep-link straight into a
/// tab (1 = Restaurants) without a second navigator entry point.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Experiences'),
              Tab(text: 'Restaurants'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SavedExperiencesTab(),
            const _SavedRestaurantsTab(),
          ],
        ),
      ),
    );
  }
}

// ─── Experiences ────────────────────────────────────────────────────────────

class _SavedExperiencesTab extends ConsumerWidget {
  const _SavedExperiencesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(savedEventsProvider);

    return DataView<List<Dinner>>(
      value: savedAsync,
      onRetry: () => ref.invalidate(savedEventsProvider),
      isEmpty: (data) => data.isEmpty,
      emptyWidget: const EmptyStateView(
        icon: Icons.bookmark_border_rounded,
        message:
            'No saved dinners yet. Tap the bookmark on any dinner to save it.',
      ),
      builder: (context, dinners) {
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.paddingScreen),
          itemCount: dinners.length,
          itemBuilder: (context, index) {
            final dinner = dinners[index];
            return _SavedDinnerTile(
              dinner: dinner,
              onTap: () {
                ref.invalidate(savedEventsProvider);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DinnerDetailScreen(dinner: dinner),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SavedDinnerTile extends StatelessWidget {
  final Dinner dinner;
  final VoidCallback onTap;

  const _SavedDinnerTile({required this.dinner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: Image.asset(
                  dinner.imagePath ?? 'assets/images/hero_tasting.png',
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dinner.title, style: AppTextStyles.titleSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      dinner.restaurant.name,
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${dinner.formattedDate} - Rs ${dinner.pricePerSeat.toStringAsFixed(0)}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.bookmark_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Restaurants ────────────────────────────────────────────────────────────

/// Venues bookmarked through `POST/DELETE /restaurants/:id/follow`.
class _SavedRestaurantsTab extends ConsumerStatefulWidget {
  const _SavedRestaurantsTab();

  @override
  ConsumerState<_SavedRestaurantsTab> createState() =>
      _SavedRestaurantsTabState();
}

class _SavedRestaurantsTabState extends ConsumerState<_SavedRestaurantsTab> {
  /// The venue currently being unfollowed, so its bookmark shows a spinner
  /// instead of accepting a second tap.
  String? _busyId;

  Future<void> _unfollow(Restaurant restaurant) async {
    if (_busyId != null) return;
    setState(() => _busyId = restaurant.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(restaurantsRepositoryProvider)
          .setFollowing(restaurant.id, false);
      ref.invalidate(followedVenuesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not update your saved restaurants.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final venuesAsync = ref.watch(followedVenuesProvider);

    return DataView<List<Restaurant>>(
      value: venuesAsync,
      onRetry: () => ref.invalidate(followedVenuesProvider),
      isEmpty: (data) => data.isEmpty,
      emptyWidget: const EmptyStateView(
        icon: Icons.bookmark_border_rounded,
        message:
            'No saved restaurants yet. Tap Save on any restaurant to keep it '
            'here.',
      ),
      builder: (context, restaurants) {
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.paddingScreen),
          itemCount: restaurants.length,
          itemBuilder: (context, index) {
            final restaurant = restaurants[index];
            return _SavedRestaurantTile(
              restaurant: restaurant,
              busy: _busyId == restaurant.id,
              onTap: () => openRestaurantProfile(context, seed: restaurant),
              onUnsave: () => _unfollow(restaurant),
            );
          },
        );
      },
    );
  }
}

class _SavedRestaurantTile extends StatelessWidget {
  const _SavedRestaurantTile({
    required this.restaurant,
    required this.busy,
    required this.onTap,
    required this.onUnsave,
  });

  final Restaurant restaurant;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onUnsave;

  @override
  Widget build(BuildContext context) {
    final city = (restaurant.city ?? '').trim();
    final subtitle = [
      restaurant.cuisine.trim(),
      city,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: MediaImage(
                    source: restaurant.imagePath,
                    cacheWidth: 128,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    RatingPill(
                      rating: restaurant.rating,
                      reviewCount: restaurant.reviewCount,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: busy ? null : onUnsave,
                tooltip: 'Remove from saved',
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.bookmark_rounded,
                        color: AppColors.primary,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
