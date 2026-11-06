import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/saved_location.dart';
import '../../providers/location_provider.dart';
import '../../providers/saved_locations_provider.dart';
import '../../providers/users_provider.dart';
import '../../repositories/location_repository.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common_widgets.dart';

/// Location picker screen per spec section 4.
///
/// Lets the user:
/// 1. Pick a supported **city** (from server or fallback list).
/// 2. Optionally narrow to an **area / neighbourhood** within that city.
/// 3. Use **Current Location** (GPS) to auto-detect the city.
/// 4. Jump to a **saved location** (Home, Work, favourites).
///
/// On "Continue" the selected city + area are persisted through
/// [lastSelectedCityProvider] / [lastSelectedAreaProvider] and handed back to
/// the caller via [onLocationConfirmed].
class LocationScreen extends ConsumerStatefulWidget {
  /// Called when the user taps "Continue" with the resolved city and area.
  final void Function(String city, String area) onLocationConfirmed;

  const LocationScreen({super.key, required this.onLocationConfirmed});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  final _searchController = TextEditingController();
  final _geocoder = Geocoding();
  String _searchQuery = '';
  bool _locating = false;

  /// The city the user has highlighted (not yet committed).
  late String _selectedCity;

  /// The area/neighbourhood within [_selectedCity]. Empty == "All areas".
  String _selectedArea = '';

  @override
  void initState() {
    super.initState();
    _selectedCity = ref.read(lastSelectedCityProvider);
    _selectedArea = ref.read(lastSelectedAreaProvider);
    if (_selectedCity.isEmpty) {
      _selectedCity = ref.read(currentUserProvider)?.location ?? 'Karachi';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── GPS detection ──────────────────────────────────────────────────────────

  Future<void> _useMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) _snack('Please turn on Location Services first.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) _snack('Permission denied — pick a city below.');
        return;
      }

      final Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } on Object {
        if (mounted) _snack('Could not get a fix — try again outdoors.');
        return;
      }

      ref.invalidate(locationPermissionProvider);
      ref.invalidate(livePositionProvider);

      String city = '';
      try {
        final placemarks = await _geocoder.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        for (final p in placemarks) {
          final c = p.locality ?? p.subAdministrativeArea;
          if (c != null && c.trim().isNotEmpty) {
            city = c.trim();
            break;
          }
        }
      } on Object {
        city = '';
      }

