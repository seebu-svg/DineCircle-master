import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/deal.dart';
import '../../models/restaurant.dart';
import '../../models/search.dart';
import '../../providers/deals_provider.dart';
import '../../providers/location_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debouncer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/data_view.dart';
import '../../widgets/deal_cover_image.dart';
import '../restaurant_detail/restaurant_profile_route.dart';
import '../search/universal_search_screen.dart';
import 'deal_ui.dart';
import 'deal_detail_screen.dart';

/// Deals tab, premium "Discover Deals" experience.
///
/// Reads the live, city-scoped `GET /api/deals` feed (the server only ever
/// returns active, published, non-expired deals) and layers on search, kind
/// filters, a Featured carousel, a Limited-Time Offers rail and image-led deal
/// cards. Every deal opens the Deal Details screen; the venue behind it opens
/// the shared Restaurant Profile. No payments anywhere, offers are redeemed
/// directly at the restaurant.
class DealsScreen extends ConsumerStatefulWidget {
  const DealsScreen({
    super.key,
    this.onRestaurantTap,
    this.onLocationTap,
  });

  final void Function(Restaurant restaurant)? onRestaurantTap;
  final VoidCallback? onLocationTap;

  @override
  ConsumerState<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends ConsumerState<DealsScreen> {
  /// (query kind, chip label) pairs. `nearby` is client-side only: the feed
  /// is already city-scoped, so it narrows results to deals carrying the
  /// selected city.
  static const List<(String, String)> _kinds = [
    ('all', 'All Deals'),
    ('percent', 'Percentage'),
    ('fixed', 'Fixed Discount'),
    ('package', 'Packages'),
    ('nearby', 'Nearby'),
  ];

  final TextEditingController _searchController = TextEditingController();
  final Debouncer _debounce = Debouncer(const Duration(milliseconds: 300));
  String _kind = 'all';
  String _query = '';

  @override
  void dispose() {
    _debounce.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Server-backed with a 300 ms debounce: the old client-side `contains` check
  /// silently missed every deal beyond the first page.
  void _onSearchChanged(String value) {
    _debounce.run(() {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  void _openUniversalSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UniversalSearchScreen(
          initialQuery: _query,
          initialCategory: SearchCategory.deals,
          autofocus: _query.isEmpty,
          onLocationTap: widget.onLocationTap,
        ),
      ),
    );
  }

  /// Server query kind ('' = unfiltered). `all` and `nearby` need no server
  /// filter: Nearby narrows the already-resolved city feed client-side.
  String get _serverKind => (_kind == 'all' || _kind == 'nearby') ? '' : _kind;

  void _openDetail(Deal deal) {
    openDealDetail(context, deal, onRestaurantTap: widget.onRestaurantTap);
  }

  void _openVenue(Deal deal) {
    final cb = widget.onRestaurantTap;
    if (cb != null) {
      cb(
        Restaurant(
          id: deal.restaurantId,
          name: deal.restaurantName,
          description: '',
          cuisine: '',
          address: deal.city ?? '',
          city: deal.city,
          imagePath: deal.coverImage,
        ),
      );
      return;
    }
    openRestaurantProfile(context, id: deal.restaurantId);
  }

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(userCityProvider);
    final search = DealSearch(city: city, kind: _serverKind, query: _query);
    final dealsAsync = ref.watch(dealsFeedProvider(search));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(dealsFeedProvider(search)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              _buildHeader(city),
              // Horizontally scrollable filter chips, full-bleed under the
              // header so the row can scroll past the screen padding.
              _FilterChipRow(
                kinds: _kinds,
                selectedKind: _kind,
                onKindSelected: (kind) => setState(() => _kind = kind),
              ),
              DataView<List<Deal>>(
                value: dealsAsync,
                isEmpty: (deals) => deals.isEmpty,
                emptyMessage: _query.isNotEmpty
                    ? 'No active deals match "$_query". Try another keyword or '
                          'clear the search.'
                    : city.trim().isEmpty
                    ? 'No active deals right now. Partner restaurants publish '
                          'new offers all the time. Check back soon.'
                    : 'No active deals in $city right now. Try another city or '
                          'check back soon.',
                onRetry: () => ref.invalidate(dealsFeedProvider(search)),
                builder: (_, deals) {
                  // Nearby stays client-side: the feed is already city-scoped,
                  // so it only narrows to deals carrying the selected city.
                  var visible = deals;
                  if (_kind == 'nearby') {
                    final normalizedCity = city.trim().toLowerCase();
                    visible = visible
                        .where(
                          (d) => (d.city ?? '').trim().toLowerCase() ==
                              normalizedCity,
                        )
                        .toList();
                  }

                  if (visible.isEmpty) {
                    return _FilteredEmptyState(
                      onClear: () {
                        setState(() {
                          _kind = 'all';
                          _query = '';
                          _searchController.clear();
                        });
                      },
                    );
                  }

                  final featured = _featured(visible);
                  final limited =
                      visible
                          .where(DealUi.isExpiringSoon)
                          .toList()
                        ..sort((a, b) => a.endsAt.compareTo(b.endsAt));
                  final limitedIds = limited.map((d) => d.id).toSet();
                  final listDeals = visible
                      .where((d) => !limitedIds.contains(d.id))
                      .toList();
                  // When everything on screen is a limited-time deal, don't
                  // render an empty list section under the rail.
                  final sectionDeals = listDeals.isEmpty ? visible : listDeals;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (featured.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const _CarouselHeader(title: 'Featured Deals'),
                        _FeaturedCarousel(
                          deals: featured,
                          onDealTap: _openDetail,
                        ),
                      ],
                      if (limited.isNotEmpty && _query.isEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const _CarouselHeader(
                          title: 'Limited-Time Offers',
                          icon: Icons.bolt_rounded,
                          color: AppColors.danger,
                        ),
                        _LimitedTimeRail(
                          deals: limited,
                          onDealTap: _openDetail,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ] else ...[
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      SectionHeader(
                        title: _kind == 'nearby'
                            ? 'Deals Near You'
                            : (city.trim().isEmpty
                                  ? 'All Deals'
                                  : 'Deals in $city'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (final deal in sectionDeals)
                        Padding(
                          key: ValueKey('deal-${deal.id}'),
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.md,
                          ),
                          child: _PremiumDealCard(
                            deal: deal,
                            onTap: () => _openDetail(deal),
                            onVenueTap: () => _openVenue(deal),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top few strongest deals that carry cover art, for the hero carousel.
  /// Falls back to the strongest deals overall when art coverage is thin.
  List<Deal> _featured(List<Deal> visible) {
    final ranked = [...visible]
      ..sort((a, b) => DealUi.rank(b).compareTo(DealUi.rank(a)));
    final withArt = ranked
        .where((d) => (d.coverImage?.trim() ?? '').isNotEmpty)
        .toList();
    final pool = withArt.length >= 2 ? withArt : ranked;
    return pool.take(6).toList();
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(String city) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        AppSpacing.md,
        AppSpacing.paddingScreen,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Discover Deals',
                  style: AppTextStyles.displaySmall.copyWith(fontSize: 26),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _LocationChip(city: city, onTap: widget.onLocationTap),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Exclusive offers from your favourite restaurants. Redeem '
            'directly at the venue.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SearchField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            onOpenFullSearch: _openUniversalSearch,
            onClear: () {
              _searchController.clear();
              setState(() => _query = '');
            },
          ),
        ],
      ),
    );
  }
}

// ─── Header pieces ──────────────────────────────────────────────────────────

/// City selector, mirroring the Home / Explore header chip style.
class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.city, this.onTap});

  final String city;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = city.trim().isEmpty ? 'Set location' : city;
    return Semantics(
      button: true,
      label: 'Choose location',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded search field for restaurants, deals and food items.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onOpenFullSearch,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Hands the current term to the universal search screen so the diner can
  /// widen the hunt to venues, dishes, experiences and hosts in one tap.
  final VoidCallback onOpenFullSearch;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search restaurants, deals, food items…',
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textSecondary,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, child) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: onClear,
                );
              },
            ),
            IconButton(
              key: const Key('dealsOpenUniversalSearch'),
              tooltip: 'Search everything',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.manage_search_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              onPressed: onOpenFullSearch,
            ),
          ],
        ),
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

