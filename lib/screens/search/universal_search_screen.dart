import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/deal.dart';
import '../../models/dinner.dart';
import '../../models/restaurant.dart';
import '../../models/search.dart';
import '../../models/user_profile.dart';
import '../../providers/location_provider.dart';
import '../../providers/search_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debouncer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/skeleton_placeholder.dart';
import 'search_filter_sheet.dart';
import 'search_result_tiles.dart';

/// The single search surface for the whole app.
///
/// One text field, one debounce (300 ms) and one server call (`GET /api/search`)
/// back restaurants, dishes, deals, experiences and hosts at once, so Home,
/// Explore and Deals all hand off to the same complete experience instead of
/// four inconsistent client-side filters. Typing only refreshes the typeahead;
/// the ranked result list is replaced when the user submits (keyboard action, a
/// suggestion tap or a recent chip), which keeps committed rows on screen while
/// the next word is typed.
class UniversalSearchScreen extends ConsumerStatefulWidget {
  const UniversalSearchScreen({
    super.key,
    this.initialQuery,
    this.initialCategory,
    this.autofocus = true,
    this.onLocationTap,
  });

  /// Seeds both the field and the first search.
  final String? initialQuery;

  /// Pre-selects a category chip (Deals' trailing action opens on deals).
  final SearchCategory? initialCategory;
  final bool autofocus;

  /// Opens the app's location picker; the field's city chip mirrors
  /// [userCityProvider] either way.
  final VoidCallback? onLocationTap;

  @override
  ConsumerState<UniversalSearchScreen> createState() =>
      _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends ConsumerState<UniversalSearchScreen> {
  /// Long enough to swallow a fast typist, short enough that suggestions feel
  /// immediate. Matches the app-wide debounce used by Explore and Deals.
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  /// Example queries shown on the idle and empty states.
  static const List<String> _exampleQueries = [
    'Sushi',
    'BBQ',
    'Brunch',
    'Steak',
    'Rooftop',
    'Dessert',
  ];

  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final Debouncer _debouncer = Debouncer(_debounceDelay);

  /// Debounced text driving the suggestion query.
  String _term = '';

  /// True while the user is editing, so the typeahead panel only covers the
  /// results when a keystroke actually happened.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    _controller = TextEditingController(text: initial);
    _term = initial;
    // The controller is app-global, so seed it after the first frame rather
    // than mutating another provider's state during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(searchControllerProvider.notifier);
      if (widget.initialCategory != null) {
        controller.selectCategory(widget.initialCategory);
      }
      if (initial.isEmpty) {
        controller.clear();
      } else {
        controller.submit(initial);
      }
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final term = value.trim();
    if (!_editing) setState(() => _editing = true);
    _debouncer.run(() {
      if (!mounted) return;
      setState(() => _term = term);
      ref.read(searchControllerProvider.notifier).queryChanged(term);
    });
  }

  Future<void> _submit(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    _debouncer.cancel();
    if (_controller.text != query) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    _focusNode.unfocus();
    setState(() {
      _term = query;
      _editing = false;
    });
    await ref.read(searchControllerProvider.notifier).submit(query);
  }

  void _clearField() {
    _debouncer.cancel();
    _controller.clear();
    setState(() {
      _term = '';
      _editing = true;
    });
    ref.read(searchControllerProvider.notifier).clear();
  }

