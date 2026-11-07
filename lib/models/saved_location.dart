/// A saved location (Home, Work, or a custom favourite area).
///
/// Persisted locally via secure storage and optionally synchronised with the
/// backend (`POST /api/users/me/saved-locations`). Each entry carries a
/// human-readable [label] ("Home", "Work", …), the free-form [name] the user
/// sees in the list, the resolved [city] and optional [area] / neighbourhood,
/// and the GPS [latitude] / [longitude] when the address could be geocoded.
class SavedLocation {
  final String id;
  final SavedLocationKind kind;

  /// Display name: "Home", "Work", "Clifton", …
  final String name;

  /// Resolved city ("Karachi").
  final String city;

  /// Optional neighbourhood or district ("DHA Phase 2").
  final String area;

  /// Free-form address string the user typed or the geocoder returned.
  final String address;

  final double? latitude;
  final double? longitude;

  const SavedLocation({
    required this.id,
    required this.kind,
    required this.name,
    this.city = '',
    this.area = '',
    this.address = '',
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Short subtitle for list tiles: "DHA, Karachi" or just "Karachi".
  String get subtitle {
    final parts = <String>[
      if (area.isNotEmpty) area,
      if (city.isNotEmpty) city,
    ];
    return parts.isEmpty ? address : parts.join(', ');
  }

  SavedLocation copyWith({
    String? id,
    SavedLocationKind? kind,
    String? name,
    String? city,
    String? area,
    String? address,
    double? latitude,
    double? longitude,
  }) => SavedLocation(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    city: city ?? this.city,
    area: area ?? this.area,
    address: address ?? this.address,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.serverValue,
    'name': name,
    'city': city,
    'area': area,
    'address': address,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
  };

  factory SavedLocation.fromJson(Map<String, dynamic> json) => SavedLocation(
    id: json['id'] as String,
    kind: SavedLocationKind.fromServerValue(json['kind'] as String? ?? ''),
    name: json['name'] as String? ?? '',
    city: json['city'] as String? ?? '',
    area: json['area'] as String? ?? '',
    address: json['address'] as String? ?? '',
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedLocation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// The three built-in kinds the UI treats specially (pinned tiles at the top
/// of the location picker) plus [custom] for user-added favourites.
enum SavedLocationKind {
  home('home'),
  work('work'),
  favourite('favourite'),
  custom('custom');

  final String serverValue;
  const SavedLocationKind(this.serverValue);

  static SavedLocationKind fromServerValue(String value) =>
      SavedLocationKind.values.firstWhere(
        (k) => k.serverValue == value,
        orElse: () => SavedLocationKind.custom,
      );
}
