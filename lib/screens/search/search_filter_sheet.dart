import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/search.dart';
import '../../providers/saved_locations_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/buttons.dart';

/// Cuisines offered as one-tap chips. Values are matched server-side against
/// `restaurants.cuisines`, so they are free text rather than a foreign key.
const List<String> kSearchCuisines = [
  'Sushi',
  'BBQ',
  'Italian',
  'Pakistani',
  'Chinese',
  'Continental',
  'Burgers',
  'Desserts',
  'Seafood',
  'Cafe',
];

/// Venue type chips (`value`, `label`), matched against the venue tag arrays.
const List<(String, String)> kSearchVenueTypes = [
  ('fine dining', 'Fine dining'),
  ('casual', 'Casual'),
  ('rooftop', 'Rooftop'),
  ('cafe', 'Café'),
  ('family', 'Family'),
];

/// Deal category chips (`value`, `label`).
const List<(String, String)> kSearchDealKinds = [
  ('percent', 'Percentage'),
  ('fixed', 'Fixed discount'),
  ('package', 'Package'),
];

/// Opens the filter sheet and returns the applied filters, or null on dismiss.
Future<SearchFilters?> showSearchFilterSheet(
  BuildContext context,
  SearchFilters initial,
) {
  return showModalBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
    ),
    builder: (_) => SearchFilterSheet(initial: initial),
  );
}

/// Location, cuisine, venue type, deal category, experience date and
/// availability, every filter the API accepts, edited as a local draft so the
/// list behind the sheet never re-queries mid-selection.
class SearchFilterSheet extends ConsumerStatefulWidget {
  const SearchFilterSheet({super.key, required this.initial});

  final SearchFilters initial;