/// Horizontally scrollable kind chips, never wrap onto multiple rows.
class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.kinds,
    required this.selectedKind,
    required this.onKindSelected,
  });

  final List<(String, String)> kinds;
  final String selectedKind;
  final ValueChanged<String> onKindSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingScreen,
        ),
        children: [
          for (final (kind, label) in kinds)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TagChip(
                label: label,
                isSelected: selectedKind == kind,
                onTap: () => onKindSelected(kind),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Empty state for filtered-out results ───────────────────────────────────

/// Honest "nothing matches the current filters" panel with a one-tap reset.
class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No deals match your filters',
        message: 'Try a different search term or filter, or reset to see '
            'every active deal.',
        action: TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Clear filters'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

// ─── Section header with icon ───────────────────────────────────────────────

class _CarouselHeader extends StatelessWidget {
  const _CarouselHeader({
    required this.title,
    this.icon,
    this.color = AppColors.primary,
  });

  final String title;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.headlineMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Featured carousel ──────────────────────────────────────────────────────

/// Horizontal carousel of hero deal cards with large cover art.
class _FeaturedCarousel extends StatelessWidget {
  const _FeaturedCarousel({required this.deals, required this.onDealTap});

  final List<Deal> deals;
  final ValueChanged<Deal> onDealTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 236,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingScreen,
        ),
        itemCount: deals.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, i) {
          final deal = deals[i];
          final urgency = DealUi.urgencyLabel(deal);
          return Semantics(
            button: true,
            label: 'Featured deal ${deal.title}',
            child: GestureDetector(
              onTap: () => onDealTap(deal),
              child: Container(
                width: 268,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  border: Border.all(color: AppColors.borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DealCoverImage(source: deal.coverImage),
                    // Legibility scrim, weighted to top and bottom.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black54,
                            Colors.transparent,
                            Colors.black87,
                          ],
                          stops: [0.0, 0.35, 1.0],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Row(
                        children: [
                          DealBadge(deal: deal, onDark: true),
                          const Spacer(),
                          if (urgency != null)
                            Flexible(
                              child: DealPill(
                                label: urgency,
                                icon: Icons.schedule_rounded,
                                color: AppColors.danger,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            deal.restaurantName,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            deal.title,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Valid till ${DealUi.date(deal.endsAt)}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: Colors.white.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                'View Deal →',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Limited-time rail ──────────────────────────────────────────────────────

/// Compact horizontal rail for deals expiring within a week.
class _LimitedTimeRail extends StatelessWidget {
  const _LimitedTimeRail({required this.deals, required this.onDealTap});

  final List<Deal> deals;
  final ValueChanged<Deal> onDealTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingScreen,
        ),
        itemCount: deals.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (_, i) {
          final deal = deals[i];
          return Semantics(
            button: true,
            label: 'Limited-time deal ${deal.title}',
            child: GestureDetector(
              onTap: () => onDealTap(deal),
              child: Container(
                width: 210,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.35),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 96,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DealCoverImage(source: deal.coverImage),
                          Positioned(
                            top: AppSpacing.xs,
                            left: AppSpacing.xs,
                            child: DealBadge(deal: deal, onDark: true),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deal.title,
                              style: AppTextStyles.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Expanded(
                              child: Text(
                                deal.restaurantName,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 12,
                                  color: AppColors.danger,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    DealUi.urgencyLabel(deal) ??
                                        'Ends ${DealUi.date(deal.endsAt)}',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Premium vertical deal card ─────────────────────────────────────────────

/// Full-width, image-led card: large cover photo with floating badges, then
/// venue, title, concise copy and a clear View Deal action.
class _PremiumDealCard extends StatelessWidget {
  const _PremiumDealCard({
    required this.deal,
    required this.onTap,
    required this.onVenueTap,
  });

  final Deal deal;
  final VoidCallback onTap;
  final VoidCallback onVenueTap;

  @override
  Widget build(BuildContext context) {
    final urgency = DealUi.urgencyLabel(deal);
    final remaining = deal.maxRedemptions != null && deal.maxRedemptions! > 0
        ? (deal.maxRedemptions! - deal.redemptions).clamp(0, deal.maxRedemptions!)
        : null;
    return Semantics(
      button: true,
      label: 'View deal ${deal.title}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cover art with floating badges ──
              SizedBox(
                height: 168,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DealCoverImage(source: deal.coverImage),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black45,
                            Colors.transparent,
                            Colors.black87,
                          ],
                          stops: [0.0, 0.4, 1.0],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                    Positioned(
                      top: AppSpacing.md,
                      left: AppSpacing.md,
                      child: DealBadge(deal: deal, onDark: true),
                    ),
                    if (urgency != null)
                      Positioned(
                        top: AppSpacing.md,
                        right: AppSpacing.md,
                        child: DealPill(
                          label: urgency,
                          icon: Icons.schedule_rounded,
                          color: AppColors.danger,
                        ),
                      ),
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.sm,
                      child: Semantics(
                        button: true,
                        label: 'View ${deal.restaurantName} profile',
                        child: GestureDetector(
                          onTap: onVenueTap,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.storefront_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  deal.restaurantName,
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Body ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deal.title,
                      style: AppTextStyles.headlineSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (deal.description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        deal.description,
                        style: AppTextStyles.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              if (deal.city != null &&
                                  deal.city!.trim().isNotEmpty)
                                DealPill(
                                  label: deal.city!.trim(),
                                  icon: Icons.location_on_outlined,
                                ),
                              if (deal.requiresCode)
                                DealPill(
                                  label: deal.code!,
                                  icon:
                                      Icons.confirmation_number_outlined,
                                  color: AppColors.gold,
                                ),
                              if (remaining != null)
                                DealPill(
                                  label: '$remaining left',
                                  icon:
                                      Icons.local_fire_department_outlined,
                                  color: AppColors.warning,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _ViewDealButton(onTap: onTap),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewDealButton extends StatelessWidget {
  const _ViewDealButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View deal',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View Deal',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
