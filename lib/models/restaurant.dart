/// Restaurant model
class Restaurant {
  final String id;
  final String name;
  final String description;
  final String cuisine;
  final String address;

  /// Area/street the venue sits in (`Do Darya`, `Clifton`); empty when the
  /// partner never filled it in.
  final String neighborhood;
  final String? city;

  /// Real venue coordinates when the API supplies them; null keeps the
  /// venue off the map instead of pinning it to the Gulf of Guinea (0,0).
  final double? latitude;
  final double? longitude;
  final String? imagePath;
  
  /// Gallery images for the restaurant (multiple photos)
  final List<String> gallery;
  
  /// Restaurant logo (separate from cover image)
  final String? logoPath;
  
  /// Contact information
  final String? phoneNumber;
  final String? website;
  final String? email;
  
  /// Social media links
  final String? instagram;
  final String? facebook;
  final String? twitter;
  
  final double rating;
  final int reviewCount;
  final String priceRange;
  final List<String> tags;
  final bool isPartner;
  final String partnershipStatus;
  final bool isFollowing;

  /// Great-circle km from the viewer's live GPS fix (`/restaurants/nearby`
  /// only); null on city/search feeds.
  final double? distanceKm;

  /// Opening hours keyed by day abbreviation (Mon, Tue, … Sun).
  final Map<String, dynamic> openingHours;

  /// Venue facilities (WiFi, parking, outdoor seating, …).
  final List<String> amenities;

