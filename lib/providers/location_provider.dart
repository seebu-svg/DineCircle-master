import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/restaurant.dart';
import 'saved_locations_provider.dart';
import 'users_provider.dart';

/// Live device location (WS-A map + nearby experience).
///
/// The app works entirely off these providers once a GPS fix exists: the map
/// centers on the user, feeds switch to the distance-ordered `/nearby`
/// endpoint, and the city badge follows the user as they move. Every provider
/// degrades gracefully — permission denied or GPS off simply falls back to the
/// profile city that was used before this layer existed.

/// Karachi city centre — the neutral camera target when neither a GPS fix nor
/// venue coordinates exist yet.
const kKarachiCenterLat = 24.81;
const kKarachiCenterLng = 67.03;

const _highAccuracy = LocationSettings(
  accuracy: LocationAccuracy.high,
  timeLimit: Duration(seconds: 15),
);

final _geocoder = Geocoding();

/// Whether location services are enabled on the device.
final locationServiceEnabledProvider = FutureProvider<bool>(
  (ref) => Geolocator.isLocationServiceEnabled(),
);

/// Coarse permission state, requested on demand (a user tap, never silently
/// at startup). Emits `true` only when the OS granted while-in-use access.
final locationPermissionProvider = FutureProvider<bool>((ref) async {
  final servicesOn = await ref.watch(locationServiceEnabledProvider.future);
  if (!servicesOn) return false;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;
});

/// Continuous GPS fixes (50 m movement filter). Kept alive while watched, so
/// the map dot and distance labels update in real time as the user moves.
/// Errors (denied permission, no fix in time) surface via [AsyncValue.error]
/// and are treated as "no location" by every consumer.
final livePositionProvider = StreamProvider<Position>((ref) async* {
  final granted = await ref.watch(locationPermissionProvider.future);
  if (!granted) {
    throw const LocationServiceDisabledException();
  }
  yield await Geolocator.getCurrentPosition(locationSettings: _highAccuracy);
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    ),
  );
});

/// The GPS fix the UI should act on, or null (permission denied / no fix yet).
/// Screens treat null exactly like the pre-location experience.
final livePositionOrNullProvider = Provider<Position?>((ref) {
  return ref.watch(livePositionProvider).valueOrNull;
});

/// City derived from the live fix via reverse geocoding. Falls back to the
/// signed-in profile city when location is unavailable or the placemark
/// carries no locality name.
final userCityProvider = Provider<String>((ref) {
  // Preference order: live GPS city → last-selected city → profile city.
  final profileCity = ref.watch(currentUserProvider)?.location ?? '';
  final lastCity = ref.watch(lastSelectedCityProvider);
  final position = ref.watch(livePositionOrNullProvider);
  if (position == null) {
    return lastCity.isNotEmpty ? lastCity : profileCity;
  }
  final liveCity = ref.watch(liveCityProvider).valueOrNull;
  if (liveCity != null && liveCity.isNotEmpty) return liveCity;
  return lastCity.isNotEmpty ? lastCity : profileCity;
});

/// The user's selected area/neighbourhood within their city. Empty string
/// means "all areas" — feeds that accept an area filter treat it as no filter.
final userAreaProvider = Provider<String>((ref) {
  return ref.watch(lastSelectedAreaProvider);
});

/// Reverse-geocodes the current fix. Reloaded whenever the position changes;
/// never throws — a failed lookup just means "keep the profile city".
final liveCityProvider = FutureProvider.autoDispose<String?>((ref) async {
  final position = ref.watch(livePositionProvider).valueOrNull;
  if (position == null) return null;
  try {
    final placemarks = await _geocoder.placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    for (final placemark in placemarks) {
      final city = placemark.locality ?? placemark.subAdministrativeArea;
      if (city != null && city.trim().isNotEmpty) return city.trim();
    }
  } on Object {
    return null;
  }
  return null;
});

/// Haversine distance in km — used for "1.2 km away" labels when the feed is
/// city-scoped (no server-computed distance available).
double distanceKmBetween({
  required double fromLat,
  required double fromLng,
  required double toLat,
  required double toLng,
}) {
  const earthRadiusKm = 6371.0;
  final dLat = (toLat - fromLat) * math.pi / 180;
  final dLng = (toLng - fromLng) * math.pi / 180;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(fromLat * math.pi / 180) *
          math.cos(toLat * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadiusKm * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Formats a km distance for cards: "450 m away" / "1.2 km away".
String distanceLabel(double km) {
  if (km < 1) return '${(km * 1000).round()} m away';
  if (km < 10) return '${km.toStringAsFixed(1)} km away';
  return '${km.round()} km away';
}

/// Stamps a client-computed [Restaurant.distanceKm] onto each venue and orders
/// them nearest-first when a live [fix] exists. Venues without coordinates are
/// left unranked (pushed to the end). When [fix] is null the list is returned
/// untouched, so city/search feeds behave exactly as before the location layer.
List<Restaurant> rankByDistance(List<Restaurant> venues, Position? fix) {
  if (fix == null) return venues;
  final decorated =
      venues
          .map(
            (r) => r.hasCoordinates
                ? r.copyWith(
                    distanceKm: distanceKmBetween(
                      fromLat: fix.latitude,
                      fromLng: fix.longitude,
                      toLat: r.latitude!,
                      toLng: r.longitude!,
                    ),
                  )
                : r,
          )
          .toList()
        ..sort((a, b) {
          final ad = a.distanceKm;
          final bd = b.distanceKm;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });
  return decorated;
}
