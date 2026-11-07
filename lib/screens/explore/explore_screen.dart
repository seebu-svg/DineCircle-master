import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Position;

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debouncer.dart';
import '../../models/dinner.dart';
import '../../models/restaurant.dart';
import '../../models/user_profile.dart';
import '../../models/deal.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/skeleton_placeholder.dart';
import '../../widgets/data_view.dart';
import '../../widgets/occasion_card.dart';
import '../../widgets/experience_card.dart';
import '../../providers/events_provider.dart';
import '../../providers/restaurants_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/deals_provider.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/users_provider.dart';
import '../../repositories/users_repository.dart';
import '../../api/api_exception.dart';
import '../deals/deal_detail_screen.dart';
import 'explore_deal_card.dart';
import '../map/map_screen.dart';
import '../search/universal_search_screen.dart';

/// The five primary discovery tabs.
enum _DiscoverTab { all, restaurants, cafes, experiences, hosts }

extension _DiscoverTabX on _DiscoverTab {
  String get label => switch (this) {
    _DiscoverTab.all => 'All',
    _DiscoverTab.restaurants => 'Restaurants',
    _DiscoverTab.cafes => 'Cafés',
    _DiscoverTab.experiences => 'Experiences',
    _DiscoverTab.hosts => 'Hosts',
  };

  IconData get icon => switch (this) {
    _DiscoverTab.all => Icons.explore_rounded,
    _DiscoverTab.restaurants => Icons.restaurant_rounded,
    _DiscoverTab.cafes => Icons.local_cafe_rounded,
    _DiscoverTab.experiences => Icons.workspace_premium_rounded,
    _DiscoverTab.hosts => Icons.people_alt_rounded,
  };
}

/// Curated occasion items for the "Discover by occasion" section.
/// Each occasion maps to a real venue tag so taps filter live data.
const List<OccasionItem> _occasions = [
  OccasionItem(
    title: 'Date Night',
    subtitle: 'Romantic tables for two',
    icon: Icons.favorite_rounded,
    accent: AppColors.danger,
    assetImage: 'assets/images/dish_steak.png',
    venueTag: 'date-night',
  ),
  OccasionItem(
    title: 'Friends & Family',
    subtitle: 'Group dining experiences',
    icon: Icons.groups_rounded,
    accent: AppColors.primary,
    assetImage: 'assets/images/dish_brunch.png',
    venueTag: 'family',
  ),
  OccasionItem(
    title: 'Celebrations',
    subtitle: 'Mark special moments',
    icon: Icons.celebration_rounded,
    accent: AppColors.gold,
    assetImage: 'assets/images/dish_dessert.png',
    venueTag: 'heritage',
  ),
  OccasionItem(
    title: 'Casual & Cozy',
    subtitle: 'Relaxed neighbourhood gems',
    icon: Icons.local_cafe_rounded,
    accent: AppColors.success,
    assetImage: 'assets/images/dish_pasta.png',
    venueTag: 'cozy',
  ),
  OccasionItem(
    title: 'Business Dining',
    subtitle: 'Impress clients & colleagues',
    icon: Icons.business_center_rounded,
    accent: AppColors.info,
    assetImage: 'assets/images/dish_sushi.png',
    venueTag: 'premium',
  ),
];

/// Discover screen, premium dining discovery interface.
///
/// Four tabs (All / Places / Offers / Experiences) replace the old triple-chip
/// navigation. Occasion cards, curated experience lists, and dedicated deal
/// sections provide a concierge-style browsing experience.
class ExploreScreen extends ConsumerStatefulWidget {
  final void Function(Dinner dinner) onDinnerTap;
  final void Function(Restaurant restaurant)? onRestaurantTap;
  final void Function(UserProfile user)? onUserTap;
  final VoidCallback? onLocationTap;

