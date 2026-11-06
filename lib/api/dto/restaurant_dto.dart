import '../json.dart';

/// Restaurant / venue payload from `/restaurants`, `/restaurants/:id` and the
/// `venue` object nested in an event detail response. All fields are optional
/// except id/name so partial payloads (e.g. event venue) parse cleanly.
class RestaurantDto {
  const RestaurantDto({
    required this.id,
    required this.name,
    this.cuisines = const [],
    this.neighborhood = '',
    this.address = '',
    this.city = '',
    this.rating = 0,
    this.reviewCount = 0,
    this.priceRange = '\$\$',
    this.coverImage,
    this.gallery = const [],
    this.about = '',
    this.tags = const [],
    this.isPartner = false,
    this.partnerPerk,
    this.openingHours = const {},
    this.seats = 0,
    this.partnershipStatus = '',
    this.isFollowing = false,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.amenities = const [],
    this.phoneNumber,
    this.website,
    this.email,
    this.instagram,
    this.facebook,
    this.twitter,
    this.logoPath,
  });

  final String id;
  final String name;
  final List<String> cuisines;
  final String neighborhood;
  final String address;
  final String city;
  final double rating;
  final int reviewCount;
  final String priceRange;
  final String? coverImage;
  final List<String> gallery;
  final String about;
  final List<String> tags;
  final bool isPartner;
  final String? partnerPerk;
  final Map<String, dynamic> openingHours;
  final int seats;
  final String partnershipStatus;
  final bool isFollowing;
  final double? latitude;
  final double? longitude;

  /// Only present on `/restaurants/nearby` payloads.
  final double? distanceKm;

  /// Venue facilities (WiFi, parking, terrace, …).
  final List<String> amenities;

  /// Contact fields the server surfaces on the venue payload. All optional —
  /// partners may publish only a subset (e.g. just a phone number).
  final String? phoneNumber;
  final String? website;
  final String? email;
  final String? instagram;
  final String? facebook;
  final String? twitter;
  final String? logoPath;

  static RestaurantDto fromJson(Map<String, dynamic> json) => RestaurantDto(
    id: asString(json['id']),
    name: asString(json['name']),
    cuisines: asStringList(json['cuisines']),
    neighborhood: asString(json['neighborhood']),
    address: asString(json['address']),
    city: asString(json['city']),
    rating: asDouble(json['rating']),
    reviewCount: asInt(json['reviewCount']),
    priceRange: asString(json['priceRange'], '\$\$'),
    coverImage: asStringOrNull(json['coverImage']),
    gallery: asStringList(json['gallery']),
    about: asString(json['about']),
    tags: asStringList(json['tags']),
    isPartner: asBool(json['isPartner']),
    partnerPerk: asStringOrNull(json['partnerPerk']),
    openingHours: asMap(json['openingHours']),
    seats: asInt(json['seats']),
    partnershipStatus: asString(json['partnershipStatus']),
    isFollowing: asBool(json['isFollowing']),
    latitude: asDoubleOrNull(json['latitude']),
    longitude: asDoubleOrNull(json['longitude']),
    distanceKm: asDoubleOrNull(json['distanceKm']),
    amenities: asStringList(json['amenities']),
    phoneNumber: asStringOrNull(json['phoneNumber']) ?? asStringOrNull(json['phone']),
    website: asStringOrNull(json['website']),
    email: asStringOrNull(json['email']),
    instagram: asStringOrNull(json['instagram']),
    facebook: asStringOrNull(json['facebook']),
    twitter: asStringOrNull(json['twitter']),
    logoPath: asStringOrNull(json['logoPath']) ?? asStringOrNull(json['logo']),
  );
}

/// A lightweight upcoming-event entry returned inside `/restaurants/:id`.
class VenueEventDto {
  const VenueEventDto({
    required this.id,
    required this.title,
    this.tagline = '',
    this.startAt,
    this.seatsTotal = 0,
    this.seatsBooked = 0,
    this.pricePerSeat = 0,
    this.type = 'dinner',
    this.coverImage,
    this.hostName,
  });

  final String id;
  final String title;
  final String tagline;
  final DateTime? startAt;
  final int seatsTotal;
  final int seatsBooked;
  final double pricePerSeat;
  final String type;
  final String? coverImage;
  final String? hostName;

  static VenueEventDto fromJson(Map<String, dynamic> json) => VenueEventDto(
    id: asString(json['id']),
    title: asString(json['title']),
    tagline: asString(json['tagline']),
    startAt: asDateOrNull(json['startAt']),
    seatsTotal: asInt(json['seatsTotal']),
    seatsBooked: asInt(json['seatsBooked']),
    pricePerSeat: asDouble(json['pricePerSeat']),
    type: asString(json['type'], 'dinner'),
    coverImage: asStringOrNull(json['coverImage']),
    hostName: asStringOrNull(json['hostName']),
  );
}

/// Parsed `/restaurants/:id` envelope: venue + its upcoming events.
class RestaurantDetailDto {
  const RestaurantDetailDto({required this.restaurant, this.events = const []});

  final RestaurantDto restaurant;
  final List<VenueEventDto> events;

  static RestaurantDetailDto fromJson(Map<String, dynamic> json) =>
      RestaurantDetailDto(
        restaurant: RestaurantDto.fromJson(asMap(json['restaurant'])),
        events: asMapList(json['upcomingEvents'])
            .map(VenueEventDto.fromJson)
            .toList(),
      );
}