  Future<void> _openFilters() async {
    final current = ref.read(searchControllerProvider).filters;
    final applied = await showSearchFilterSheet(context, current);
    if (applied == null || !mounted) return;
    await ref.read(searchControllerProvider.notifier).applyFilters(applied);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    final city = ref.watch(userCityProvider);

    final showSuggestions = _editing && _term.trim().length >= 2;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: _SearchField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onChanged: _onChanged,
          onSubmitted: _submit,
          onClear: _clearField,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: IconButton(
              key: const Key('searchFilterButton'),
              tooltip: 'Filters',
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: state.filters.activeCount > 0,
                backgroundColor: AppColors.primary,
                label: Text('${state.filters.activeCount}'),
                child: const Icon(Icons.tune_rounded),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CityRow(
              city: city,
              onTap: widget.onLocationTap,
              filterCount: state.filters.activeCount,
              onClearFilters: state.filters.hasFilters
                  ? controller.clearFilters
                  : null,
            ),
            if (showSuggestions)
              _SuggestionPanel(term: _term, onSelected: _submit),
            Expanded(child: _buildBody(state, controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SearchState state, UniversalSearchController controller) {
    if (state.isIdle) {
      return _IdleView(
        examples: _exampleQueries,
        onSearch: _submit,
      );
    }
    if (state.status == SearchStatus.loading && !state.hasResults) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.paddingScreen),
        child: SkeletonList(itemCount: 5, itemHeight: 72),
      );
    }
    if (state.hasError) return _errorState(state, controller);
    if (state.isEmptyResult) return _emptyState(state, controller);
    return _results(state, controller);
  }

  Widget _errorState(SearchState state, UniversalSearchController controller) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              state.error ?? 'Search is unavailable right now.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              key: const Key('searchRetry'),
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(SearchState state, UniversalSearchController controller) {
    return ListView(
      key: const Key('searchEmptyState'),
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      children: [
        const SizedBox(height: AppSpacing.xl),
        const Icon(
          Icons.search_off_rounded,
          size: 56,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'No results for "${state.filters.query.trim()}"',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          state.filters.hasFilters
              ? 'Some filters may be too narrow. Clear them or try a '
                    'different phrase.'
              : 'Try a different spelling or a broader keyword — a cuisine, a '
                    'neighbourhood or a venue name.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (state.filters.hasFilters) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton.icon(
              key: const Key('searchClearFilters'),
              onPressed: controller.clearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Clear filters'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final example in _exampleQueries)
              TagChip(label: example, onTap: () => _submit(example)),
          ],
        ),
      ],
    );
  }

  Widget _results(SearchState state, UniversalSearchController controller) {
    final categories = state.category == null
        ? SearchCategory.values
        : [state.category!];
    final anyMore = SearchCategory.values.any(
      (category) => state.results.hasMoreFor(category),
    );

    return Column(
      children: [
        if (state.isLoading)
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: AppColors.surface,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        _CategoryChips(state: state, controller: controller),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.paddingScreen,
              0,
              AppSpacing.paddingScreen,
              AppSpacing.xxl,
            ),
            children: [
              for (final category in categories)
                ..._section(state, controller, category),
              if (anyMore && state.loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One category's header, rows and (when the server has more) its own
  /// "Load more" action.
  List<Widget> _section(
    SearchState state,
    UniversalSearchController controller,
    SearchCategory category,
  ) {
    final items = state.results.itemsFor(category);
    if (items.isEmpty) return const [];
    final total = state.results.countFor(category);
    final canSeeAll = state.category == null && total > items.length;

    return [
      const SizedBox(height: AppSpacing.md),
      SectionHeader(
        key: Key('searchSection_${category.apiKey}'),
        title: '${category.label} ($total)',
        actionText: canSeeAll ? 'See all' : null,
        onAction: canSeeAll ? () => controller.selectCategory(category) : null,
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _tileFor(item),
        ),
      if (state.results.hasMoreFor(category))
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Center(
            child: TextButton.icon(
              key: Key('searchLoadMore_${category.apiKey}'),
              onPressed: state.loadingMore ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text('More ${category.label.toLowerCase()}'),
            ),
          ),
        ),
    ];
  }

  Widget _tileFor(Object item) => switch (item) {
    final Restaurant restaurant => RestaurantResultTile(restaurant: restaurant),
    final MenuItemHit hit => MenuItemResultTile(item: hit),
    final Deal deal => DealResultTile(deal: deal),
    final Dinner dinner => ExperienceResultTile(dinner: dinner),
    final UserProfile host => HostResultTile(host: host),
    _ => const SizedBox.shrink(),
  };
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('searchField'),
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Restaurants, dishes, deals, hosts…',
        hintStyle: AppTextStyles.bodySmall.copyWith(
          color: AppColors.textTertiary,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textTertiary,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, child) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              key: const Key('searchClear'),
              tooltip: 'Clear search',
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              onPressed: onClear,
            );
          },
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

/// City chip plus the "n filters active" escape hatch.
class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.city,
    required this.onTap,
    required this.filterCount,
    required this.onClearFilters,
  });

  final String city;
  final VoidCallback? onTap;
  final int filterCount;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        0,
        AppSpacing.paddingScreen,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
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
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    city.trim().isEmpty ? 'Anywhere' : city,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.edit_location_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
              ],
            ),
          ),
          const Spacer(),
          if (filterCount > 0 && onClearFilters != null)
            TextButton(
              key: const Key('searchClearFilters'),
              onPressed: onClearFilters,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text('Clear $filterCount filter'
                  '${filterCount == 1 ? '' : 's'}'),
            ),
        ],
      ),
    );
  }
}

