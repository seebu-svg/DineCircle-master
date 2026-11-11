import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_exception.dart';
import '../../models/dinner.dart';
import '../../models/public_menu.dart';
import '../../models/restaurant.dart';
import '../../models/restaurant_review.dart';
import '../../models/table_reservation.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/deals_provider.dart';
import '../../providers/reservations_provider.dart';
import '../../providers/restaurant_reviews_provider.dart';
import '../../providers/restaurants_provider.dart';
import '../../repositories/restaurant_reviews_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/opening_hours.dart';
import '../../utils/venue_time.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/data_view.dart';
import '../../widgets/experience_card.dart';
import '../../widgets/media_image.dart';
import '../../widgets/skeleton_placeholder.dart';
import '../deals/deal_detail_screen.dart';
import '../explore/explore_deal_card.dart';
import '../map/map_screen.dart';
import '../qr_menu/dish_detail_sheet.dart';
import '../qr_menu/qr_menu_screen.dart';
import '../tables/reserve_table_sheet.dart';
import 'profile_hero.dart';
import 'profile_info_sections.dart';

/// Restaurant profile, the single storefront screen shared by every entry
/// point: nearby/list taps, search results and QR scans.
///
/// Either a [restaurant] seed (instant paint from a list row) or a
/// [restaurantId] (QR scan, manual code, deep link) must be supplied. With an
/// id only, the screen holds a skeleton until `/restaurants/:id` resolves and
/// offers a retry when it fails, so one widget serves both paths.
class RestaurantDetailScreen extends ConsumerStatefulWidget {
  final Restaurant? restaurant;
  final String? restaurantId;
  final void Function(Dinner dinner)? onDinnerTap;

  const RestaurantDetailScreen({
    super.key,
    this.restaurant,
    this.restaurantId,
    this.onDinnerTap,
  }) : assert(
         restaurant != null || (restaurantId != null && restaurantId != ''),
         'Provide a restaurant seed or a restaurantId.',
       );

  /// Canonical id for this profile, from the seed or the QR/deep link.
  String get id => restaurantId ?? restaurant!.id;

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

/// Section identifiers in vertical order. `experiences` is dropped from both the
/// nav and the body when the venue has no upcoming events, so tabs can never
/// point at something that is not on screen.
const String _kOverview = 'overview';
const String _kMenu = 'menu';
const String _kDeals = 'deals';
const String _kExperiences = 'experiences';
const String _kReviews = 'reviews';

const Map<String, String> _kSectionTitles = {
  _kOverview: 'Overview',
  _kMenu: 'Menu',
  _kDeals: 'Deals',
  _kExperiences: 'Experiences',
  _kReviews: 'Reviews',
};

/// Height of the pinned section nav. Content inside is clamped to 1.3x text
/// scaling so a large system font can never inflate this extent.
const double _kNavExtent = 58;

/// Expanded hero height; also the scroll offset at which the app bar title
/// starts fading in.
const double _kHeroHeight = 300;

class _RestaurantDetailScreenState extends ConsumerState<RestaurantDetailScreen> {
  final ScrollController _scroll = ScrollController();
  final ScrollController _navScroll = ScrollController();
  final GlobalKey _scrollKey = GlobalKey();
  final Map<String, GlobalKey> _sectionKeys = {};

  /// Serialised scroll offset at which each section's top reaches the viewport
  /// top. Rebuilt after layout and whenever the section list changes.
  List<double> _sectionOffsets = const [];
  List<String> _visibleIds = const [];

