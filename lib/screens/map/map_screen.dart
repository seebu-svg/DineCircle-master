import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/dinner.dart';
import '../../models/restaurant.dart';
import '../../providers/events_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/restaurants_provider.dart';
import '../../providers/session_provider.dart' show authReadyProvider;
import '../../widgets/avatar_widget.dart';

/// Map discovery screen per spec section 3, on a real Google Map.
///
/// Markers sit at each venue's stored coordinates; the camera follows the
/// live GPS fix when permission is granted (otherwise the venue cluster,
/// otherwise Karachi). Marker taps keep the legacy bottom sheets, and
/// "Directions" deep-links into the Google Maps app / web.
class MapScreen extends ConsumerStatefulWidget {
  final void Function(Dinner dinner)? onDinnerTap;
  final void Function(Restaurant restaurant)? onRestaurantTap;

  const MapScreen({super.key, this.onDinnerTap, this.onRestaurantTap});

  /// Opens Google Maps (app when installed, web otherwise) navigating to the
  /// venue. No API key required — this is the public Maps URL scheme.
  /// [travelMode] is one of `driving`, `transit`, `walking`, `bicycling`.
  static Future<void> openDirections({
    required double lat,
    required double lng,
    String? destinationName,
    String? travelMode,
  }) async {
    final name = Uri.encodeComponent(destinationName ?? '');
    final mode = travelMode == null ? '' : '&travelmode=$travelMode';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng'
      '&destination_name=$name'
      '$mode',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

/// Which marker layers are visible (the filter chip row).
enum _MapLayer { all, dinners, restaurants }

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;
  _MapLayer _layer = _MapLayer.all;
  bool _cameraSettled = false;

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // First layout: place the camera on the best target we already have.
    controller.moveCamera(CameraUpdate.newLatLng(_initialTarget()));
  }

  Position? get _fix => ref.read(livePositionOrNullProvider);

  LatLng _initialTarget() {
    final fix = _fix;
    if (fix != null) return LatLng(fix.latitude, fix.longitude);
    final venues = _visibleVenues();
    if (venues.isNotEmpty) {
      return LatLng(
        venues.map((r) => r.latitude!).reduce((a, b) => a + b) / venues.length,
        venues.map((r) => r.longitude!).reduce((a, b) => a + b) / venues.length,
      );
    }
    return const LatLng(kKarachiCenterLat, kKarachiCenterLng);
  }

  List<Restaurant> _visibleVenues() {
    if (!ref.read(authReadyProvider)) return const [];
    final city = ref.read(userCityProvider);
    final async = ref.read(venuesInCityProvider(city));
    return (async.valueOrNull ?? const <Restaurant>[])
        .where((r) => r.hasCoordinates)
        .toList();
  }

  void _recenter() {
    final fix = _fix;
    final target = fix != null
        ? LatLng(fix.latitude, fix.longitude)
        : _initialTarget();
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(target, fix != null ? 15 : 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(userCityProvider);
    final venuesAsync = ref.watch(venuesInCityProvider(city));
    final dinnersAsync = ref.watch(eventsFeedProvider(EventFilter(city: city)));
    final liveAsync = ref.watch(livePositionProvider);
    final restaurants = venuesAsync.valueOrNull ?? const <Restaurant>[];
    final dinners = dinnersAsync.valueOrNull ?? const <Dinner>[];
    final isLoading =
        venuesAsync is AsyncLoading || dinnersAsync is AsyncLoading;
    final markedRestaurants = restaurants
        .where((r) => r.hasCoordinates)
        .toList();
    final markedDinners = dinners
        .where((d) => d.restaurant.hasCoordinates)
        .toList();
    final isEmpty =
        !isLoading && markedRestaurants.isEmpty && markedDinners.isEmpty;

    // Pan with the user the first time a fix arrives (then hands control back).
    final fix = liveAsync.valueOrNull;
    if (fix != null && !_cameraSettled && _mapController != null) {
      _cameraSettled = true;
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(fix.latitude, fix.longitude), 14),
      );
    }

