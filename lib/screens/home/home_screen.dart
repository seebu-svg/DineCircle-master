import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/dinner.dart';
import '../../models/restaurant.dart';
import '../../models/booking.dart';
import '../../models/discovery_category.dart';
import '../../widgets/dinner_card.dart';
import '../../widgets/restaurant_card.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/skeleton_placeholder.dart';
import '../../widgets/data_view.dart';
import '../../providers/events_provider.dart';
import '../../providers/restaurants_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/social_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../qr_menu/qr_scan_screen.dart';

/// Home screen — "Today" per spec.
///
/// A vertically scrolling editorial concierge with nine sections ordered by
/// guest priority:
///
///   1. Personalized header + location
///   2. Search
///   3. Quick actions
///   4. Your Next Table (conditional — only when a confirmed booking exists)
///   5. Featured Experiences (cinematic, date-filtered)
///   6. Gather Around a Table (category banners)
///   7. Tables Worth Booking (restaurants)
///   8. This Week on DineCircle (upcoming dinners list)
///   9. Find Your Kind of Evening (occasion moods)
///
/// Empty sections are hidden. All data comes from Riverpod providers — no
/// mock data.
class HomeScreen extends ConsumerStatefulWidget {
  final void Function(Dinner dinner) onDinnerTap;
  final VoidCallback? onNotificationsTap;
  final void Function(Restaurant restaurant)? onRestaurantTap;
  final VoidCallback? onCreateTap;
  final VoidCallback? onExploreTap;
  final VoidCallback? onBookingsTap;
  final VoidCallback? onSavedTap;
  final VoidCallback? onLocationTap;
  final void Function(DiscoveryCategory category)? onCategoryTap;
  final VoidCallback? onSearchTap;
  final void Function(String audience)? onOccasionTap;
  final VoidCallback? onBecomeHostTap;