  int _activeIndex = 0;
  bool _isFollowing = false;
  bool _followLoading = false;
  bool _collapsed = false;
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.restaurant?.isFollowing ?? false;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _navScroll.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    setState(() => _followLoading = true);
    final next = !_isFollowing;
    try {
      final result = await ref
          .read(restaurantsRepositoryProvider)
          .setFollowing(widget.id, next);
      if (mounted) {
        setState(() {
          _isFollowing = result;
          _followLoading = false;
        });
        ref.invalidate(restaurantDetailProvider(widget.id));
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
        setState(() => _followLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _share() async {
    final link = 'https://dinecircle.app/restaurants/${widget.id}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restaurant link copied to clipboard!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _call(Restaurant restaurant) async {
    final phone = restaurant.phoneNumber;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openReserveSheet(BuildContext context, Restaurant restaurant) {
    showModalBottomSheet<TableReservation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReserveTableSheet(restaurant: restaurant),
    ).then((reservation) {
      if (reservation != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Table reserved! Ref: ${reservation.reference}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    });
  }

  // ── Section navigation ─────────────────────────────────────────────────────

  GlobalKey _keyFor(String id) =>
      _sectionKeys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final offset = _scroll.offset;
    final shouldCollapse = offset > _kHeroHeight - kToolbarHeight - 48;
    if (shouldCollapse != _collapsed && mounted) {
      setState(() => _collapsed = shouldCollapse);
    }
    if (_sectionOffsets.isEmpty) return;

    var index = 0;
    for (var i = 0; i < _sectionOffsets.length; i++) {
      if (offset >= _sectionOffsets[i] - _kNavExtent - 12) index = i;
    }
    if (index != _activeIndex && mounted) {
      setState(() => _activeIndex = index);
      _ensureActivePillVisible();
    }
  }

  /// Measures every section against the scroll view so a tab tap can land the
  /// heading exactly under the pinned nav.
  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final scrollBox =
          _scrollKey.currentContext?.findRenderObject() as RenderBox?;
      if (scrollBox == null) return;
      final scrollTop = scrollBox.localToGlobal(Offset.zero).dy;
      final offset = _scroll.hasClients ? _scroll.offset : 0.0;

      final measured = <double>[];
      for (final id in _visibleIds) {
        final ctx = _sectionKeys[id]?.currentContext;
        final box = ctx?.findRenderObject();
        if (box is! RenderBox) {
          measured.add(double.infinity);
          continue;
        }
        final dy = box.localToGlobal(Offset.zero).dy;
        measured.add((dy - scrollTop + offset).clamp(0.0, double.infinity));
      }
      _sectionOffsets = measured;
    });
  }

