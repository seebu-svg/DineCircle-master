import 'package:flutter/material.dart';

import '../../models/deal.dart';
import '../../models/dinner.dart';
import '../../models/restaurant.dart';
import '../../models/search.dart';
import '../../models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/money.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/media_image.dart';
import '../deals/deal_detail_screen.dart';
import '../detail/dinner_detail_screen.dart';
import '../qr_menu/qr_menu_screen.dart';
import '../restaurant_detail/restaurant_profile_route.dart';
import '../user_profile/user_profile_screen.dart';

/// Opens the surface that owns [hit].
///
/// Every search section routes through here so the five result types can never
/// drift apart: a venue opens the shared Restaurant Profile, a dish the venue's
/// menu pre-filtered to that dish, a deal its detail page, an experience the
/// dinner detail page and a host their profile.
void openSearchHit(BuildContext context, Object hit) {
  switch (hit) {
    case Restaurant restaurant:
      openRestaurantProfile(context, seed: restaurant);
    case MenuItemHit item:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QrMenuScreen(
            restaurantId: item.restaurantId,
            initialQuery: item.name,
          ),
        ),
      );
    case Deal deal:
      openDealDetail(context, deal);
    case Dinner dinner:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DinnerDetailScreen(dinner: dinner)),
      );
    case UserProfile host:
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserProfileScreen(user: host)),
      );
  }
}

/// One universal-search result: 72 px thumbnail, title, location line, and a
/// row of supporting facts. Deliberately one silhouette for all five entity
/// types so the list scans as a single ranked set.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.title,
    required this.onTap,
    this.thumbnail,
    this.subtitle,
    this.detail,
    this.meta = const [],
    this.badge,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? thumbnail;
  final String? subtitle;
  final String? detail;

  /// Small fact chips (rating, price, distance, tags) rendered under the text.
  final List<Widget> meta;

  /// Leading label identifying the entity type (`Dish`, `Deal`, …).
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open $title',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbnail != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: thumbnail,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTextStyles.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _Badge(label: badge!),
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (detail != null && detail!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: meta,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Venue hit: cover art, name, `neighborhood · city`, rating and cuisine.
class RestaurantResultTile extends StatelessWidget {
  const RestaurantResultTile({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return SearchResultTile(
      key: Key('searchTile_${restaurant.id}'),
      title: restaurant.name,
      subtitle: [restaurant.cuisine, restaurant.locationLine]
          .where((part) => part.trim().isNotEmpty)
          .join(' · '),
      thumbnail: MediaImage(
        source: restaurant.imagePath,
        fallbackIcon: Icons.restaurant_rounded,
        cacheWidth: 180,
      ),
      meta: [
        if (restaurant.reviewCount > 0)
          RatingPill(
            rating: restaurant.rating,
            reviewCount: restaurant.reviewCount,
          ),
        _Badge(label: restaurant.priceRangeLabel),
        if (restaurant.isFollowing) const _Badge(label: 'Saved'),
      ],
      onTap: () => openSearchHit(context, restaurant),
    );
  }
}

/// Dish hit: photo, dish name, section + venue, price and location.
class MenuItemResultTile extends StatelessWidget {
  const MenuItemResultTile({super.key, required this.item});

  final MenuItemHit item;

  @override
  Widget build(BuildContext context) {
    return SearchResultTile(
      key: Key('searchTile_${item.id}'),
      title: item.name,
      badge: 'Dish',
      subtitle: item.subtitle,
      detail: item.locationLine,
      thumbnail: MediaImage(
        source: item.photoUrl,
        fallbackIcon: Icons.local_dining_rounded,
        cacheWidth: 180,
      ),
      meta: [
        _Badge(label: formatPkr(item.price), highlight: true),
        for (final tag in item.dietaryTags.take(2)) _Badge(label: tag),
      ],
      onTap: () => openSearchHit(context, item),
    );
  }
}

/// Deal hit: cover art, title, venue, discount label and expiry.
class DealResultTile extends StatelessWidget {
  const DealResultTile({super.key, required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    return SearchResultTile(
      key: Key('searchTile_${deal.id}'),
      title: deal.title,
      badge: 'Deal',
      subtitle: deal.restaurantName,
      detail: deal.description,
      thumbnail: MediaImage(
        source: deal.coverImage,
        fallbackIcon: Icons.local_offer_rounded,
        cacheWidth: 180,
      ),
      meta: [
        _Badge(label: deal.kindLabel, highlight: true),
        if ((deal.city ?? '').trim().isNotEmpty)
          _Badge(label: deal.city!.trim()),
        _Badge(label: 'Ends ${_shortDate(deal.endsAt)}'),
      ],
      onTap: () => openSearchHit(context, deal),
    );
  }
}

/// Experience hit: cover art, title, venue, date and price per seat.
class ExperienceResultTile extends StatelessWidget {
  const ExperienceResultTile({super.key, required this.dinner});

  final Dinner dinner;

  @override
  Widget build(BuildContext context) {
    final left = dinner.isFull ? 'Fully booked' : '${dinner.availableSeats} seats left';
    return SearchResultTile(
      key: Key('searchTile_${dinner.id}'),
      title: dinner.title,
      badge: 'Experience',
      subtitle: dinner.restaurant.name,
      detail: dinner.description,
      thumbnail: MediaImage(
        source: dinner.imagePath,
        fallbackIcon: Icons.people_alt_rounded,
        cacheWidth: 180,
      ),
      meta: [
        _Badge(
          label: '${dinner.formattedDate} · ${dinner.formattedTime}',
          highlight: true,
        ),
        _Badge(label: formatPkr(dinner.pricePerSeat)),
        _Badge(label: left),
      ],
      onTap: () => openSearchHit(context, dinner),
    );
  }
}

/// Host hit: avatar, name/handle, follower count and hosted dinners.
class HostResultTile extends StatelessWidget {
  const HostResultTile({super.key, required this.host});

  final UserProfile host;

  @override
  Widget build(BuildContext context) {
    return SearchResultTile(
      key: Key('searchTile_${host.id}'),
      title: host.name,
      badge: 'Host',
      subtitle: host.handle.trim().isEmpty ? null : '@${host.handle.trim()}',
      detail: host.bio,
      thumbnail: AvatarWidget(
        imagePath: host.avatarPath,
        initials: host.initials,
        size: 72,
        gradientIndex: host.id.hashCode,
      ),
      meta: [
        _Badge(label: '${host.followers} followers'),
        if (host.dinnersHosted > 0)
          _Badge(label: '${host.dinnersHosted} dinners hosted'),
        if (host.isVerified) const _Badge(label: 'Verified', highlight: true),
      ],
      onTap: () => openSearchHit(context, host),
    );
  }
}

/// Compact pill used for type labels and facts inside a tile.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.primary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// `24 Aug`, short enough for a chip, unambiguous because it carries the year
/// only when the date is not in the current year.
String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[date.month - 1];
  final sameYear = date.year == DateTime.now().year;
  return sameYear ? '${date.day} $month' : '${date.day} $month ${date.year}';
}