  const Restaurant({
    required this.id,
    required this.name,
    required this.description,
    required this.cuisine,
    required this.address,
    this.neighborhood = '',
    this.city,
    this.latitude,
    this.longitude,
    this.imagePath,
    this.gallery = const [],
    this.logoPath,
    this.phoneNumber,
    this.website,
    this.email,
    this.instagram,
    this.facebook,
    this.twitter,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.priceRange = '\$\$',
    this.tags = const [],
    this.isPartner = false,
    this.partnershipStatus = '',
    this.isFollowing = false,
    this.distanceKm,
    this.openingHours = const {},
    this.amenities = const [],
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Price tier for display. The API stores tiers as `$` repeats, but DineCircle
  /// prices are rupees, so a dollar glyph would misstate the tier: `$$` renders
  /// as `Rs..` and `$$$` as `Rs...`. Anything unrecognised collapses to `Rs`.
  String get priceRangeLabel {
    final tiers = priceRange.replaceAll(r'$', '').length;
    if (tiers < 1) return 'Rs';
    return 'Rs${'.' * tiers.clamp(1, 4)}';
  }
  
  /// Short location line for heroes and cards: `Do Darya · Karachi`, falling
  /// back to whichever of city/address/cuisine the partner actually filled in.
  String get locationLine {
    final area = neighborhood.trim();
    final town = city?.trim() ?? '';
    if (area.isNotEmpty && town.isNotEmpty && area != town) {
      return '$area · $town';
    }
    if (area.isNotEmpty) return area;
    if (town.isNotEmpty) return town;
    if (address.trim().isNotEmpty) return address.trim();
    return cuisine.trim();
  }

  /// Whether the restaurant has any gallery images
  bool get hasGallery => gallery.isNotEmpty;
  
  /// Whether the restaurant has a logo
  bool get hasLogo => logoPath != null && logoPath!.isNotEmpty;
  
  /// Whether the restaurant has contact information
  bool get hasContact => phoneNumber != null || website != null || email != null;
  
  /// Whether the restaurant has social media links
  bool get hasSocialMedia => instagram != null || facebook != null || twitter != null;
  
  /// Check if restaurant is currently open based on opening hours
  bool isOpenNow() {
    if (openingHours.isEmpty) return false;
    
    final now = DateTime.now();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final currentDay = dayNames[now.weekday - 1]; // weekday is 1-7, Monday is 1
    
    final dayHours = openingHours[currentDay];
    if (dayHours == null || dayHours == 'Closed') return false;
    
    // Parse hours like "9:00 AM - 10:00 PM" or "09:00-22:00"
    try {
      final parts = dayHours.split(' - ');
      if (parts.length != 2) return false;
      
      final openTime = _parseTime(parts[0].trim());
      final closeTime = _parseTime(parts[1].trim());
      
      if (openTime == null || closeTime == null) return false;
      
      final currentMinutes = now.hour * 60 + now.minute;
      final openMinutes = openTime.hour * 60 + openTime.minute;
      final closeMinutes = closeTime.hour * 60 + closeTime.minute;
      
      return currentMinutes >= openMinutes && currentMinutes <= closeMinutes;
    } catch (e) {
      return false;
    }
  }
  
  /// Parse time string like "9:00 AM" or "09:00" into DateTime
  DateTime? _parseTime(String timeStr) {
    try {
      // Handle AM/PM format
      if (timeStr.toUpperCase().contains('AM') || timeStr.toUpperCase().contains('PM')) {
        final parts = timeStr.toUpperCase().split(' ');
        if (parts.length != 2) return null;
        
        final timeParts = parts[0].split(':');
        if (timeParts.length != 2) return null;
        
        var hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        
        if (parts[1] == 'PM' && hour != 12) hour += 12;
        if (parts[1] == 'AM' && hour == 12) hour = 0;
        
        return DateTime(2000, 1, 1, hour, minute);
      } else {
        // Handle 24-hour format
        final timeParts = timeStr.split(':');
        if (timeParts.length != 2) return null;
        
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        
        return DateTime(2000, 1, 1, hour, minute);
      }
    } catch (e) {
      return null;
    }
  }

  /// Returns a copy with the given fields replaced. Used by the location layer
  /// to stamp a client-computed [distanceKm] onto city/search feed results when
  /// a live GPS fix exists but the endpoint did not return a distance.
  Restaurant copyWith({
    double? distanceKm,
    List<String>? gallery,
    String? logoPath,
    String? phoneNumber,
    String? website,
    String? email,
    String? instagram,
    String? facebook,
    String? twitter,
    bool? isFollowing,
  }) => Restaurant(
    id: id,
    name: name,
    description: description,
    cuisine: cuisine,
    address: address,
    city: city,
    latitude: latitude,
    longitude: longitude,
    imagePath: imagePath,
    gallery: gallery ?? this.gallery,
    logoPath: logoPath ?? this.logoPath,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    website: website ?? this.website,
    email: email ?? this.email,
    instagram: instagram ?? this.instagram,
    facebook: facebook ?? this.facebook,
    twitter: twitter ?? this.twitter,
    rating: rating,
    reviewCount: reviewCount,
    priceRange: priceRange,
    tags: tags,
    isPartner: isPartner,
    partnershipStatus: partnershipStatus,
    isFollowing: isFollowing ?? this.isFollowing,
    distanceKm: distanceKm ?? this.distanceKm,
    openingHours: openingHours,
    amenities: amenities,
  );

  /// Create Restaurant from JSON response
  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      cuisine: json['cuisine'] as String? ?? '',
      address: json['address'] as String? ?? '',
      city: json['city'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      imagePath: json['imagePath'] as String? ?? json['coverImage'] as String?,
      gallery: (json['gallery'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      logoPath: json['logoPath'] as String? ?? json['logo'] as String?,
      phoneNumber: json['phoneNumber'] as String? ?? json['phone'] as String?,
      website: json['website'] as String?,
      email: json['email'] as String?,
      instagram: json['instagram'] as String?,
      facebook: json['facebook'] as String?,
      twitter: json['twitter'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: json['reviewCount'] as int? ?? 0,
      priceRange: json['priceRange'] as String? ?? '\$\$',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      isPartner: json['isPartner'] as bool? ?? false,
      partnershipStatus: json['partnershipStatus'] as String? ?? '',
      isFollowing: json['isFollowing'] as bool? ?? false,
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      openingHours: json['openingHours'] as Map<String, dynamic>? ?? const {},
      amenities: (json['amenities'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  /// Convert Restaurant to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'cuisine': cuisine,
      'address': address,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'imagePath': imagePath,
      'gallery': gallery,
      'logoPath': logoPath,
      'phoneNumber': phoneNumber,
      'website': website,
      'email': email,
      'instagram': instagram,
      'facebook': facebook,
      'twitter': twitter,
      'rating': rating,
      'reviewCount': reviewCount,
      'priceRange': priceRange,
      'tags': tags,
      'isPartner': isPartner,
      'partnershipStatus': partnershipStatus,
      'isFollowing': isFollowing,
      'distanceKm': distanceKm,
      'openingHours': openingHours,
      'amenities': amenities,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Restaurant && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