  @override
  ConsumerState<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends ConsumerState<SearchFilterSheet> {
  late String _city = widget.initial.city;
  late String _cuisine = widget.initial.cuisine;
  late String _venueType = widget.initial.venueType;
  late String _dealKind = widget.initial.dealKind;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;
  late bool _availableOnly = widget.initial.availableOnly;

  SearchFilters get _draft => widget.initial.copyWith(
    city: _city,
    cuisine: _cuisine,
    venueType: _venueType,
    dealKind: _dealKind,
    availableOnly: _availableOnly,
    from: _from,
    to: _to,
    clearDates: _from == null && _to == null,
  );

  void _reset() {
    setState(() {
      _city = '';
      _cuisine = '';
      _venueType = '';
      _dealKind = '';
      _from = null;
      _to = null;
      _availableOnly = false;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
      helpText: 'Experience dates',
    );
    if (picked == null) return;
    setState(() {
      _from = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _to = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
    });
  }

  void _applyPreset(int days, {bool weekend = false}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (weekend) {
      // Saturday through Sunday of the coming weekend (today counts).
      final untilSaturday = (DateTime.saturday - today.weekday + 7) % 7;
      final saturday = today.add(Duration(days: untilSaturday));
      setState(() {
        _from = saturday;
        _to = saturday.add(
          const Duration(days: 1, hours: 23, minutes: 59, seconds: 59),
        );
      });
      return;
    }
    setState(() {
      _from = today;
      _to = days == 0
          ? DateTime(today.year, today.month, today.day, 23, 59, 59)
          : today.add(Duration(days: days, hours: 23, minutes: 59, seconds: 59));
    });
  }

  String? get _dateLabel {
    if (_from == null && _to == null) return null;
    if (_from == null) return 'Until ${_short(_to!)}';
    if (_to == null) return 'From ${_short(_from!)}';
    return '${_short(_from!)} – ${_short(_to!)}';
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

  static String _short(DateTime date) =>
      '${date.day} ${_months[date.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(supportedCityNamesProvider);
    final draft = _draft;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          key: const Key('searchFilterSheet'),
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paddingScreen,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Filters', style: AppTextStyles.headlineSmall),
                  ),
                  TextButton(
                    key: const Key('searchResetFilters'),
                    onPressed: draft.hasFilters ? _reset : null,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.paddingScreen,
                  AppSpacing.lg,
                  AppSpacing.paddingScreen,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('Location'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        TagChip(
                          label: 'Anywhere',
                          isSelected: _city.isEmpty,
                          onTap: () => setState(() => _city = ''),
                        ),
                        for (final city in cities)
                          TagChip(
                            label: city,
                            isSelected: _city == city,
                            onTap: () => setState(
                              () => _city = _city == city ? '' : city,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SectionLabel('Cuisine'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final cuisine in kSearchCuisines)
                          TagChip(
                            label: cuisine,
                            isSelected: _cuisine == cuisine,
                            onTap: () => setState(
                              () => _cuisine = _cuisine == cuisine
                                  ? ''
                                  : cuisine,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SectionLabel('Restaurant type'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final (value, label) in kSearchVenueTypes)
                          TagChip(
                            label: label,
                            isSelected: _venueType == value,
                            onTap: () => setState(
                              () => _venueType = _venueType == value
                                  ? ''
                                  : value,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SectionLabel('Deal category'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final (value, label) in kSearchDealKinds)
                          TagChip(
                            label: label,
                            isSelected: _dealKind == value,
                            onTap: () => setState(
                              () => _dealKind = _dealKind == value ? '' : value,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SectionLabel('Experience date'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        TagChip(
                          label: 'Today',
                          isSelected: _isPreset(0),
                          onTap: () => _applyPreset(0),
                        ),
                        TagChip(
                          label: 'This weekend',
                          onTap: () => _applyPreset(0, weekend: true),
                        ),
                        TagChip(
                          label: 'Next 7 days',
                          isSelected: _isPreset(7),
                          onTap: () => _applyPreset(7),
                        ),
                        ActionChip(
                          key: const Key('searchCustomDate'),
                          avatar: const Icon(
                            Icons.calendar_month_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          label: Text(
                            _dateLabel ?? 'Custom range',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          backgroundColor: AppColors.surfaceElevated,
                          side: const BorderSide(color: AppColors.border),
                          onPressed: _pickRange,
                        ),
                        if (_from != null || _to != null)
                          ActionChip(
                            avatar: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppColors.textTertiary,
                            ),
                            label: const Text('Any date'),
                            backgroundColor: AppColors.surfaceElevated,
                            side: const BorderSide(color: AppColors.border),
                            labelStyle: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.textTertiary,
                            ),
                            onPressed: () => setState(() {
                              _from = null;
                              _to = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile.adaptive(
                      key: const Key('searchAvailabilitySwitch'),
                      contentPadding: EdgeInsets.zero,
                      value: _availableOnly,
                      onChanged: (value) =>
                          setState(() => _availableOnly = value),
                      title: Text(
                        'Available only',
                        style: AppTextStyles.titleSmall,
                      ),
                      subtitle: Text(
                        'Experiences with seats left',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paddingScreen,
                AppSpacing.sm,
                AppSpacing.paddingScreen,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      draft.activeCount == 0
                          ? 'No filters selected'
                          : '${draft.activeCount} filter${draft.activeCount == 1 ? '' : 's'} selected',
                      style: AppTextStyles.caption,
                    ),
                  ),
                  PrimaryButton(
                    key: const Key('searchApplyFilters'),
                    text: 'Apply',
                    isFullWidth: false,
                    onPressed: () => Navigator.pop(context, draft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// True when the current window is the plain "today"/"next N days" preset.
  bool _isPreset(int days) {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (from != today) return false;
    final end = days == 0
        ? DateTime(today.year, today.month, today.day, 23, 59, 59)
        : today.add(Duration(days: days, hours: 23, minutes: 59, seconds: 59));
    return to == end;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.labelMedium.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 0.6,
      ),
    );
  }
}