  const HomeScreen({
    super.key,
    required this.onDinnerTap,
    this.onNotificationsTap,
    this.onRestaurantTap,
    this.onCreateTap,
    this.onExploreTap,
    this.onBookingsTap,
    this.onSavedTap,
    this.onLocationTap,
    this.onCategoryTap,
    this.onSearchTap,
    this.onOccasionTap,
    this.onBecomeHostTap,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Greeting keyed by local hour.
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final dinnersAsync = ref.watch(eventsFeedProvider(const EventFilter()));
    final trendingAsync = ref.watch(
      eventsFeedProvider(const EventFilter(sort: 'trending')),
    );
    final forYouAsync = ref.watch(
      eventsFeedProvider(const EventFilter(sort: 'forYou')),
    );
    final restaurantsAsync = ref.watch(nearbyRestaurantsProvider);
    final bookingsAsync = ref.watch(myBookingsProvider);
    final canHost = ref.watch(canHostProvider);
    final city = ref.watch(userCityProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App bar ──
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.bg,
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    'DineCircle',
                    style: AppTextStyles.headlineMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              Builder(
                builder: (context) {
                  final unread =
                      ref.watch(unreadActivityCountProvider).valueOrNull ?? 0;
                  return IconButton(
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      backgroundColor: AppColors.danger,
                      label: Text(
                        '${unread > 99 ? '99+' : unread}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      child: const Icon(Icons.notifications_rounded),
                    ),
                    onPressed: widget.onNotificationsTap,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                tooltip: 'Scan menu QR',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QrScanScreen()),
                ),
              ),
            ],
          ),

          // ── 1. Personalized Header + Location ──
          SliverToBoxAdapter(
            child: Padding(
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              user?.name.isNotEmpty == true
                                  ? 'Hey, ${user!.name.split(' ').first}'
                                  : 'Welcome back',
                              style: AppTextStyles.headlineLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onLocationTap,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 100),
                              child: Text(
                                city.isEmpty ? 'Set city' : city,
                                style: AppTextStyles.labelSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textSecondary,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Your next story starts at a table.',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
              vertical: AppSpacing.md,
            ),
            // ── 2. Search ──
            sliver: SliverToBoxAdapter(
              child: GestureDetector(
                onTap: widget.onSearchTap ?? widget.onExploreTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Search restaurants & cafés',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 3. Quick Actions ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.event_seat_rounded,
                      label: 'Book a Table',
                      color: AppColors.info,
                      onTap: () => widget.onCategoryTap?.call(
                        DiscoveryCategory.bookTable,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.groups_rounded,
                      label: 'Join a Gathering',
                      color: AppColors.primary,
                      onTap: () => widget.onCategoryTap?.call(
                        DiscoveryCategory.diningEvents,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.local_offer_rounded,
                      label: 'Explore Deals',
                      color: AppColors.success,
                      onTap: () =>
                          widget.onCategoryTap?.call(DiscoveryCategory.deals),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.lg)),

          // ── 4. Your Next Table (conditional) ──
          _buildUpcomingPlans(bookingsAsync),

          // ── 5. Trending Now ──
          _buildTrendingExperiences(trendingAsync),

          // ── 6. Recommended for You ──
          _buildRecommendedForYou(forYouAsync),

          // ── 7. Gather Around a Table ──
          _buildSocialCategories(),

          // ── 7. Tables Worth Booking ──
          _buildRestaurants(restaurantsAsync),

          // ── 8. This Week on DineCircle ──
          _buildThisWeek(dinnersAsync),

          // ── 9. Find Your Kind of Evening ──
          _buildEveningMoods(),

          // ── Host a Table (only if user cannot host yet) ──
          if (!canHost) _buildHostInvitation(),

          // ── Empty-state fallback ──
          SliverToBoxAdapter(
            child:
                dinnersAsync.whenOrNull(
                  data: (dinners) => (dinners.isEmpty)
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.xl),
                          child: EmptyStateView(
                            message:
                                'No dinners near you yet. Check back soon.',
                          ),
                        )
                      : const SizedBox.shrink(),
                ) ??
                const SizedBox.shrink(),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.xxl)),
        ],
      ),
    );
  }

  // ─── Section builders ────────────────────────────────────────────────────

  /// Trending Now — server-sorted by fill ratio (most popular first).
  Widget _buildTrendingExperiences(AsyncValue<List<Dinner>> async) {
    return SliverToBoxAdapter(
      child: async.when(
        loading: () =>
            const SizedBox(height: 340, child: SkeletonList(itemCount: 2)),
        error: (_, _) => const SizedBox.shrink(),
        data: (dinners) {
          final list = dinners.take(8).toList();
          if (list.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Trending Now',
                actionText: 'See all',
                onAction: widget.onExploreTap,
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 310,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingScreen,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final dinner = list[index];
                    return DinnerCard(
                      dinner: dinner,
                      onTap: () => widget.onDinnerTap(dinner),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  /// Recommended for You — server-sorted by cuisine overlap with user's tastes.
  Widget _buildRecommendedForYou(AsyncValue<List<Dinner>> async) {
    return SliverToBoxAdapter(
      child: async.when(
        loading: () =>
            const SizedBox(height: 340, child: SkeletonList(itemCount: 2)),
        error: (_, _) => const SizedBox.shrink(),
        data: (dinners) {
          final list = dinners.take(6).toList();
          if (list.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Recommended for You',
                actionText: 'Explore',
                onAction: widget.onExploreTap,
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 310,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingScreen,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final dinner = list[index];
                    return DinnerCard(
                      dinner: dinner,
                      onTap: () => widget.onDinnerTap(dinner),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  /// Gather Around a Table — photographic category banners.
  Widget _buildSocialCategories() {
    const categories = [
      _SocialCategory(
        'Social Dining',
        'Make new connections',
        Icons.groups_rounded,
        AppColors.primaryLight,
        'social',
        'assets/images/venue_rooftop.png',
      ),
      _SocialCategory(
        'Singles Nights',
        'Meet over a meal',
        Icons.favorite_rounded,
        AppColors.danger,
        'singles',
        'assets/images/dish_steak.png',
      ),
      _SocialCategory(
        'Networking',
        'Dine professionally',
        Icons.business_center_rounded,
        AppColors.info,
        'networking',
        'assets/images/venue_interior.png',
      ),
      _SocialCategory(
        'Creator Dinners',
        'Dine with influencers',
        Icons.video_camera_front_rounded,
        AppColors.gold,
        'creator',
        'assets/images/dish_sushi.png',
      ),
      _SocialCategory(
        'Culinary Experiences',
        'Chef-led tastings',
        Icons.restaurant_rounded,
        AppColors.success,
        'culinary',
        'assets/images/hero_tasting.png',
      ),
    ];
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Gather Around a Table',
            actionText: 'See all',
            onAction: widget.onExploreTap,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
              ),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final cat = categories[index];
                return _SocialCategoryCard(
                  category: cat,
                  onTap: () => widget.onOccasionTap?.call(cat.audience),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// Tables Worth Booking — nearby restaurant cards.
  Widget _buildRestaurants(AsyncValue<List<Restaurant>> async) {
    return SliverToBoxAdapter(
      child: async.when(
        loading: () =>
            const SizedBox(height: 270, child: SkeletonList(itemCount: 3)),
        error: (_, _) => const SizedBox.shrink(),
        data: (restaurants) {
          final list = restaurants.take(6).toList();
          if (list.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Tables Worth Booking',
                actionText: 'See all',
                onAction: widget.onExploreTap,
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 260,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingScreen,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final r = list[index];
                    return SizedBox(
                      width: 210,
                      child: RestaurantCard(
                        restaurant: r,
                        onTap: () => widget.onRestaurantTap?.call(r),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  /// This Week on DineCircle — upcoming dinners in a vertical list.
  ///
  /// Excludes dinners already shown in Featured Experiences (tonight/special/
  /// creator) to avoid repetitive placement.
  Widget _buildThisWeek(AsyncValue<List<Dinner>> async) {
    return SliverToBoxAdapter(
      child: async.when(
        loading: () =>
            const SizedBox(height: 200, child: SkeletonList(itemCount: 3)),
        error: (_, _) => const SizedBox.shrink(),
        data: (dinners) {
          final now = DateTime.now();
          final weekEnd = now.add(const Duration(days: 7));
          final featuredIds = dinners
              .where(
                (d) =>
                    (d.dateTime.isAfter(now) &&
                        d.dateTime.isBefore(
                          now.add(const Duration(days: 2)),
                        )) ||
                    d.isSpecialEvent ||
                    d.host.isInfluencer,
              )
              .map((d) => d.id)
              .toSet();

          final upcoming = dinners
              .where(
                (d) =>
                    d.dateTime.isAfter(now) &&
                    d.dateTime.isBefore(weekEnd) &&
                    !featuredIds.contains(d.id),
              )
              .take(5)
              .toList();

          // If all dinners are already featured, show the full list instead of
          // hiding the section — the guest still needs something to browse.
          final list = upcoming.isEmpty && dinners.isNotEmpty
              ? dinners.where((d) => d.dateTime.isAfter(now)).take(5).toList()
              : upcoming;

          if (list.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'This Week on DineCircle',
                actionText: 'See all',
                onAction: widget.onExploreTap,
              ),
              const SizedBox(height: AppSpacing.md),
              ...list.map(
                (dinner) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingScreen,
                    vertical: AppSpacing.xs,
                  ),
                  child: _DinnerListItem(
                    dinner: dinner,
                    onTap: () => widget.onDinnerTap(dinner),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  /// Find Your Kind of Evening — occasion mood cards.
  Widget _buildEveningMoods() {
    const occasions = [
      _Occasion(
        'Date Night',
        Icons.favorite_rounded,
        AppColors.danger,
        'date',
        'assets/images/dish_steak.png',
      ),
      _Occasion(
        'Friends & Family',
        Icons.celebration_rounded,
        AppColors.primary,
        'friends',
        'assets/images/dish_tacos.png',
      ),
      _Occasion(
        'Celebrations',
        Icons.cake_rounded,
        AppColors.gold,
        'celebration',
        'assets/images/dish_dessert.png',
      ),
      _Occasion(
        'Business Dining',
        Icons.business_center_rounded,
        AppColors.info,
        'business',
        'assets/images/venue_interior.png',
      ),
      _Occasion(
        'Casual & Cozy',
        Icons.local_cafe_rounded,
        AppColors.success,
        'casual',
        'assets/images/dish_brunch.png',
      ),
      _Occasion(
        'Something Special',
        Icons.diamond_rounded,
        AppColors.primaryLight,
        'special',
        'assets/images/hero_tasting.png',
      ),
    ];
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Find Your Kind of Evening'),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
              ),
              itemCount: occasions.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final o = occasions[index];
                return _OccasionCard(
                  occasion: o,
                  onTap: () => widget.onOccasionTap?.call(o.audience),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// Your Next Table — next confirmed upcoming booking near the top.
  ///
  /// Shows venue, date, time, party size, and a status badge. Hidden when
  /// there are no upcoming confirmed bookings.
  Widget _buildUpcomingPlans(AsyncValue<List<Booking>> async) {
    return SliverToBoxAdapter(
      child: async.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (bookings) {
          final now = DateTime.now();
          final next =
              bookings
                  .where(
                    (b) =>
                        b.status == BookingStatus.confirmed &&
                        b.dinner.dateTime.isAfter(now),
                  )
                  .toList()
                ..sort(
                  (a, b) => a.dinner.dateTime.compareTo(b.dinner.dateTime),
                );
          if (next.isEmpty) return const SizedBox.shrink();
          final booking = next.first;
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Your Next Table',
                  actionText: 'View bookings',
                  onAction: widget.onBookingsTap,
                ),
                const SizedBox(height: AppSpacing.md),
                _UpcomingBookingCard(
                  booking: booking,
                  onTap: () => widget.onDinnerTap(booking.dinner),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Host a Table — invitation for guests who haven't become hosts yet.
  Widget _buildHostInvitation() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingScreen,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Host a Table'),
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: widget.onBecomeHostTap ?? widget.onCreateTap,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      AppColors.gold.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: const Icon(
                        Icons.military_tech_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Become a host',
                            style: AppTextStyles.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Create and organize your own dining experiences',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

// ─── Supporting data classes ───────────────────────────────────────────────

class _SocialCategory {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String audience;
  final String imagePath;
  const _SocialCategory(
    this.label,
    this.subtitle,
    this.icon,
    this.color,
    this.audience,
    this.imagePath,
  );
}

class _Occasion {
  final String label;
  final IconData icon;
  final Color color;
  final String audience;
  final String imagePath;
  const _Occasion(
    this.label,
    this.icon,
    this.color,
    this.audience,
    this.imagePath,
  );
}

// ─── Quick Action ──────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Social Category Card ──────────────────────────────────────────────────

class _SocialCategoryCard extends StatelessWidget {
  final _SocialCategory category;
  final VoidCallback? onTap;
  const _SocialCategoryCard({required this.category, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          width: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background image with colour fallback
              Image.asset(
                category.imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: category.color.withValues(alpha: 0.15)),
              ),
              // Multi-stop gradient for text readability at bottom
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.82),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              // Content anchored to bottom
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(category.icon, color: category.color, size: 22),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      category.label,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.subtitle,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

// ─── Occasion Card ─────────────────────────────────────────────────────────

class _OccasionCard extends StatelessWidget {
  final _Occasion occasion;
  final VoidCallback? onTap;
  const _OccasionCard({required this.occasion, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          width: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                occasion.imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: occasion.color.withValues(alpha: 0.15)),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.80),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(occasion.icon, color: occasion.color, size: 26),
                    const SizedBox(height: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        occasion.label,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
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

// ─── Dinner List Item ──────────────────────────────────────────────────────

class _DinnerListItem extends StatelessWidget {
  final Dinner dinner;
  final VoidCallback? onTap;
  const _DinnerListItem({required this.dinner, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                dinner.imagePath ?? 'assets/images/hero_tasting.png',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dinner.title,
                    style: AppTextStyles.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    dinner.restaurant.name,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 2,
                    children: [
                      _InfoChip(
                        icon: Icons.calendar_today_rounded,
                        label: dinner.formattedDate,
                        color: AppColors.primary,
                      ),
                      _InfoChip(
                        icon: Icons.access_time_rounded,
                        label: dinner.formattedTime,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _PriceSeatsColumn(dinner: dinner),
          ],
        ),
      ),
    );
  }
}

/// Compact icon + label chip used in dinner list items.
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Price + seats column for dinner list items.
class _PriceSeatsColumn extends StatelessWidget {
  final Dinner dinner;
  const _PriceSeatsColumn({required this.dinner});

  @override
  Widget build(BuildContext context) {
    final seats = dinner.availableSeats;
    final isLow = seats <= 3 && seats > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Rs ${dinner.pricePerSeat.toStringAsFixed(0)}',
          style: AppTextStyles.titleSmall.copyWith(color: AppColors.primary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: isLow
                ? AppColors.danger.withValues(alpha: 0.15)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            '$seats left',
            style: AppTextStyles.caption.copyWith(
              color: isLow ? AppColors.danger : AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Upcoming Booking Card ─────────────────────────────────────────────────

class _UpcomingBookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onTap;
  const _UpcomingBookingCard({required this.booking, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dinner = booking.dinner;
    final seatsText = '${booking.seats} guest${booking.seats > 1 ? 's' : ''}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            // Date badge
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${dinner.dateTime.day}',
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    _monthAbbrev(dinner.dateTime),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dinner.title,
                    style: AppTextStyles.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    dinner.restaurant.name,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        dinner.formattedTime,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.people_rounded,
                        size: 12,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        seatsText,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  static const _months = [
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

  String _monthAbbrev(DateTime dt) => _months[dt.month - 1];
}
