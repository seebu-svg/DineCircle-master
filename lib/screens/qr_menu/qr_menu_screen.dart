import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/public_menu.dart';
import '../../providers/api_client_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/opening_hours.dart';
import '../../widgets/data_view.dart';
import '../../widgets/media_image.dart';
import 'dish_detail_sheet.dart';
import 'menu_dish_card.dart';

/// Provider that fetches the unauthenticated public menu by restaurant UUID.
final publicMenuProvider =
    FutureProvider.family<PublicMenu, String>((ref, restaurantId) async {
  final repo = ref.watch(publicMenuRepositoryProvider);
  final menu = await repo.fetch(restaurantId);
  // Record the scan for analytics (fire-and-forget).
  repo.recordScan(restaurantId);
  return menu;
});

/// Full restaurant menu — the food-first surface a diner reaches from the venue
/// profile or by scanning the table QR code.
///
/// Fetches `GET /api/public/menu/:restaurantId` (unauthenticated) and renders a
/// collapsible venue hero, a dish search, dietary filters, sticky category tabs
/// and compact image-forward dish cards. Prices are PKR and read-only: the guest
/// browses the menu and orders with restaurant staff, so there is no cart,
/// checkout or payment anywhere on this screen.
class QrMenuScreen extends ConsumerStatefulWidget {
  const QrMenuScreen({super.key, required this.restaurantId, this.initialQuery});

  final String restaurantId;

  /// Seeds the dish search, so a universal-search dish hit lands on the venue's
  /// menu already narrowed to that dish instead of the full catalogue.
  final String? initialQuery;

  @override
  ConsumerState<QrMenuScreen> createState() => _QrMenuScreenState();
}

class _QrMenuScreenState extends ConsumerState<QrMenuScreen> {
  /// Height of the pinned category-tab strip, including its vertical padding.
  static const double _tabBarExtent = 52;

  /// Height of the expanded hero. Chosen so the venue name, location and
  /// opening status fit above the pinned tabs on a 640dp-tall phone.
  static const double _heroExtent = 216;

  final ScrollController _scroll = ScrollController();
  final ScrollController _tabsScroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _tabKeys = <String, GlobalKey>{};

  /// Content offsets of each visible section, measured after layout.
  List<double> _sectionOffsets = const <double>[];

  /// Sections currently rendered; recomputed on every build from the menu plus
  /// the active query/filters.
  List<_MenuSectionView> _views = const <_MenuSectionView>[];