      if (!mounted) return;
      if (city.isEmpty) {
        _snack("Couldn't determine your city — pick one below.");
        return;
      }
      setState(() {
        _selectedCity = city;
        _selectedArea = '';
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.info),
    );
  }

  // ── Search filtering ───────────────────────────────────────────────────────

  List<ServiceCity> get _filteredCities {
    final all = ref.read(supportedCitiesProvider).valueOrNull ?? const [];
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.areas.any((a) => a.toLowerCase().contains(q)),
        )
        .toList();
  }

  // ── Commit ─────────────────────────────────────────────────────────────────

  void _confirm() {
    ref.read(lastSelectedCityProvider.notifier).setCity(_selectedCity);
    if (_selectedArea.isNotEmpty) {
      ref.read(lastSelectedAreaProvider.notifier).setArea(_selectedArea);
    } else {
      ref.read(lastSelectedAreaProvider.notifier).clear();
    }
    widget.onLocationConfirmed(_selectedCity, _selectedArea);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final savedLocations = ref.watch(savedLocationsProvider);
    final homeLoc = _ofKind(savedLocations, SavedLocationKind.home);
    final workLoc = _ofKind(savedLocations, SavedLocationKind.work);
    final areas = ref.watch(areasForCityProvider(_selectedCity));
    final filteredCities = _filteredCities;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paddingScreen,
                AppSpacing.md,
                AppSpacing.paddingScreen,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Choose Your Location',
                      style: AppTextStyles.headlineLarge,
                    ),
                  ),
                ],
              ),
            ),
            // ── Scrollable body ─────────────────────────────────────────────
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Subtitle
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.paddingScreen,
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'Discover the best dining experiences around you.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ),

                  // ── Quick-action row: Choose City + Current Location ──────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.paddingScreen,
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _QuickActionTile(
                              icon: Icons.location_city_rounded,
                              label: 'Choose City',
                              onTap: () {},
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _QuickActionTile(
                              icon: Icons.my_location_rounded,
                              label: _locating
                                  ? 'Detecting…'
                                  : 'Current Location',
                              isLoading: _locating,
                              onTap: _useMyLocation,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── City + Area picker card ────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.paddingScreen,
                      ),
                      child: _CityAreaCard(
                        selectedCity: _selectedCity,
                        selectedArea: _selectedArea,
                        areas: areas,
                        onCityTap: (city) {
                          setState(() {
                            _selectedCity = city;
                            _selectedArea = '';
                          });
                        },
                        onAreaTap: (area) {
                          setState(() => _selectedArea = area);
                        },
                      ),
                    ),
                  ),

                  // ── Saved locations ────────────────────────────────────────
                  if (homeLoc != null || workLoc != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.paddingScreen,
                          AppSpacing.xl,
                          AppSpacing.paddingScreen,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          'Saved Locations',
                          style: AppTextStyles.titleMedium,
                        ),
                      ),
                    ),
                  if (homeLoc != null)
                    SliverToBoxAdapter(
                      child: _SavedLocationTile(
                        location: homeLoc,
                        icon: Icons.home_rounded,
                        onTap: () {
                          setState(() {
                            _selectedCity = homeLoc.city;
                            _selectedArea = homeLoc.area;
                          });
                        },
                      ),
                    ),
                  if (workLoc != null)
                    SliverToBoxAdapter(
                      child: _SavedLocationTile(
                        location: workLoc,
                        icon: Icons.work_rounded,
                        onTap: () {
                          setState(() {
                            _selectedCity = workLoc.city;
                            _selectedArea = workLoc.area;
                          });
                        },
                      ),
                    ),

                  // ── Search bar ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.paddingScreen,
                        AppSpacing.xl,
                        AppSpacing.paddingScreen,
                        AppSpacing.sm,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search_rounded,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: const InputDecoration(
                                  hintText: 'Search city or area…',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                                style: AppTextStyles.bodyMedium,
                                onChanged: (v) {
                                  setState(() => _searchQuery = v);
                                },
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                color: AppColors.textSecondary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── City list ──────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.paddingScreen,
                        AppSpacing.md,
                        AppSpacing.paddingScreen,
                        AppSpacing.sm,
                      ),
                      child: Text(
                        'Supported Cities',
                        style: AppTextStyles.titleMedium,
                      ),
                    ),
                  ),
                  if (filteredCities.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Center(
                          child: Text(
                            'No cities found',
                            style: AppTextStyles.bodySmall,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final city = filteredCities[index];
                        final isSelected = city.name == _selectedCity;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.paddingScreen,
                            vertical: AppSpacing.xs,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedCity = city.name;
                                _selectedArea = '';
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMd,
                                ),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_city_rounded,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          city.name,
                                          style: AppTextStyles.titleMedium
                                              .copyWith(
                                                color: isSelected
                                                    ? AppColors.primary
                                                    : AppColors.textPrimary,
                                              ),
                                        ),
                                        if (city.areas.isNotEmpty) ...[
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            '${city.areas.length} areas available',
                                            style: AppTextStyles.caption,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }, childCount: filteredCities.length),
                    ),

                  // Bottom spacer
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.xxl),
                  ),
                ],
              ),
            ),

            // ── Continue button ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.paddingScreen,
                AppSpacing.sm,
                AppSpacing.paddingScreen,
                AppSpacing.md,
              ),
              child: PrimaryButton(
                text: 'Continue with Location',
                onPressed: _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }

  SavedLocation? _ofKind(List<SavedLocation> list, SavedLocationKind kind) {
    for (final loc in list) {
      if (loc.kind == kind) return loc;
    }
    return null;
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

/// Quick-action tile at the top of the picker ("Choose City" / "Current
/// Location"). Uses a fixed-height container so both tiles in the row match.
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card showing the selected city and an area picker (chip row).
class _CityAreaCard extends StatelessWidget {
  final String selectedCity;
  final String selectedArea;
  final List<String> areas;
  final ValueChanged<String> onCityTap;
  final ValueChanged<String> onAreaTap;

  const _CityAreaCard({
    required this.selectedCity,
    required this.selectedArea,
    required this.areas,
    required this.onCityTap,
    required this.onAreaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // City row
          Row(
            children: [
              const Icon(
                Icons.location_city_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('City', style: AppTextStyles.caption),
                    const SizedBox(height: 2),
                    Text(selectedCity, style: AppTextStyles.titleMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Area row
          Row(
            children: [
              const Icon(
                Icons.map_outlined,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Area / Neighbourhood', style: AppTextStyles.caption),
                    const SizedBox(height: 2),
                    Text(
                      selectedArea.isEmpty ? 'All areas' : selectedArea,
                      style: AppTextStyles.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Area chips (only when the city has areas)
          if (areas.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                TagChip(
                  label: 'All areas',
                  isSelected: selectedArea.isEmpty,
                  onTap: () => onAreaTap(''),
                ),
                for (final area in areas)
                  TagChip(
                    label: area,
                    isSelected: selectedArea == area,
                    onTap: () => onAreaTap(area),
                  ),
              ],
            ),
          ],

          // Tagline
          const SizedBox(height: AppSpacing.md),
          Text(
            '$selectedCity — Explore across the city',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A saved-location tile (Home / Work) that jumps to that city+area on tap.
class _SavedLocationTile extends StatelessWidget {
  final SavedLocation location;
  final IconData icon;
  final VoidCallback onTap;

  const _SavedLocationTile({
    required this.location,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.paddingScreen,
        vertical: AppSpacing.xs,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(location.name, style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      location.subtitle,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