    final markers = <Marker>{
      if (_layer != _MapLayer.dinners)
        ...markedRestaurants.map(
          (r) => Marker(
            markerId: MarkerId('venue_${r.id}'),
            position: LatLng(r.latitude!, r.longitude!),
            onTap: () => _showRestaurantBottomSheet(context, r),
          ),
        ),
      if (_layer != _MapLayer.restaurants)
        ...markedDinners.map(
          (d) => Marker(
            markerId: MarkerId('dinner_${d.id}'),
            position: LatLng(d.restaurant.latitude!, d.restaurant.longitude!),
            icon: d.isSpecialEvent
                ? BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  )
                : BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRose,
                  ),
            onTap: () => _showDinnerBottomSheet(context, d),
          ),
        ),
    };

    return Scaffold(
      body: Stack(
        children: [
          // Real Google Map (key-less debug builds render a grey demo map).
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _initialTarget(),
              zoom: 12,
            ),
            markers: markers,
            myLocationEnabled: fix != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),
          // Search bar overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ],
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
                          decoration: const InputDecoration(
                            hintText: 'Search this area...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.filter_list_rounded),
                        onPressed: () {},
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Filter chips — toggle marker layers.
          Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingScreen,
                ),
                children: [
                  for (final layer in _MapLayer.values) ...[
                    _MapFilterChip(
                      label: switch (layer) {
                        _MapLayer.all => 'All',
                        _MapLayer.dinners => 'Dinners',
                        _MapLayer.restaurants => 'Restaurants',
                      },
                      isSelected: _layer == layer,
                      onTap: () => setState(() => _layer = layer),
                    ),
                    if (layer != _MapLayer.values[_MapLayer.values.length - 1])
                      const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
          // Re-center button — jumps to the live fix (or the venue cluster).
          Positioned(
            bottom: 100,
            right: AppSpacing.paddingScreen,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  ref.watch(livePositionProvider).valueOrNull != null
                      ? Icons.my_location_rounded
                      : Icons.location_searching_rounded,
                  color: AppColors.primary,
                ),
                onPressed: _recenter,
              ),
            ),
          ),
          // Legend
          Positioned(
            bottom: 36,
            left: AppSpacing.paddingScreen,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primary,
                    size: 14,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Restaurants', style: AppTextStyles.caption),
                  const SizedBox(width: AppSpacing.md),
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primaryLight,
                    size: 14,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Dinners', style: AppTextStyles.caption),
                ],
              ),
            ),
          ),
          // City header badge — follows the live fix when available.
          if (city.isNotEmpty)
            Positioned(
              top: 66,
              left: AppSpacing.paddingScreen,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.gps_fixed_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(city, style: AppTextStyles.labelMedium),
                  ],
                ),
              ),
            ),
          if (isEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingScreen,
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_off_rounded,
                      color: AppColors.textSecondary,
                      size: 28,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      city.isEmpty
                          ? 'No dinners or venues near you yet'
                          : 'Nothing to show in $city yet',
                      style: AppTextStyles.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Try changing your location to discover more tables.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (isLoading && restaurants.isEmpty && dinners.isEmpty)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        ],
      ),
    );
  }

  void _showDinnerBottomSheet(BuildContext context, Dinner dinner) {
    final venue = dinner.restaurant;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dinner.title,
                                style: AppTextStyles.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (dinner.isSpecialEvent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusXs,
                                  ),
                                ),
                                child: Text(
                                  'EVENT',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: Colors.black,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          dinner.restaurant.name,
                          style: AppTextStyles.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Text(
                              dinner.formattedDate,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'at ${dinner.formattedTime}',
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
              const SizedBox(height: AppSpacing.md),
              // Details row
              Row(
                children: [
                  _InfoPill(
                    icon: Icons.attach_money_rounded,
                    text: 'Rs ${dinner.pricePerSeat.toStringAsFixed(0)}/seat',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _InfoPill(
                    icon: Icons.event_seat_rounded,
                    text: '${dinner.availableSeats} seats left',
                    color: dinner.availableSeats <= 3
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _InfoPill(
                    icon: Icons.location_on_rounded,
                    text: dinner.restaurant.city ?? dinner.restaurant.name,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Host
              Row(
                children: [
                  AvatarWidget(
                    imagePath: dinner.host.avatarPath,
                    initials: dinner.host.initials,
                    size: AppSpacing.avatarSm,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Hosted by ${dinner.host.name}',
                      style: AppTextStyles.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: venue.hasCoordinates
                          ? () {
                              Navigator.pop(context);
                              MapScreen.openDirections(
                                lat: venue.latitude!,
                                lng: venue.longitude!,
                                destinationName: venue.name,
                              );
                            }
                          : null,
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Directions'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        disabledForegroundColor: AppColors.textTertiary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDinnerTap?.call(dinner);
                      },
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('View Details'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRestaurantBottomSheet(BuildContext context, Restaurant restaurant) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    child: Image.asset(
                      restaurant.imagePath ??
                          'assets/images/venue_interior.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(restaurant.name, style: AppTextStyles.titleMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          restaurant.cuisine,
                          style: AppTextStyles.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: AppColors.gold,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${restaurant.rating}',
                              style: AppTextStyles.labelSmall,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              restaurant.priceRangeLabel,
                              style: AppTextStyles.labelSmall,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Icon(
                              Icons.location_on_rounded,
                              color: AppColors.textTertiary,
                              size: 14,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              restaurant.distanceKm != null
                                  ? distanceLabel(restaurant.distanceKm!)
                                  : (restaurant.city ?? restaurant.name),
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: restaurant.hasCoordinates
                          ? () {
                              Navigator.pop(context);
                              MapScreen.openDirections(
                                lat: restaurant.latitude!,
                                lng: restaurant.longitude!,
                                destinationName: restaurant.name,
                              );
                            }
                          : null,
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Directions'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        disabledForegroundColor: AppColors.textTertiary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onRestaurantTap?.call(restaurant);
                      },
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('View Details'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoPill({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final displayColor = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: displayColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(color: displayColor),
          ),
        ],
      ),
    );
  }
}

class _MapFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MapFilterChip({
    required this.label,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