  const ExploreScreen({
    super.key,
    required this.onDinnerTap,
    this.onRestaurantTap,
    this.onUserTap,
    this.onLocationTap,
  });

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  final Debouncer _debounce = Debouncer(const Duration(milliseconds: 400));
  _DiscoverTab _selectedTab = _DiscoverTab.all;
  String _query = '';
  String _venueTag = '';
  String? _cuisine;
  bool _showMap = false;
  final Set<String> _savingRestaurantIds = {};

  // Filter-sheet state
  String? _audience;
  String? _type;
  double? _maxPrice;
  int _days = 0;

  /// Helper for the tab-content extension to call `setState` without
  /// tripping the `@protected` lint (extensions are not subclasses).
  void _updateVenueTag(String tag) => setState(() => _venueTag = tag);
  void _updateCuisine(String? cuisine) => setState(() => _cuisine = cuisine);
  void _toggleMapView() => setState(() => _showMap = !_showMap);

  /// Toggle save/follow state for a restaurant via the repository.
  Future<void> _toggleSave(Restaurant r) async {
    if (_savingRestaurantIds.contains(r.id)) return;
    setState(() => _savingRestaurantIds.add(r.id));
    final next = !r.isFollowing;
    try {
      final result = await ref
          .read(restaurantsRepositoryProvider)
          .setFollowing(r.id, next);
      if (mounted) {
        setState(() => _savingRestaurantIds.remove(r.id));
        ref.invalidate(nearbyRestaurantsProvider);
        ref.invalidate(
          venueSearchProvider(VenueSearch(query: _query, tag: _venueTag)),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result ? 'Saved' : 'Removed'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _savingRestaurantIds.remove(r.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Occasion card tap: set the venue tag and switch to Restaurants tab.
  void _onOccasionTap(OccasionItem occ) {
    if (occ.venueTag != null) {
      setState(() {
        _venueTag = occ.venueTag!;
        _selectedTab = _DiscoverTab.restaurants;
      });
    }
  }

  static const _venueTags = <String>[
    'fine dining',
    'casual',
    'rooftop',
    'cafe',
  ];

  @override
  void dispose() {
    _debounce.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Location-denied banner shown above the venue list when GPS is off or
  /// permission was denied. Offers actions to enable location or choose a city.
  Widget _buildLocationBanner() {
    final permissionAsync = ref.watch(locationPermissionProvider);
    final positionAsync = ref.watch(livePositionProvider);
    final city = ref.watch(userCityProvider);

    // Only show when permission is explicitly false or position has an error.
    final permissionDenied = permissionAsync.valueOrNull == false;
    final positionError = positionAsync.hasError;

    if (!permissionDenied && !positionError) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_off_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Location is off. Showing $city venues.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.warning,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => ref.invalidate(locationPermissionProvider),
                icon: const Icon(Icons.location_on_rounded, size: 16),
                label: const Text('Enable location'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton.icon(
                onPressed: widget.onLocationTap,
                icon: const Icon(Icons.edit_location_rounded, size: 16),
                label: const Text('Choose city'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Empty state with a "Clear filters" action when the filtered list is empty.
  Widget _buildClearFiltersEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_alt_off_rounded,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No restaurants match your filters.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            onPressed: () {
              _updateCuisine(null);
              _updateVenueTag('');
              _searchController.clear();
              setState(() => _query = '');
              ref.invalidate(
                venueSearchProvider(VenueSearch(query: _query, tag: _venueTag)),
              );
            },
            icon: const Icon(Icons.clear_rounded),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounce.run(() {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  /// Escapes Explore's scoped query into the complete search surface, keeping
  /// whatever the diner already typed.
  void _openUniversalSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UniversalSearchScreen(
          initialQuery: _query,
          autofocus: _query.isEmpty,
          onLocationTap: widget.onLocationTap,
        ),
      ),
    );
  }

  String? get _effectiveAudience {
    if (_audience != null) return _audience;
    return switch (_selectedTab) {
      _DiscoverTab.experiences => 'public',
      _ => null,
    };
  }

  String? get _effectiveType {
    if (_type != null) return _type;
    return switch (_selectedTab) {
      _DiscoverTab.experiences => 'tasting,supperClub,workshop,festival',
      _ => null,
    };
  }

  EventFilter get _eventFilter {
    final hasWindow = _days > 0;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    return EventFilter(
      query: _query.isEmpty ? null : _query,
      audience: _effectiveAudience,
      type: _effectiveType,
      maxPrice: _maxPrice,
      from: hasWindow ? from : null,
      to: hasWindow ? from.add(Duration(days: _days)) : null,
    );
  }

  Future<void> _showFilterSheet() async {
    final draft = await showModalBottomSheet<_ExploreFilterDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => _FilterSheet(
        initialAudience: _audience,
        initialType: _type,
        initialMaxPrice: _maxPrice,
        initialDays: _days,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _audience = draft.audience;
      _type = draft.type;
      _maxPrice = draft.maxPrice;
      _days = draft.days;
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dinnersAsync = ref.watch(eventsFeedProvider(_eventFilter));
    final restaurantsAsync = ref.watch(nearbyRestaurantsProvider);
    final fix = ref.watch(livePositionOrNullProvider);
    final venuesAsync = ref.watch(
      venueSearchProvider(VenueSearch(query: _query, tag: _venueTag)),
    );
    final city = ref.watch(userCityProvider);
    final dealsAsync = ref.watch(
      dealsFeedProvider(DealSearch(city: city)),
    );
    final hostsAsync = ref.watch(discoverHostsProvider);
    final topPad = MediaQuery.of(context).padding.top;
    // Title and tab rows grow with the user's font-size setting, so their
    // heights must scale too, fixed pixels overflow on devices set above 1.0.
    final textScaler = MediaQuery.textScalerOf(context);
    final headerHeight =
        topPad +
        AppSpacing.sm +
        textScaler.scale(32) +
        2 +
        textScaler.scale(14) +
        AppSpacing.md +
        48 +
        AppSpacing.md +
        textScaler.scale(40) +
        AppSpacing.xs +
        AppSpacing.sm;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeaderDelegate(
              height: headerHeight,
              child: SizedBox(
                height: headerHeight,
                child: ColoredBox(
                  color: AppColors.bg,
                  child: _DiscoverHeader(
                    city: city,
                    selectedTab: _selectedTab,
                    searchController: _searchController,
                    onSearchChanged: _onSearchChanged,
                    onTabChanged: (tab) => setState(() => _selectedTab = tab),
                    onFilterTap: _showFilterSheet,
                    onSearchTap: _openUniversalSearch,
                    onLocationTap: widget.onLocationTap,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildTabContent(
              dinnersAsync,
              restaurantsAsync,
              fix,
              venuesAsync,
              dealsAsync,
              hostsAsync,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(
    AsyncValue<List<Dinner>> dinnersAsync,
    AsyncValue<List<Restaurant>> restaurantsAsync,
    Position? fix,
    AsyncValue<List<Restaurant>> venuesAsync,
    AsyncValue<List<Deal>> dealsAsync,
    AsyncValue<List<RosterUser>> hostsAsync,
  ) {
    return switch (_selectedTab) {
      _DiscoverTab.all => _buildAllTab(
        dinnersAsync,
        restaurantsAsync,
        fix,
        dealsAsync,
        hostsAsync,
      ),
      _DiscoverTab.restaurants =>
        _buildRestaurantsTab(venuesAsync, fix, dealsAsync),
      _DiscoverTab.cafes => _buildCafesTab(venuesAsync, fix),
      _DiscoverTab.experiences => _buildExperiencesTab(dinnersAsync),
      _DiscoverTab.hosts => _buildHostsTab(hostsAsync),
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
}

// ────────────────────────────────────────────────────────────────────────────
// Discover header
// ────────────────────────────────────────────────────────────────────────────

class _DiscoverHeader extends StatelessWidget {
  final String city;
  final _DiscoverTab selectedTab;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_DiscoverTab> onTabChanged;
  final VoidCallback onFilterTap;

  /// Escapes the scoped query to the universal search screen.
  final VoidCallback onSearchTap;
  final VoidCallback? onLocationTap;

  const _DiscoverHeader({
    required this.city,
    required this.selectedTab,
    required this.searchController,
    required this.onSearchChanged,
    required this.onTabChanged,
    required this.onFilterTap,
    required this.onSearchTap,
    this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        MediaQuery.of(context).padding.top + AppSpacing.sm,
        AppSpacing.paddingScreen,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title + location chip
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Discover',
                      style: AppTextStyles.displaySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (city.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Explore dining in $city',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              GestureDetector(
                onTap: onLocationTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
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
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          city.isNotEmpty ? city : 'Set city',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: city.isNotEmpty
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Row 2: Search bar
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search restaurants, cuisines, experiences...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      hintStyle: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
                GestureDetector(
                  onTap: onFilterTap,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      Icons.tune_rounded,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                ),
                GestureDetector(
                  key: const Key('exploreOpenUniversalSearch'),
                  onTap: onSearchTap,
                  child: const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.sm),
                    child: Icon(
                      Icons.manage_search_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Row 3: Tab selector (horizontally scrollable for 5 tabs)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in _DiscoverTab.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: GestureDetector(
                      onTap: () => onTabChanged(tab),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: selectedTab == tab
                              ? AppColors.primaryGradient
                              : null,
                          color: selectedTab == tab
                              ? null
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                          border: Border.all(
                            color: selectedTab == tab
                                ? Colors.transparent
                                : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tab.icon,
                              size: 16,
                              color: selectedTab == tab
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              tab.label,
                              style: AppTextStyles.labelMedium.copyWith(
                                color: selectedTab == tab
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SliverPersistentHeader delegate
// ────────────────────────────────────────────────────────────────────────────

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

// ────────────────────────────────────────────────────────────────────────────
// Tab content builders
// ────────────────────────────────────────────────────────────────────────────

extension _ExploreTabContent on _ExploreScreenState {
  Widget _buildAllTab(
    AsyncValue<List<Dinner>> dinnersAsync,
    AsyncValue<List<Restaurant>> restaurantsAsync,
    Position? fix,
    AsyncValue<List<Deal>> dealsAsync,
    AsyncValue<List<RosterUser>> hostsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Featured discovery banner ──
        restaurantsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (restaurants) {
            if (restaurants.isEmpty) return const SizedBox.shrink();
            final hero = restaurants
                .where((r) => r.rating > 0)
                .toList()
              ..sort((a, b) => b.rating.compareTo(a.rating));
            final featured = hero.isNotEmpty ? hero.first : restaurants.first;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
              ),
              child: GestureDetector(
                onTap: () => widget.onRestaurantTap?.call(featured),
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusXxl,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (featured.imagePath != null &&
                          featured.imagePath!.isNotEmpty)
                        Image.asset(
                          featured.imagePath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black54,
                              Colors.black26,
                              Colors.black87,
                            ],
                            stops: [0.0, 0.35, 1.0],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      Positioned(
                        top: AppSpacing.md,
                        left: AppSpacing.md,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Featured',
                                style: AppTextStyles.caption.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.lg,
                        right: AppSpacing.lg,
                        bottom: AppSpacing.md,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              featured.name,
                              style: AppTextStyles.headlineSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (featured.rating > 0) ...[
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: AppColors.gold,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    featured.rating.toStringAsFixed(1),
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.gold,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                ],
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 12,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    featured.cuisine,
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: Colors.white.withValues(alpha: 0.9),
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
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),

        // ── Cuisine discovery (derived from live venues) ──
        restaurantsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (restaurants) {
            final cuisines = restaurants
                .expand((r) => r.cuisine.split(', '))
                .where((c) => c.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            if (cuisines.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'Explore cuisines'),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingScreen,
                  ),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final c in cuisines.take(8))
                        TagChip(
                          label: c,
                          isSelected: _cuisine == c,
                          onTap: () {
                            _updateCuisine(_cuisine == c ? null : c);
                            setState(() => _selectedTab = _DiscoverTab.restaurants);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),

        // ── Occasion cards (functional taps) ──
        SectionHeader(title: 'Discover by occasion'),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
            children: [
              for (final occ in _occasions)
                OccasionCard(
                  item: occ,
                  onTap: () => _onOccasionTap(occ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ── Top picks near you (restaurants with save) ──
        restaurantsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
            child: SkeletonList(itemCount: 3, itemHeight: 200),
          ),
          error: (error, _) => Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
            child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(nearbyRestaurantsProvider),
            ),
          ),
          data: (restaurants) {
            if (restaurants.isEmpty) return const SizedBox.shrink();
            final picks = restaurants.take(5).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'Top picks near you'),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.paddingScreen,
                    ),
                    itemCount: picks.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.md),
                      child: SizedBox(
                        width: 200,
                        child: _SaveableRestaurantCard(
                          restaurant: picks[i],
                          isSaving: _savingRestaurantIds.contains(picks[i].id),
                          onTap: () =>
                              widget.onRestaurantTap?.call(picks[i]),
                          onSave: () => _toggleSave(picks[i]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),

        // ── Upcoming experiences ──
        dinnersAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (dinners) {
            if (dinners.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Tonight & Upcoming',
                  actionText: 'See all',
                  onAction: () =>
                      setState(() => _selectedTab = _DiscoverTab.experiences),
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingScreen,
                  ),
                  child: Column(
                    children: [
                      for (final d in dinners.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ExperienceCard(
                            dinner: d,
                            onTap: () => widget.onDinnerTap(d),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),

        // ── Popular cafés (deduped against top picks) ──
        restaurantsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (restaurants) {
            final topIds = restaurants.take(5).map((r) => r.id).toSet();
            final cafes = restaurants
                .where((r) =>
                    !topIds.contains(r.id) &&
                    (r.tags.contains('cafe') ||
                        r.cuisine.toLowerCase().contains('cafe') ||
                        r.cuisine.toLowerCase().contains('coffee')))
                .toList();
            if (cafes.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'Popular cafés'),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.paddingScreen,
                    ),
                    itemCount: cafes.length.clamp(0, 5),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.md),
                      child: SizedBox(
                        width: 200,
                        child: _SaveableRestaurantCard(
                          restaurant: cafes[i],
                          isSaving:
                              _savingRestaurantIds.contains(cafes[i].id),
                          onTap: () =>
                              widget.onRestaurantTap?.call(cafes[i]),
                          onSave: () => _toggleSave(cafes[i]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),

        // ── Featured hosts ──
        hostsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (hosts) {
            if (hosts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'Featured hosts'),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.paddingScreen,
                    ),
                    itemCount: hosts.length.clamp(0, 6),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.md),
                      child: _HostChip(
                        user: hosts[i].user,
                        onTap: () => widget.onUserTap?.call(hosts[i].user),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),

        // ── Recommended deals ──
        dealsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (deals) {
            if (deals.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Recommended deals',
                  actionText: 'See all',
                  onAction: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 210,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.paddingScreen,
                    ),
                    itemCount: deals.length.clamp(0, 5),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.md),
                      child: SizedBox(
                        width: 220,
                        child: ExploreDealCard(
                          deal: deals[i],
                          onTap: () => openDealDetail(
                            context,
                            deals[i],
                            onRestaurantTap: widget.onRestaurantTap,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRestaurantsTab(
    AsyncValue<List<Restaurant>> venuesAsync,
    Position? fix,
    AsyncValue<List<Deal>> dealsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cuisine chips (derived from live venues)
        venuesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (venues) {
            final cuisines = venues
                .expand((r) => r.cuisine.split(', '))
                .where((c) => c.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            if (cuisines.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
              ),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TagChip(
                    label: 'All',
                    isSelected: _cuisine == null,
                    onTap: () => _updateCuisine(null),
                  ),
                  for (final c in cuisines.take(8))
                    TagChip(
                      label: c,
                      isSelected: _cuisine == c,
                      onTap: () => _updateCuisine(_cuisine == c ? null : c),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),

        // Venue type chips + map/list toggle
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final tag in ['All', ..._ExploreScreenState._venueTags])
                      TagChip(
                        label: tag,
                        isSelected:
                            (tag == 'All' && _venueTag.isEmpty) || _venueTag == tag,
                        onTap: () => _updateVenueTag(tag == 'All' ? '' : tag),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: Icon(
                  _showMap
                      ? Icons.list_rounded
                      : Icons.map_rounded,
                  color: AppColors.primary,
                ),
                tooltip: _showMap ? 'Show list' : 'Show map',
                onPressed: _toggleMapView,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Location-denied banner when GPS is off or permission denied.
        if (!_showMap) _buildLocationBanner(),

        // Escape hatch from this scoped query to the complete search surface.
        if (_query.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.paddingScreen,
              0,
              AppSpacing.paddingScreen,
              AppSpacing.sm,
            ),
            child: GestureDetector(
              key: const Key('exploreSeeAll'),
              onTap: _openUniversalSearch,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.manage_search_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'See all results for "$_query"',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Map view or list view
        if (_showMap)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: MapScreen(
              onRestaurantTap: widget.onRestaurantTap,
              onDinnerTap: widget.onDinnerTap,
            ),
          )
        else
          // Venue list (filtered by cuisine if set)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
            child: DataView<List<Restaurant>>(
              value: venuesAsync,
              isEmpty: (v) => v.isEmpty,
              emptyMessage: 'No restaurants in ${ref.watch(userCityProvider)} yet.',
              onRetry: () {
                _updateCuisine(null);
                _updateVenueTag('');
                _searchController.clear();
                setState(() => _query = '');
                ref.invalidate(
                  venueSearchProvider(VenueSearch(query: _query, tag: _venueTag)),
                );
              },
              builder: (_, venues) {
                final filtered = _cuisine == null
                    ? venues
                    : venues.where((r) => r.cuisine.contains(_cuisine!)).toList();
                if (filtered.isEmpty) {
                  return _buildClearFiltersEmpty();
                }
                return Column(
                  children: [
                    for (final venue in rankByDistance(filtered, fix))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _VenueRow(
                          restaurant: venue,
                          onTap: () => widget.onRestaurantTap?.call(venue),
                          onSave: () => _toggleSave(venue),
                          isSaving:
                              _savingRestaurantIds.contains(venue.id),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: AppSpacing.xl),

        // Deals section
        dealsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (deals) {
            if (deals.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: 'Active deals'),
                  const SizedBox(height: AppSpacing.md),
                  for (final deal in deals.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: ExploreDealCard(
                        deal: deal,
                        onTap: () => openDealDetail(
                          context,
                          deal,
                          onRestaurantTap: widget.onRestaurantTap,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _buildExperiencesTab(
    AsyncValue<List<Dinner>> dinnersAsync,
  ) {
    return dinnersAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.paddingScreen),
        child: SkeletonList(itemCount: 4, itemHeight: 100),
      ),
      error: (error, _) => Padding(
        padding: EdgeInsets.all(AppSpacing.paddingScreen),
        child: ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(eventsFeedProvider),
        ),
      ),
      data: (dinners) {
        final experiences = dinners.where((d) => d.isSpecialEvent).toList();
        final regularDinners = dinners.where((d) => !d.isSpecialEvent).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Curated experiences
            if (experiences.isNotEmpty) ...[
              SectionHeader(title: 'Curated experiences'),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingScreen,
                ),
                child: Column(
                  children: [
                    for (final d in experiences)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ExperienceCard(
                          dinner: d,
                          onTap: () => widget.onDinnerTap(d),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],

            // All dinners
            SectionHeader(
              title: regularDinners.isEmpty
                  ? 'No more dinners'
                  : '${regularDinners.length} dinners to explore',
            ),
            const SizedBox(height: AppSpacing.md),
            if (regularDinners.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: EmptyStateView(
                  message: 'No dinners match your filters.',
                ),
              )
            else
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingScreen,
                ),
                child: Column(
                  children: [
                    for (final d in regularDinners)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ExperienceCard(
                          dinner: d,
                          onTap: () => widget.onDinnerTap(d),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
        );
      },
    );
  }

  Widget _buildCafesTab(
    AsyncValue<List<Restaurant>> venuesAsync,
    Position? fix,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
      child: DataView<List<Restaurant>>(
        value: venuesAsync,
        isEmpty: (venues) => venues
            .where((r) =>
                r.tags.contains('cafe') ||
                r.cuisine.toLowerCase().contains('cafe') ||
                r.cuisine.toLowerCase().contains('coffee'))
            .isEmpty,
        emptyMessage: 'No cafés in your area yet.',
        onRetry: () => ref.invalidate(venueSearchProvider),
        builder: (_, venues) {
          final cafes = venues
              .where((r) =>
                  r.tags.contains('cafe') ||
                  r.cuisine.toLowerCase().contains('cafe') ||
                  r.cuisine.toLowerCase().contains('coffee'))
              .toList();
          return Column(
            children: [
              for (final cafe in rankByDistance(cafes, fix))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _VenueRow(
                    restaurant: cafe,
                    onTap: () => widget.onRestaurantTap?.call(cafe),
                    onSave: () => _toggleSave(cafe),
                    isSaving: _savingRestaurantIds.contains(cafe.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHostsTab(AsyncValue<List<RosterUser>> hostsAsync) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
      child: hostsAsync.when(
        loading: () => const SkeletonList(itemCount: 5, itemHeight: 80),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(discoverHostsProvider),
        ),
        data: (hosts) {
          final filtered = _query.isEmpty
              ? hosts
              : hosts.where((h) {
                  final q = _query.toLowerCase();
                  return h.user.name.toLowerCase().contains(q) ||
                      h.user.handle.toLowerCase().contains(q) ||
                      (h.user.bio?.toLowerCase().contains(q) ?? false);
                }).toList();
          if (filtered.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: EmptyStateView(message: 'No hosts found.'),
            );
          }
          return Column(
            children: [
              for (final host in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _HostRow(
                    user: host.user,
                    onTap: () => widget.onUserTap?.call(host.user),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Private helper widgets
// ────────────────────────────────────────────────────────────────────────────

/// Venue row for the Places tab, cover, name, cuisine, distance, tags, save.
class _VenueRow extends StatelessWidget {
  const _VenueRow({
    required this.restaurant,
    this.onTap,
    this.onSave,
    this.isSaving = false,
  });

  final Restaurant restaurant;
  final VoidCallback? onTap;
  final VoidCallback? onSave;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Image.asset(
                restaurant.imagePath ?? 'assets/images/venue_interior.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: AppColors.surfaceElevated,
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: AppColors.textTertiary,
                  ),
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
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          restaurant.distanceKm != null
                              ? '${restaurant.cuisine} \u00b7 ${distanceLabel(restaurant.distanceKm!)}'
                              : '${restaurant.cuisine} \u00b7 ${restaurant.address}',
                          style: restaurant.distanceKm != null
                              ? AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                )
                              : AppTextStyles.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (restaurant.rating > 0) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: AppColors.gold,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          restaurant.rating.toStringAsFixed(1),
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (restaurant.tags.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final tag in restaurant.tags.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (onSave != null)
              GestureDetector(
                onTap: isSaving ? null : onSave,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Icon(
                          restaurant.isFollowing
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: restaurant.isFollowing
                              ? AppColors.primary
                              : AppColors.textTertiary,
                          size: 22,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a [RestaurantCard] with a floating save/bookmark button.
class _SaveableRestaurantCard extends StatelessWidget {
  const _SaveableRestaurantCard({
    required this.restaurant,
    required this.onTap,
    required this.onSave,
    this.isSaving = false,
  });

  final Restaurant restaurant;
  final VoidCallback onTap;
  final VoidCallback onSave;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RestaurantCard(restaurant: restaurant, onTap: onTap),
        ),
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: GestureDetector(
            onTap: isSaving ? null : onSave,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : Icon(
                      restaurant.isFollowing
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: restaurant.isFollowing
                          ? AppColors.primary
                          : Colors.white,
                      size: 18,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact host chip for the All tab's "Featured hosts" rail.
class _HostChip extends StatelessWidget {
  const _HostChip({required this.user, this.onTap});

  final UserProfile user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                user.initials,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              user.name,
              style: AppTextStyles.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (user.isVerified)
              const Icon(
                Icons.verified_rounded,
                size: 14,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

/// Host row for the Hosts tab, avatar, name, handle, stats.
class _HostRow extends StatelessWidget {
  const _HostRow({required this.user, this.onTap});

  final UserProfile user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                user.initials,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.name,
                          style: AppTextStyles.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '@${user.handle}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.restaurant_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${user.dinnersHosted} hosted',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Icon(
                        Icons.people_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${user.followers} followers',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textSecondary,
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
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Filter sheet (unchanged)
// ────────────────────────────────────────────────────────────────────────────

class _ExploreFilterDraft {
  const _ExploreFilterDraft({
    this.audience,
    this.type,
    this.maxPrice,
    this.days = 0,
  });

  final String? audience;
  final String? type;
  final double? maxPrice;
  final int days;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    this.initialAudience,
    this.initialType,
    this.initialMaxPrice,
    this.initialDays = 0,
  });

  final String? initialAudience;
  final String? initialType;
  final double? initialMaxPrice;
  final int initialDays;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _audiences = <String, String>{
    'public': 'Public',
    'friends': 'Friends',
    'followers': 'Followers',
    'inviteOnly': 'Invite-only',
  };
  static const _types = <String, String>{
    'dinner': 'Dinners',
    'experience': 'Experiences',
  };
  static const _windows = <int, String>{
    0: 'Any time',
    3: 'Next 3 days',
    7: 'Next 7 days',
    30: 'Next 30 days',
  };
  static const double _priceCeiling = 25000;

  late String? _audience = widget.initialAudience;
  late String? _type = widget.initialType;
  late double _maxPrice = widget.initialMaxPrice ?? _priceCeiling;
  late int _days = widget.initialDays;

  bool get _priceBounded => _maxPrice < _priceCeiling;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        AppSpacing.lg,
        AppSpacing.paddingScreen,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filters', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          const Text('Audience'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TagChip(
                label: 'Any',
                isSelected: _audience == null,
                onTap: () => setState(() => _audience = null),
              ),
              for (final entry in _audiences.entries)
                TagChip(
                  label: entry.value,
                  isSelected: _audience == entry.key,
                  onTap: () => setState(() => _audience = entry.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Event type'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              TagChip(
                label: 'Any',
                isSelected: _type == null,
                onTap: () => setState(() => _type = null),
              ),
              for (final entry in _types.entries)
                TagChip(
                  label: entry.value,
                  isSelected: _type == entry.key,
                  onTap: () => setState(() => _type = entry.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _priceBounded
                ? 'Max price per seat · Rs ${_maxPrice.round()}'
                : 'Max price per seat · any',
          ),
          Slider(
            value: _maxPrice,
            min: 0,
            max: _priceCeiling,
            divisions: 12,
            label: 'Rs ${_maxPrice.round()}',
            onChanged: (v) => setState(() => _maxPrice = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Date window'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in _windows.entries)
                TagChip(
                  label: entry.value,
                  isSelected: _days == entry.key,
                  onTap: () => setState(() => _days = entry.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const _ExploreFilterDraft()),
                child: const Text('Reset'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _ExploreFilterDraft(
                    audience: _audience,
                    type: _type,
                    maxPrice: _priceBounded ? _maxPrice : null,
                    days: _days,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