  String _query = '';
  final Set<String> _activeTags = <String>{};
  int _activeIndex = 0;
  bool _headerCollapsed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _query = initial;
      _search.text = initial;
    }
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tabsScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  // ── Scroll + tab sync ──────────────────────────────────────────────────────

  double get _stickyExtent =>
      kToolbarHeight + MediaQuery.paddingOf(context).top + _tabBarExtent;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pixels = _scroll.position.pixels;

    // Collapse the app bar title once the hero has scrolled behind the toolbar.
    final collapsed = pixels > _heroExtent - kToolbarHeight - 24;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }

    if (_sectionOffsets.length != _views.length) {
      _measureSectionOffsets();
      if (_sectionOffsets.length != _views.length) return;
    }
    final next = _indexForOffset(pixels);
    if (next != _activeIndex) {
      setState(() => _activeIndex = next);
      _revealActiveTab();
    }
  }

  int _indexForOffset(double pixels) {
    final threshold = pixels + _stickyExtent + 8;
    var index = 0;
    for (var i = 0; i < _sectionOffsets.length; i++) {
      if (_sectionOffsets[i] <= threshold) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  /// Measures each section's offset inside the scroll content.
  ///
  /// Sections are laid out eagerly inside a single box sliver, so every key has
  /// a render object after the first frame and the offsets stay exact until the
  /// filtered section list changes.
  void _measureSectionOffsets() {
    if (!_scroll.hasClients || _views.isEmpty) {
      _sectionOffsets = const <double>[];
      return;
    }
    final offsets = <double>[];
    for (final view in _views) {
      final object = _sectionKeys[view.section.id]?.currentContext?.findRenderObject();
      if (object is! RenderBox || !object.hasSize) {
        _sectionOffsets = const <double>[];
        return;
      }
      final viewport = RenderAbstractViewport.of(object);
      offsets.add(viewport.getOffsetToReveal(object, 0).offset);
    }
    _sectionOffsets = offsets;
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureSectionOffsets();
    });
  }

  void _onSelectTab(int index) {
    setState(() => _activeIndex = index);
    if (_sectionOffsets.length != _views.length) _measureSectionOffsets();
    if (index >= _sectionOffsets.length || !_scroll.hasClients) return;
    final target = (_sectionOffsets[index] - _stickyExtent).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Keeps the highlighted category visible in the horizontal tab strip without
  /// touching the vertical scroll position.
  void _revealActiveTab() {
    if (_activeIndex >= _views.length || !_tabsScroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabsScroll.hasClients) return;
      if (_activeIndex >= _views.length) return;
      final object = _tabKeys[_views[_activeIndex].section.id]
          ?.currentContext
          ?.findRenderObject();
      if (object is! RenderBox || !object.hasSize) return;
      final viewport = RenderAbstractViewport.of(object);
      final target = viewport
          .getOffsetToReveal(object, 0.5)
          .offset
          .clamp(0.0, _tabsScroll.position.maxScrollExtent);
      _tabsScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<_MenuSectionView> _buildViews(PublicMenu menu) {
    final query = _query.trim().toLowerCase();
    final views = <_MenuSectionView>[];
    for (final section in menu.filledSections) {
      final items = section.items.where((item) {
        if (query.isNotEmpty &&
            !item.name.toLowerCase().contains(query) &&
            !item.description.toLowerCase().contains(query)) {
          return false;
        }
        if (_activeTags.isEmpty) return true;
        return item.normalizedDietaryTags.any(_activeTags.contains);
      }).toList();
      if (items.isEmpty) continue;
      views.add(_MenuSectionView(section: section, items: items));
    }
    return views;
  }

  /// Dietary tags actually present on this menu, with how many dishes carry
  /// each one. Only real data is offered as a filter.
  Map<String, int> _tagCounts(PublicMenu menu) {
    final counts = <String, int>{};
    for (final section in menu.filledSections) {
      for (final item in section.items) {
        for (final tag in item.normalizedDietaryTags) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  void _toggleTag(String tag) {
    setState(() {
      if (!_activeTags.remove(tag)) _activeTags.add(tag);
      _activeIndex = 0;
      _sectionOffsets = const <double>[];
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _clearFilters() {
    setState(() {
      _activeTags.clear();
      _query = '';
      _search.clear();
      _activeIndex = 0;
      _sectionOffsets = const <double>[];
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(publicMenuProvider(widget.restaurantId));
    final data = menuAsync.valueOrNull;
    // Loading, error and "no menu published" states keep a plain app bar so the
    // guest always has a way back; the data state draws its own hero header.
    final showPlainBar = data == null || data.filledSections.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: showPlainBar
          ? AppBar(
              backgroundColor: AppColors.bg,
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: const Text('Menu', maxLines: 1),
              ),
            )
          : null,
      body: DataView<PublicMenu>(
        value: menuAsync,
        onRetry: () =>
            ref.invalidate(publicMenuProvider(widget.restaurantId)),
        isEmpty: (menu) => menu.filledSections.isEmpty,
        emptyWidget: const EmptyStateView(
          icon: Icons.restaurant_menu_rounded,
          message: 'No menu items available right now.\nPlease ask the staff.',
        ),
        builder: (context, menu) => _buildMenu(context, menu),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, PublicMenu menu) {
    _views = _buildViews(menu);
    final tagCounts = _tagCounts(menu);
    final bottomInset = AppSpacing.xxl + MediaQuery.paddingOf(context).bottom;
    // Content height changes whenever a filter narrows the list, so offsets are
    // re-measured after every layout pass instead of on scroll only.
    _scheduleMeasure();

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        _hero(menu.restaurant),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.paddingScreen,
                  AppSpacing.lg,
                  AppSpacing.paddingScreen,
                  0,
                ),
                child: _SearchField(
                  controller: _search,
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                      _activeIndex = 0;
                      _sectionOffsets = const <double>[];
                    });
                  },
                ),
              ),
            ),
          ),
        ),
        if (tagCounts.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _DietaryFilterBar(
                    tags: _sortedTags(tagCounts),
                    counts: tagCounts,
                    active: _activeTags,
                    onToggle: _toggleTag,
                    onClear: _clearFilters,
                  ),
                ),
              ),
            ),
          ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _CategoryTabsDelegate(
            extent: _tabBarExtent,
            child: _CategoryTabs(
              views: _views,
              activeIndex: _activeIndex,
              controller: _tabsScroll,
              keyFor: (id) => _tabKeys.putIfAbsent(id, () => GlobalKey()),
              onSelect: _onSelectTab,
            ),
          ),
        ),
        if (_views.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paddingScreen,
                AppSpacing.xxl,
                AppSpacing.paddingScreen,
                AppSpacing.xxl,
              ),
              child: _NoResults(onClear: _clearFilters),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.paddingScreen,
                    AppSpacing.lg,
                    AppSpacing.paddingScreen,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final view in _views)
                        _SectionBlock(
                          key: _sectionKeys.putIfAbsent(
                            view.section.id,
                            () => GlobalKey(),
                          ),
                          view: view,
                          onDishTap: (item) => showDishDetail(
                            context,
                            item: item,
                            sectionName: view.section.name,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.paddingScreen,
              AppSpacing.sm,
              AppSpacing.paddingScreen,
              bottomInset,
            ),
            child: Column(
              children: [
                const Divider(color: AppColors.border, height: AppSpacing.lg),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Menu items and prices are provided by the restaurant.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Collapsible venue header: cover art, name, location and a compact
  /// open/closed status. Opening hours and facilities live on the venue profile,
  /// not here.
  Widget _hero(PublicMenuRestaurant restaurant) {
    final days = parseOpeningHours(restaurant.openingHours);
    return SliverAppBar(
      pinned: true,
      expandedHeight: _heroExtent,
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: const _CircleBackButton(),
      title: AnimatedOpacity(
        opacity: _headerCollapsed ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Text(
          restaurant.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.titleMedium,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _MenuHero(restaurant: restaurant, days: days),
      ),
    );
  }

  List<String> _sortedTags(Map<String, int> counts) {
    const priority = ['vegetarian', 'vegan', 'halal', 'gluten-free', 'dairy-free', 'contains-nuts', 'seafood', 'spicy'];
    final tags = counts.keys.toList();
    tags.sort((a, b) {
      final ai = priority.indexOf(a);
      final bi = priority.indexOf(b);
      if (ai != -1 || bi != -1) {
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      }
      return a.compareTo(b);
    });
    return tags;
  }
}

/// Immutable snapshot of one section with the items that survive the filters.
class _MenuSectionView {
  const _MenuSectionView({required this.section, required this.items});

  final PublicMenuSection section;
  final List<PublicMenuItem> items;
}

// ─── Hero ────────────────────────────────────────────────────────────────────

class _MenuHero extends StatelessWidget {
  const _MenuHero({required this.restaurant, required this.days});

  final PublicMenuRestaurant restaurant;
  final List<DayView> days;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final location = restaurant.locationLine;
    final today = days.isEmpty ? null : days[DateTime.now().weekday - 1];
    final openNow = isCurrentlyOpen(days);

    return Stack(
      fit: StackFit.expand,
      children: [
        MediaImage(
          source: restaurant.coverImage,
          cacheWidth: (width * dpr).round(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.35),
                AppColors.bg.withValues(alpha: 0.55),
                AppColors.bg,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.paddingScreen,
              0,
              AppSpacing.paddingScreen,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurant.name,
                  style: AppTextStyles.headlineMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          location,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (today != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _OpenStatusPill(isOpen: openNow),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          openNow ? 'Today ${today.summary}' : today.summary,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OpenStatusPill extends StatelessWidget {
  const _OpenStatusPill({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isOpen ? 'Open now' : 'Closed',
            style: AppTextStyles.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Material(
        color: AppColors.bg.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Search + filters ────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      borderSide: BorderSide(color: color),
    );

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: AppTextStyles.bodyMedium,
      cursorColor: AppColors.primary,
      cursorHeight: 18,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search dishes, drinks, desserts',
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: AppColors.textTertiary,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                tooltip: 'Clear search',
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 12,
        ),
        border: border(AppColors.border),
        enabledBorder: border(AppColors.border),
        focusedBorder: border(AppColors.primary.withValues(alpha: 0.55)),
      ),
    );
  }
}

class _DietaryFilterBar extends StatelessWidget {
  const _DietaryFilterBar({
    required this.tags,
    required this.counts,
    required this.active,
    required this.onToggle,
    required this.onClear,
  });

  /// Tags present on this menu in display order.
  final List<String> tags;

  /// How many dishes carry each tag.
  final Map<String, int> counts;
  final Set<String> active;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.paddingScreen,
          ),
          itemCount: tags.length + (active.isEmpty ? 0 : 1),
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            if (active.isNotEmpty && index == tags.length) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Center(
                  child: Text(
                    'Clear',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }
            final tag = tags[index];
            return Center(
              child: DietaryChip(
                tag: tag,
                selected: active.contains(tag),
                onTap: () => onToggle(tag),
                count: counts[tag],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Category tabs ───────────────────────────────────────────────────────────

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.views,
    required this.activeIndex,
    required this.controller,
    required this.keyFor,
    required this.onSelect,
  });

  final List<_MenuSectionView> views;
  final int activeIndex;
  final ScrollController controller;
  final GlobalKey Function(String id) keyFor;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        color: AppColors.bg,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.paddingScreen,
          ),
          itemCount: views.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) {
            final view = views[index];
            final selected = index == activeIndex;
            return Center(
              child: Semantics(
                button: true,
                selected: selected,
                child: GestureDetector(
                  key: keyFor(view.section.id),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    height: 34,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: selected ? AppColors.primaryGradient : null,
                      color: selected ? null : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      view.section.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: selected
                            ? AppColors.bg
                            : AppColors.textSecondary,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryTabsDelegate extends SliverPersistentHeaderDelegate {
  _CategoryTabsDelegate({required this.extent, required this.child});

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: extent, child: child);
  }

  @override
  bool shouldRebuild(covariant _CategoryTabsDelegate oldDelegate) =>
      oldDelegate.extent != extent || oldDelegate.child != child;
}

// ─── Sections ────────────────────────────────────────────────────────────────

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    super.key,
    required this.view,
    required this.onDishTap,
  });

  final _MenuSectionView view;
  final ValueChanged<PublicMenuItem> onDishTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                view.section.name,
                style: AppTextStyles.headlineSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${view.items.length} ${view.items.length == 1 ? 'item' : 'items'}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final item in view.items)
          DishCard(
            item: item,
            onTap: () => onDishTap(item),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.search_off_rounded,
          size: 36,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No dishes match your filters',
          style: AppTextStyles.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Try a different search or clear the dietary filters.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(onPressed: onClear, child: const Text('Clear filters')),
      ],
    );
  }
}