  /// Centres the active pill inside the nav rail. Only the rail is scrolled,
  /// `Scrollable.ensureVisible` would also nudge the page itself.
  void _ensureActivePillVisible() {
    if (_activeIndex < 0 || _activeIndex >= _visibleIds.length) return;
    final ctx = _sectionKeys['pill:${_visibleIds[_activeIndex]}']?.currentContext;
    if (ctx == null || !_navScroll.hasClients) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final centre =
        box.localToGlobal(Offset.zero).dx + box.size.width / 2;
    final viewport = MediaQuery.sizeOf(context).width;
    final target = (_navScroll.offset + centre - viewport / 2).clamp(
      0.0,
      _navScroll.position.maxScrollExtent,
    );
    _navScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onTabTap(int index) {
    setState(() => _activeIndex = index);
    if (index < _sectionOffsets.length && _scroll.hasClients) {
      final target = _sectionOffsets[index];
      if (target.isFinite) {
        _scroll.animateTo(
          (target - _kNavExtent).clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
    _ensureActivePillVisible();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The list hands us a slim venue (id/name only). Pull the full profile +
    // upcoming events from `/restaurants/:id`, painting the slim item until it
    // resolves.
    final detailAsync = ref.watch(restaurantDetailProvider(widget.id));
    final detail = detailAsync.valueOrNull;
    final restaurant = detail?.restaurant ?? widget.restaurant;

    // Opened from a QR scan or deep link with no list row to paint first: hold
    // a skeleton until the profile arrives, and offer a retry instead of an
    // empty shell if the fetch fails.
    if (restaurant == null) {
      if (detailAsync.hasError) {
        return Scaffold(
          appBar: AppBar(backgroundColor: AppColors.bg),
          body: ErrorStateView(
            error: detailAsync.error!,
            onRetry: () => ref.invalidate(restaurantDetailProvider(widget.id)),
          ),
        );
      }
      return const _RestaurantProfileSkeleton();
    }

    final events = detail?.events ?? const <Dinner>[];
    final ids = <String>[
      _kOverview,
      _kMenu,
      _kDeals,
      if (events.isNotEmpty) _kExperiences,
      _kReviews,
    ];
    if (!_listEquals(ids, _visibleIds)) {
      _visibleIds = ids;
      _sectionOffsets = const [];
      _activeIndex = _activeIndex.clamp(0, ids.length - 1);
    }
    _scheduleMeasure();

    final days = parseOpeningHours(restaurant.openingHours);
    final isOpen = isCurrentlyOpen(days);
    final todayIndex = (DateTime.now().weekday - 1).clamp(0, 6);
    final todayLabel = days.isEmpty ? '' : days[todayIndex].summary;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final hPad = screenWidth > 760
        ? (screenWidth - 720) / 2
        : AppSpacing.paddingScreen.toDouble();

    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: _BottomBar(
        horizontalPadding: hPad,
        onViewMenu: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QrMenuScreen(restaurantId: restaurant.id),
          ),
        ),
        onReserve: () => _openReserveSheet(context, restaurant),
      ),
      body: CustomScrollView(
        key: _scrollKey,
        controller: _scroll,
        slivers: [
          SliverAppBar(
            expandedHeight: _kHeroHeight,
            pinned: true,
            backgroundColor: AppColors.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: _CircleIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: _pop,
            ),
            title: AnimatedOpacity(
              opacity: _collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Text(
                restaurant.name,
                style: AppTextStyles.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: ProfileHero(
                restaurant: restaurant,
                isOpen: isOpen,
                todayLabel: todayLabel,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSpacing.md,
                hPad,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  QuickActionsBar(
                    onDirections: () => MapScreen.openDirections(
                      lat: restaurant.latitude!,
                      lng: restaurant.longitude!,
                      destinationName: restaurant.name,
                    ),
                    onCall: () => _call(restaurant),
                    onSave: _toggleFollow,
                    onShare: _share,
                    isSaved: _isFollowing,
                    isBusy: _followLoading,
                    canCall:
                        restaurant.phoneNumber != null &&
                        restaurant.phoneNumber!.isNotEmpty,
                    canDirections: restaurant.hasCoordinates,
                  ),
                  if (restaurant.tags.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final tag in restaurant.tags)
                          TagChip(label: tag),
                      ],
                    ),
                  ],
                  _YourTableCard(restaurantId: restaurant.id),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SectionNavDelegate(
              titles: [for (final id in ids) _kSectionTitles[id]!],
              activeIndex: _activeIndex,
              onTap: _onTabTap,
              controller: _navScroll,
              keyFor: (index) => _keyFor('pill:${ids[index]}'),
            ),
          ),
          _sectionSliver(
            _kOverview,
            hPad,
            _OverviewSection(
              restaurant: restaurant,
              isOpen: isOpen,
              onDirections: restaurant.hasCoordinates
                  ? () => MapScreen.openDirections(
                      lat: restaurant.latitude!,
                      lng: restaurant.longitude!,
                      destinationName: restaurant.name,
                    )
                  : null,
              onCall: () => _call(restaurant),
            ),
          ),
          _sectionSliver(
            _kMenu,
            hPad,
            _MenuPreviewSection(restaurantId: restaurant.id),
          ),
          _sectionSliver(
            _kDeals,
            hPad,
            _DealsSection(restaurantId: restaurant.id),
          ),
          if (events.isNotEmpty)
            _sectionSliver(
              _kExperiences,
              hPad,
              _ExperiencesSection(
                events: events,
                onOpen: (dinner) => widget.onDinnerTap?.call(dinner),
              ),
            ),
          _sectionSliver(
            _kReviews,
            hPad,
            _ReviewsSection(restaurantId: restaurant.id),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppSpacing.sm,
                hPad,
                AppSpacing.xxl,
              ),
              child: Text(
                'Restaurant details, menu, prices and offers are provided by '
                'the venue.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pop() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// One keyed section block; the key is what [_scheduleMeasure] reads to learn
  /// where the heading sits inside the scroll view.
  Widget _sectionSliver(String id, double hPad, Widget child) {
    return SliverToBoxAdapter(
      child: Padding(
        key: _keyFor(id),
        padding: EdgeInsets.fromLTRB(hPad, AppSpacing.lg, hPad, AppSpacing.sm),
        child: child,
      ),
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─── Section nav ──────────────────────────────────────────────────────────────

class _SectionNavDelegate extends SliverPersistentHeaderDelegate {
  _SectionNavDelegate({
    required this.titles,
    required this.activeIndex,
    required this.onTap,
    required this.controller,
    required this.keyFor,
  });

  final List<String> titles;
  final int activeIndex;
  final void Function(int index) onTap;
  final ScrollController controller;
  final GlobalKey Function(int index) keyFor;

  @override
  double get minExtent => _kNavExtent;

  @override
  double get maxExtent => _kNavExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: _kNavExtent,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      alignment: Alignment.centerLeft,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.paddingScreen,
            vertical: AppSpacing.sm,
          ),
          itemCount: titles.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) {
            final active = index == activeIndex;
            return GestureDetector(
              key: keyFor(index),
              onTap: () => onTap(index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? null : AppColors.surface,
                  gradient: active ? AppColors.primaryGradient : null,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(
                    color: active ? Colors.transparent : AppColors.border,
                  ),
                ),
                child: Text(
                  titles[index],
                  style: AppTextStyles.labelSmall.copyWith(
                    color: active ? Colors.black : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionNavDelegate oldDelegate) =>
      oldDelegate.activeIndex != activeIndex ||
      oldDelegate.titles.length != titles.length;
}

// ─── Overview ────────────────────────────────────────────────────────────────

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.restaurant,
    required this.isOpen,
    required this.onDirections,
    required this.onCall,
  });

  final Restaurant restaurant;
  final bool isOpen;
  final VoidCallback? onDirections;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final hasDescription = restaurant.description.trim().isNotEmpty;
    final hasAddress = restaurant.address.trim().isNotEmpty;
    final hasHours = restaurant.openingHours.isNotEmpty;
    final hasFacilities = restaurant.amenities.isNotEmpty;
    final hasContact = restaurant.hasContact || restaurant.hasSocialMedia;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ProfileSectionHeading(title: 'About'),
        if (hasDescription)
          AboutSection(text: restaurant.description)
        else
          Text(
            'The venue has not added a description yet.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        if (hasAddress) ...[
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: onDirections,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    restaurant.address,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (onDirections != null)
                  const Icon(
                    Icons.directions_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
              ],
            ),
          ),
        ],
        if (hasHours) ...[
          const SizedBox(height: AppSpacing.lg),
          const ProfileSectionHeading(title: 'Opening hours'),
          OpeningHoursCard(hours: restaurant.openingHours),
        ],
        if (hasFacilities) ...[
          const SizedBox(height: AppSpacing.lg),
          const ProfileSectionHeading(title: 'Facilities'),
          FacilitiesWrap(amenities: restaurant.amenities),
        ],
        if (hasContact) ...[
          const SizedBox(height: AppSpacing.lg),
          const ProfileSectionHeading(title: 'Contact'),
          ContactCard(restaurant: restaurant, onCall: onCall),
        ],
      ],
    );
  }
}

// ─── Menu preview ────────────────────────────────────────────────────────────

class _MenuPreviewSection extends ConsumerWidget {
  const _MenuPreviewSection({required this.restaurantId});