/// Typeahead list drawn between the field and the results.
class _SuggestionPanel extends ConsumerWidget {
  const _SuggestionPanel({required this.term, required this.onSelected});

  final String term;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(searchSuggestionsProvider(term));
    final rows = suggestions.valueOrNull ?? const <SearchSuggestion>[];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const Key('searchSuggestions'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        0,
        AppSpacing.paddingScreen,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows.take(6))
            InkWell(
              key: Key('searchSuggestion_${row.text}'),
              onTap: () => onSelected(row.text),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      row.kind.icon,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        row.text,
                        style: AppTextStyles.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      row.kind.apiKey,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Category chips with live counts; "All" is the same row's first entry.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.state, required this.controller});

  final SearchState state;
  final UniversalSearchController controller;

  @override
  Widget build(BuildContext context) {
    final selected = state.category;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: TagChip(
              key: const Key('searchCategory_all'),
              label: 'All (${state.results.total})',
              isSelected: selected == null,
              onTap: () => controller.selectCategory(null),
            ),
          ),
          for (final category in SearchCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TagChip(
                key: Key('searchCategory_${category.apiKey}'),
                label: '${category.label} (${state.results.countFor(category)})',
                isSelected: selected == category,
                onTap: () => controller.selectCategory(category),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pre-search state: recent terms (long-press to forget one) and examples.
class _IdleView extends ConsumerWidget {
  const _IdleView({required this.examples, required this.onSearch});

  final List<String> examples;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider).valueOrNull ?? const [];
    final notifier = ref.read(recentSearchesProvider.notifier);

    return ListView(
      key: const Key('searchIdle'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        AppSpacing.sm,
        AppSpacing.paddingScreen,
        AppSpacing.xxl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Recent searches', style: AppTextStyles.titleSmall),
            ),
            if (recents.isNotEmpty)
              TextButton(
                key: const Key('clearRecentSearches'),
                onPressed: () async {
                  await notifier.clear();
                },
                child: const Text('Clear'),
              ),
          ],
        ),
        if (recents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              'Your recent searches will show up here.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final term in recents)
                _RecentChip(
                  key: Key('recentSearch_$term'),
                  label: term,
                  onTap: () => onSearch(term),
                  onLongPress: () => notifier.remove(term),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.xl),
        Text('Popular right now', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final example in examples)
              TagChip(label: example, onTap: () => onSearch(example)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Icon(
              Icons.tips_and_updates_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Search a venue, a dish, a deal, an experience or a host — '
                'one field covers them all.',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Recent-search pill. Tapping re-runs it; long-pressing forgets it.
class _RecentChip extends StatelessWidget {
  const _RecentChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search again for $label',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
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
                Icons.history_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