  final String restaurantId;

  void _openFullMenu(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrMenuScreen(restaurantId: restaurantId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(publicMenuProvider(restaurantId));

    return menuAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
      error: (_, _) => const _InlineNote(
        icon: Icons.restaurant_menu_rounded,
        message: 'Menu unavailable right now.',
      ),
      data: (menu) {
        final sections = menu.sections
            .where((s) => s.items.isNotEmpty)
            .take(2)
            .toList();
        if (sections.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileSectionHeading(title: 'Menu'),
              _InlineNote(
                icon: Icons.restaurant_menu_rounded,
                message: 'This venue has not published a menu yet.',
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileSectionHeading(
              title: 'Menu',
              trailing: _TextAction(
                label: 'View full menu',
                onTap: () => _openFullMenu(context),
              ),
            ),
            for (final section in sections) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  section.name,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              for (final item in section.items.take(2))
                _DishPreviewRow(
                  item: item,
                  onTap: () => showDishDetail(
                    context,
                    item: item,
                    sectionName: section.name,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _DishPreviewRow extends StatelessWidget {
  const _DishPreviewRow({required this.item, required this.onTap});

  final PublicMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photo = item.photoUrl?.trim() ?? '';
    return Semantics(
      button: true,
      label: '${item.name}, ${item.formattedPrice}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photo.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: MediaImage(
                      source: photo,
                      fallbackIcon: Icons.restaurant_menu_rounded,
                      cacheWidth: 168,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                item.formattedPrice,
                style: AppTextStyles.titleSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Deals ───────────────────────────────────────────────────────────────────

class _DealsSection extends ConsumerWidget {
  const _DealsSection({required this.restaurantId});

  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(restaurantDealsProvider(restaurantId));

    return dealsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (deals) {
        if (deals.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileSectionHeading(title: 'Deals'),
              _InlineNote(
                icon: Icons.local_offer_outlined,
                message: 'No active deals at this venue right now.',
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileSectionHeading(
              title: 'Deals',
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  '${deals.length} active',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 212,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                clipBehavior: Clip.none,
                itemCount: deals.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final deal = deals[index];
                  return SizedBox(
                    width: 260,
                    child: ExploreDealCard(
                      deal: deal,
                      onTap: () => openDealDetail(context, deal),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Experiences ─────────────────────────────────────────────────────────────

class _ExperiencesSection extends StatelessWidget {
  const _ExperiencesSection({required this.events, required this.onOpen});

  final List<Dinner> events;
  final void Function(Dinner dinner) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeading(
          title: 'Experiences',
          trailing: Text(
            '${events.length} upcoming',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
        for (final dinner in events)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ExperienceCard(
              dinner: dinner,
              onTap: () => onOpen(dinner),
              onReserve: () => onOpen(dinner),
            ),
          ),
      ],
    );
  }
}

// ─── Reviews ─────────────────────────────────────────────────────────────────

class _ReviewsSection extends ConsumerStatefulWidget {
  const _ReviewsSection({required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends ConsumerState<_ReviewsSection> {
  bool _showAll = false;

  void _openWriteReview() {
    final repo = ref.read(restaurantReviewsRepositoryProvider);
    _showWriteReviewSheet(context, repo, widget.restaurantId);
  }

  @override
  Widget build(BuildContext context) {
    final reviewsAsync = ref.watch(restaurantReviewsProvider(widget.restaurantId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeading(
          title: 'Reviews',
          trailing: TextButton.icon(
            onPressed: _openWriteReview,
            icon: const Icon(Icons.edit_rounded, size: 14),
            label: const Text('Write a review'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        reviewsAsync.when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          error: (_, _) => const _InlineNote(
            icon: Icons.rate_review_outlined,
            message: 'Reviews are unavailable right now.',
          ),
          data: (feed) {
            if (feed.isEmpty) {
              return const _InlineNote(
                icon: Icons.rate_review_outlined,
                message: 'No reviews yet. Be the first to share your visit.',
              );
            }
            final visible = _showAll ? feed.reviews : feed.reviews.take(3);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewsSummary(
                  aggregate: feed.aggregate,
                  reviews: feed.reviews,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final review in visible) _ReviewTile(review: review),
                if (feed.reviews.length > 3)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                      child: Text(
                        _showAll
                            ? 'Show fewer reviews'
                            : 'Show all ${feed.reviews.length} reviews',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Aggregate rating plus the 5→1 star split derived from the reviews actually
/// returned. The split is only shown once there are enough rows for it to mean
/// something; there is no fabricated distribution for thin venues.
class _ReviewsSummary extends StatelessWidget {
  const _ReviewsSummary({required this.aggregate, required this.reviews});

  final RestaurantReviewAggregate aggregate;
  final List<RestaurantReview> reviews;

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{for (var s = 1; s <= 5; s++) s: 0};
    for (final review in reviews) {
      final star = review.rating.round().clamp(1, 5);
      counts[star] = (counts[star] ?? 0) + 1;
    }
    final total = reviews.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                aggregate.rating.toStringAsFixed(1),
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StarRating(rating: aggregate.rating),
                    const SizedBox(height: 2),
                    Text(
                      '${aggregate.count} ${aggregate.count == 1 ? 'review' : 'reviews'}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (total >= 3) ...[
            const SizedBox(height: AppSpacing.md),
            for (var star = 5; star >= 1; star--)
              _RatingBarRow(
                star: star,
                count: counts[star] ?? 0,
                total: total,
              ),
          ],
        ],
      ),
    );
  }
}

class _RatingBarRow extends StatelessWidget {
  const _RatingBarRow({
    required this.star,
    required this.count,
    required this.total,
  });

  final int star;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$star',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Icon(Icons.star_rounded, size: 12, color: AppColors.gold),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 5,
                backgroundColor: AppColors.surfaceHigh,
                valueColor: const AlwaysStoppedAnimation(AppColors.gold),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final RestaurantReview review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: AppSpacing.avatarXs / 2,
                backgroundColor: AppColors.surfaceHigh,
                child: Text(
                  review.authorName.isNotEmpty
                      ? review.authorName[0].toUpperCase()
                      : '?',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  review.authorName,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StarRating(rating: review.rating),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            review.text,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (review.hasPartnerReply) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.business_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Response from restaurant',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    review.partnerReply!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatDate(review.createdAt),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'Just now';
  }
}

class _StarRating extends StatelessWidget {
  final double rating;
  const _StarRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    final fullStars = rating.floor();
    final hasHalf = rating - fullStars >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < fullStars
                ? Icons.star_rounded
                : (i == fullStars && hasHalf)
                ? Icons.star_half_rounded
                : Icons.star_border_rounded,
            size: 14,
            color: AppColors.gold,
          ),
      ],
    );
  }
}

// ─── Small shared pieces ─────────────────────────────────────────────────────

/// Flat inline message used for empty / unavailable states inside a section.
/// Deliberately not a tall `EmptyStateView`: these live mid-page, next to real
/// content, so they must not take over the viewport.
class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Sticky bottom bar: browse the menu or book a table, always one tap away.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.horizontalPadding,
    required this.onViewMenu,
    required this.onReserve,
  });

  final double horizontalPadding;
  final VoidCallback onViewMenu;
  final VoidCallback onReserve;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.sm,
          horizontalPadding,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: SecondaryButton(
                text: 'View Menu',
                icon: Icons.restaurant_menu_rounded,
                onPressed: onViewMenu,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 7,
              child: PrimaryButton(
                text: 'Reserve Table',
                icon: Icons.event_seat_rounded,
                onPressed: onReserve,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Your table ─────────────────────────────────────────────────────────────

/// "Your table" reservation status card shown when the user has an upcoming
/// reservation at this restaurant. Renders nothing when there's no match.
class _YourTableCard extends ConsumerWidget {
  const _YourTableCard({required this.restaurantId});

  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationsAsync = ref.watch(myReservationsProvider);
    return reservationsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (reservations) {
        final now = DateTime.now();
        final upcoming =
            reservations
                .where(
                  (r) =>
                      r.restaurantId == restaurantId &&
                      r.startAt.isAfter(now) &&
                      !r.isCancelled &&
                      !r.isCompleted,
                )
                .toList()
              ..sort((a, b) => a.startAt.compareTo(b.startAt));

        if (upcoming.isEmpty) return const SizedBox.shrink();

        final reservation = upcoming.first;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(
                    Icons.event_seat_rounded,
                    size: 20,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your table',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${reservation.reference} \u00b7 ${reservation.partySize} '
                        '${reservation.partySize == 1 ? 'guest' : 'guests'}',
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _formatReservationDateTime(reservation.startAt),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: reservation.isConfirmed
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    reservation.isConfirmed ? 'Confirmed' : 'Pending',
                    style: AppTextStyles.caption.copyWith(
                      color: reservation.isConfirmed
                          ? AppColors.success
                          : AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatReservationDateTime(DateTime dt) {
    final local = dt.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
    return '$date at ${formatVenueTime(dt)}';
  }
}

// ─── Write review sheet ──────────────────────────────────────────────────────

void _showWriteReviewSheet(
  BuildContext context,
  RestaurantReviewsRepository repo,
  String restaurantId,
) {
  double rating = 0;
  final controller = TextEditingController();
  bool submitting = false;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              top: AppSpacing.md,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Write a review', style: AppTextStyles.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text('Your rating: ', style: AppTextStyles.bodySmall),
                    const SizedBox(width: AppSpacing.sm),
                    ...List.generate(5, (i) {
                      return GestureDetector(
                        onTap: submitting
                            ? null
                            : () => setSheetState(
                                () => rating = (i + 1).toDouble(),
                              ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            i < rating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 28,
                            color: AppColors.gold,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controller,
                  enabled: !submitting,
                  maxLines: 4,
                  maxLength: 2000,
                  style: AppTextStyles.bodySmall,
                  decoration: InputDecoration(
                    hintText: 'Share your experience...',
                    hintStyle: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        submitting ||
                            rating == 0 ||
                            controller.text.trim().isEmpty
                        ? null
                        : () async {
                            setSheetState(() => submitting = true);
                            try {
                              await repo.submit(
                                restaurantId,
                                rating: rating,
                                text: controller.text.trim(),
                              );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Review submitted!'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setSheetState(() => submitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not submit review: $e',
                                    ),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.surfaceHigh,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                    ),
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Submit review',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// ─── Skeleton ────────────────────────────────────────────────────────────────

/// Full-page skeleton shown while `/restaurants/:id` resolves with no seed
/// (QR scan, deep link). Mirrors the hero + section-nav silhouette so the
/// transition into the real screen feels like a reveal, not a blank page.
class _RestaurantProfileSkeleton extends StatelessWidget {
  const _RestaurantProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(backgroundColor: AppColors.bg),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        children: const [
          SkeletonBox(height: 220, radius: AppSpacing.radiusLg),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(width: 220, height: 28),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 140, height: 16),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 64, radius: AppSpacing.radiusXl),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(width: 260, height: 32, radius: AppSpacing.radiusFull),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(height: 96, radius: AppSpacing.radiusMd),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 96, radius: AppSpacing.radiusMd),
        ],
      ),
    );
  }
}
