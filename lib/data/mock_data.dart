import '../models/user_profile.dart';
import '../models/restaurant.dart';
import '../models/dinner.dart';
import '../models/booking.dart';
import '../models/message.dart';
import '../models/partner_offer.dart';
import '../models/notification_item.dart';
import '../models/review.dart';
import '../models/host_models.dart';

/// Mock data for the DineCircle app
class MockData {
  MockData._();

  // Single-source masked fixture strings (reused across booking / payment / host UIs).
  /// Demo-only card label. Real bookings never use this, the gateway's
  /// webhook writes the true brand/last4 once a charge settles.
  static const String cardMasked = 'Visa •••• 4242';
  static const String cardLast4 = '4242';
  static const String mastercardMasked = 'Mastercard •••• 8819';
  static const String amexMasked = 'Amex •••• 0005';
  static const String bankMasked = 'Bank •••• 7890';
  static String get currentUserName => currentUser.name;

  // Current user
  static const currentUser = UserProfile(
    id: 'user_current',
    name: 'Alex Morgan',
    bio: 'Food influencer & content creator. Sharing exclusive dining experiences with my community. 12K+ followers across platforms.',
    avatarPath: 'assets/images/portrait_1.png',
    dinnersHosted: 12,
    dinnersAttended: 47,
    followers: 2847,
    following: 189,
    rating: 4.8,
    reviewCount: 38,
    isVerified: true,
    isInfluencer: true,
    interests: ['Italian', 'Japanese', 'Wine', 'Craft Cocktails'],
    location: 'San Francisco, CA',
    socialLinks: [
      SocialLink(
        platform: SocialPlatform.instagram,
        handle: '@alexmorgan.eats',
      ),
      SocialLink(platform: SocialPlatform.tiktok, handle: '@alexmorgan'),
      SocialLink(platform: SocialPlatform.youtube, handle: 'Alex Morgan Eats'),
    ],
  );

  // Users
  static const users = [
    UserProfile(
      id: 'user_1',
      name: 'Sofia Chen',
      bio: 'Food writer and culinary explorer. Sharing stories one plate at a time.',
      avatarPath: 'assets/images/portrait_2.png',
      dinnersHosted: 28,
      dinnersAttended: 156,
      followers: 2847,
      following: 423,
      rating: 4.9,
      reviewCount: 89,
      isVerified: true,
      isInfluencer: true,
      interests: ['Asian Fusion', 'Wine', 'Farm-to-Table'],
      location: 'San Francisco, CA',
      socialLinks: [
        SocialLink(
          platform: SocialPlatform.instagram,
          handle: '@sofiachen.food',
        ),
      ],
    ),
    UserProfile(
      id: 'user_2',
      name: 'Marcus Rivera',
      bio: 'Chef and restaurateur. Passionate about bringing people together through food.',
      avatarPath: 'assets/images/portrait_3.png',
      dinnersHosted: 45,
      dinnersAttended: 89,
      followers: 5621,
      following: 234,
      rating: 4.9,
      reviewCount: 156,
      isVerified: true,
      isInfluencer: true,
      interests: ['Mediterranean', 'Italian', 'Wine Pairing'],
      location: 'Oakland, CA',
      socialLinks: [
        SocialLink(
          platform: SocialPlatform.instagram,
          handle: '@chefmarcusriv',
        ),
        SocialLink(
          platform: SocialPlatform.youtube,
          handle: 'Chef Marcus Rivera',
        ),
      ],
    ),
    UserProfile(
      id: 'user_3',
      name: 'Emma Thompson',
      bio: 'Sommelier and wine educator. Exploring the intersection of food and wine.',
      avatarPath: 'assets/images/portrait_4.png',
      dinnersHosted: 18,
      dinnersAttended: 234,
      followers: 1893,
      following: 567,
      rating: 4.8,
      reviewCount: 67,
      isVerified: true,
      isInfluencer: true,
      interests: ['Wine', 'French', 'Cheese'],
      location: 'Napa Valley, CA',
      socialLinks: [
        SocialLink(platform: SocialPlatform.instagram, handle: '@emmathesomm'),
        SocialLink(platform: SocialPlatform.website, handle: 'emmawine.com'),
      ],
    ),
    UserProfile(
      id: 'user_4',
      name: 'James Park',
      bio:
          'Food photographer and content creator. Capturing culinary artistry.',
      avatarPath: 'assets/images/portrait_5.png',
      dinnersHosted: 8,
      dinnersAttended: 167,
      followers: 3456,
      following: 789,
      rating: 4.7,
      reviewCount: 45,
      isVerified: true,
      isInfluencer: true,
      interests: ['Japanese', 'Korean', 'Photography'],
      location: 'Los Angeles, CA',
      socialLinks: [
        SocialLink(
          platform: SocialPlatform.instagram,
          handle: '@jamespark.shoots',
        ),
        SocialLink(platform: SocialPlatform.tiktok, handle: '@jamespfeat'),
      ],
    ),
    UserProfile(
      id: 'user_5',
      name: 'Olivia Martinez',
      bio: 'Pastry chef and dessert enthusiast. Life is short, eat dessert first.',
      avatarPath: 'assets/images/portrait_6.png',
      dinnersHosted: 15,
      dinnersAttended: 98,
      followers: 1234,
      following: 345,
      rating: 4.8,
      reviewCount: 34,
      isVerified: false,
      isInfluencer: true,
      interests: ['Desserts', 'French', 'Chocolate'],
      location: 'Berkeley, CA',
      socialLinks: [
        SocialLink(platform: SocialPlatform.instagram, handle: '@oliviabakes'),
      ],
    ),
    UserProfile(
      id: 'user_6',
      name: 'Noah Kim',
      bio: 'Craft cocktail enthusiast and weekend foodie. Always hunting for the next great pour.',
      avatarPath: 'assets/images/portrait_2.png',
      dinnersHosted: 3,
      dinnersAttended: 54,
      followers: 412,
      following: 289,
      rating: 4.6,
      reviewCount: 12,
      isVerified: false,
      isInfluencer: false,
      interests: ['Cocktails', 'Korean', 'Casual'],
      location: 'San Francisco, CA',
    ),
    UserProfile(
      id: 'user_7',
      name: 'Priya Sharma',
      bio: 'Spice seeker and home cook. Exploring the world one dinner at a time.',
      avatarPath: 'assets/images/portrait_4.png',
      dinnersHosted: 5,
      dinnersAttended: 71,
      followers: 268,
      following: 301,
      rating: 4.7,
      reviewCount: 19,
      isVerified: false,
      isInfluencer: false,
      interests: ['Indian', 'Street Food', 'Vegetarian'],
      location: 'San Jose, CA',
    ),
    UserProfile(
      id: 'user_8',
      name: 'Lucas Weber',
      bio: 'Wine collector and slow-food advocate. Good food takes time.',
      avatarPath: 'assets/images/portrait_5.png',
      dinnersHosted: 2,
      dinnersAttended: 38,
      followers: 195,
      following: 174,
      rating: 4.5,
      reviewCount: 8,
      isVerified: false,
      isInfluencer: false,
      interests: ['Wine', 'French', 'Farm-to-Table'],
      location: 'Napa Valley, CA',
    ),
  ];

  // Restaurants
  static const restaurants = [
    Restaurant(
      id: 'rest_1',
      name: 'Nobu San Francisco',
      description: 'World-renowned Japanese-Peruvian fusion cuisine in an elegant setting.',
      cuisine: 'Japanese',
      address: '1735 Montgomery St',
      city: 'San Francisco',
      latitude: 37.8005,
      longitude: -122.4132,
      imagePath: 'assets/images/dish_sushi.png',
      rating: 4.8,
      reviewCount: 1234,
      priceRange: '\$\$\$',
      tags: ['Sushi', 'Omakase', 'Fine Dining'],
      isPartner: true,
    ),
    Restaurant(
      id: 'rest_2',
      name: 'The Italian Place',
      description: 'Authentic Italian cuisine with handmade pasta and wood-fired pizzas.',
      cuisine: 'Italian',
      address: '456 Columbus Ave',
      city: 'San Francisco',
      latitude: 37.8001,
      longitude: -122.4078,
      imagePath: 'assets/images/dish_pasta.png',
      rating: 4.6,
      reviewCount: 892,
      priceRange: '\$\$',
      tags: ['Pasta', 'Pizza', 'Wine Bar'],
      isPartner: true,
    ),
    Restaurant(
      id: 'rest_3',
      name: 'Steakhouse 55',
      description: 'Premium dry-aged steaks and classic American fare.',
      cuisine: 'American',
      address: '789 Market St',
      city: 'San Francisco',
      latitude: 37.7865,
      longitude: -122.4032,
      imagePath: 'assets/images/dish_steak.png',
      rating: 4.7,
      reviewCount: 567,
      priceRange: '\$\$\$',
      tags: ['Steak', 'Grill', 'Cocktails'],
      isPartner: true,
    ),
    Restaurant(
      id: 'rest_4',
      name: 'Taco Libre',
      description:
          'Elevated street tacos and craft cocktails in a vibrant atmosphere.',
      cuisine: 'Mexican',
      address: '234 Mission St',
      city: 'San Francisco',
      latitude: 37.7892,
      longitude: -122.3962,
      imagePath: 'assets/images/dish_tacos.png',
      rating: 4.5,
      reviewCount: 445,
      priceRange: '\$\$',
      tags: ['Tacos', 'Mezcal', 'Casual'],
      isPartner: false,
    ),
    Restaurant(
      id: 'rest_5',
      name: 'Le Petit Bistro',
      description: 'Classic French bistro with seasonal menus and an extensive wine list.',
      cuisine: 'French',
      address: '567 Union St',
      city: 'San Francisco',
      latitude: 37.8012,
      longitude: -122.4102,
      imagePath: 'assets/images/venue_interior.png',
      rating: 4.8,
      reviewCount: 678,
      priceRange: '\$\$\$',
      tags: ['French', 'Wine', 'Romantic'],
      isPartner: true,
    ),
    Restaurant(
      id: 'rest_6',
      name: 'The Rooftop',
      description: 'Contemporary American cuisine with panoramic city views.',
      cuisine: 'American',
      address: '890 Geary St',
      city: 'San Francisco',
      latitude: 37.7862,
      longitude: -122.4192,
      imagePath: 'assets/images/venue_rooftop.png',
      rating: 4.6,
      reviewCount: 334,
      priceRange: '\$\$\$',
      tags: ['Rooftop', 'Views', 'Cocktails'],
      isPartner: true,
    ),
  ];

  // Dinners
  static List<Dinner> get dinners => [
    Dinner(
      id: 'dinner_1',
      title: 'Omakase Experience',
      description: 'Join us for an intimate 12-course omakase experience featuring the freshest seasonal ingredients flown in daily from Japan.',
      restaurant: restaurants[0],
      host: users[0],
      dateTime: DateTime.now().add(const Duration(days: 2, hours: 19)),
      totalSeats: 8,
      bookedSeats: 5,
      pricePerSeat: 185.0,
      imagePath: 'assets/images/dish_sushi.png',
      menu: [
        const MenuItem(
          id: 'menu_1',
          name: 'Tuna Tartare',
          description: 'Bluefin tuna, avocado, yuzu, shiso',
          price: 28.0,
        ),
        const MenuItem(
          id: 'menu_2',
          name: 'Wagyu Beef',
          description: 'A5 wagyu, truffle, ponzu',
          price: 45.0,
        ),
        const MenuItem(
          id: 'menu_3',
          name: 'Omakase Course',
          description: 'Chef\'s selection of 12 courses',
          price: 185.0,
        ),
      ],
      tags: ['Japanese', 'Omakase', 'Fine Dining'],
      isPublic: true,
      isSpecialEvent: true,
      dressCode: 'Smart Casual',
      ageRestriction: '21+',
      cancellationPolicy: 'Free cancellation up to 72 hours before',
      category: 'Food Experience',
      attendees: [users[1], users[2], users[3]],
    ),
    Dinner(
      id: 'dinner_2',
      title: 'Pasta Making Workshop',
      description: 'Learn the art of handmade pasta with Chef Marco. Includes wine pairing and a full dinner.',
      restaurant: restaurants[1],
      host: users[1],
      dateTime: DateTime.now().add(const Duration(days: 3, hours: 18)),
      totalSeats: 12,
      bookedSeats: 8,
      pricePerSeat: 95.0,
      imagePath: 'assets/images/dish_pasta.png',
      menu: [
        const MenuItem(
          id: 'menu_4',
          name: 'Fresh Pasta Making',
          description: 'Learn to make 3 types of pasta',
          price: 95.0,
        ),
      ],
      tags: ['Italian', 'Cooking Class', 'Wine Pairing'],
      isPublic: true,
      cancellationPolicy: 'Free cancellation up to 48 hours before',
      category: 'Food Experience',
      attendees: [users[0], users[2]],
    ),
    Dinner(
      id: 'dinner_3',
      title: 'Wine & Steak Night',
      description: 'Premium dry-aged steaks paired with exceptional wines from Napa Valley.',
      restaurant: restaurants[2],
      host: users[2],
      dateTime: DateTime.now().add(const Duration(days: 5, hours: 20)),
      totalSeats: 10,
      bookedSeats: 6,
      pricePerSeat: 145.0,
      imagePath: 'assets/images/dish_steak.png',
      menu: [
        const MenuItem(
          id: 'menu_5',
          name: 'Dry-Aged Ribeye',
          description: '45-day dry-aged, bone marrow butter',
          price: 68.0,
        ),
        const MenuItem(
          id: 'menu_6',
          name: 'Wine Pairing',
          description: '3 glasses of premium Napa wines',
          price: 77.0,
        ),
      ],
      tags: ['American', 'Wine Pairing', 'Steak'],
      isPublic: true,
      ageRestriction: '21+',
      cancellationPolicy: 'Free cancellation up to 48 hours before',
      category: 'Public Dinner',
      attendees: [users[0], users[1]],
    ),
    Dinner(
      id: 'dinner_4',
      title: 'Taco Tuesday Social',
      description: 'Casual evening of elevated tacos and craft cocktails. Meet new people in a relaxed setting.',
      restaurant: restaurants[3],
      host: users[3],
      dateTime: DateTime.now().add(const Duration(days: 1, hours: 19)),
      totalSeats: 16,
      bookedSeats: 12,
      pricePerSeat: 45.0,
      imagePath: 'assets/images/dish_tacos.png',
      menu: [
        const MenuItem(
          id: 'menu_7',
          name: 'Taco Trio',
          description: '3 elevated tacos with craft mezcal',
          price: 45.0,
        ),
      ],
      tags: ['Mexican', 'Social', 'Casual'],
      isPublic: true,
      cancellationPolicy: 'Free cancellation up to 24 hours before',
      category: 'Public Dinner',
      attendees: [users[0], users[1], users[2], users[4]],
    ),
    Dinner(
      id: 'dinner_5',
      title: 'French Bistro Evening',
      description: 'Classic French cuisine in an intimate bistro setting. Perfect for food lovers seeking authentic flavors.',
      restaurant: restaurants[4],
      host: users[0],
      dateTime: DateTime.now().add(
        const Duration(days: 4, hours: 19, minutes: 30),
      ),
      totalSeats: 8,
      bookedSeats: 3,
      pricePerSeat: 125.0,
      imagePath: 'assets/images/venue_interior.png',
      menu: [
        const MenuItem(
          id: 'menu_8',
          name: 'French Onion Soup',
          description: 'Classic preparation with gruyere crouton',
          price: 18.0,
        ),
        const MenuItem(
          id: 'menu_9',
          name: 'Duck Confit',
          description: 'With roasted potatoes and seasonal vegetables',
          price: 42.0,
        ),
        const MenuItem(
          id: 'menu_10',
          name: 'Crème Brûlée',
          description: 'Vanilla bean, caramelized sugar',
          price: 14.0,
        ),
      ],
      tags: ['French', 'Romantic', 'Wine'],
      isPublic: true,
      ageRestriction: '18+',
      cancellationPolicy: 'Free cancellation up to 48 hours before',
      category: 'Special Menu',
      attendees: [users[1]],
    ),
    Dinner(
      id: 'dinner_6',
      title: 'Rooftop Sunset Dinner',
      description: 'Contemporary American cuisine with panoramic city views. Watch the sunset while enjoying exceptional food and wine.',
      restaurant: restaurants[5],
      host: users[1],
      dateTime: DateTime.now().add(const Duration(days: 6, hours: 18)),
      totalSeats: 20,
      bookedSeats: 14,
      pricePerSeat: 165.0,
      imagePath: 'assets/images/venue_rooftop.png',
      menu: [
        const MenuItem(
          id: 'menu_11',
          name: 'Sunset Cocktail',
          description: 'Signature cocktail with panoramic views',
          price: 22.0,
        ),
        const MenuItem(
          id: 'menu_12',
          name: 'Chef\'s Tasting Menu',
          description: '5-course seasonal tasting menu',
          price: 143.0,
        ),
      ],
      tags: ['American', 'Rooftop', 'Views'],
      isPublic: true,
      isSpecialEvent: true,
      dressCode: 'Smart Casual',
      cancellationPolicy: 'Free cancellation up to 72 hours before',
      category: 'Influencer Event',
      attendees: [users[0], users[2], users[3], users[4]],
    ),
    Dinner(
      id: 'dinner_7',
      title: 'Brunch Social',
      description: 'Weekend brunch with artisanal coffee, fresh pastries, and great conversation.',
      restaurant: restaurants[1],
      host: users[4],
      dateTime: DateTime.now().add(const Duration(days: 7, hours: 11)),
      totalSeats: 12,
      bookedSeats: 7,
      pricePerSeat: 55.0,
      imagePath: 'assets/images/dish_brunch.png',
      menu: [
        const MenuItem(
          id: 'menu_13',
          name: 'Brunch Platter',
          description: 'Avocado toast, poached eggs, fresh berries, croissant',
          price: 55.0,
        ),
      ],
      tags: ['Brunch', 'Social', 'Casual'],
      isPublic: true,
      cancellationPolicy: 'Free cancellation up to 24 hours before',
      category: 'Group Dining',
      attendees: [users[0], users[1]],
    ),
    Dinner(
      id: 'dinner_8',
      title: 'Dessert & Wine Pairing',
      description: 'Indulge in exquisite desserts paired with exceptional wines. A sweet evening for dessert lovers.',
      restaurant: restaurants[4],
      host: users[4],
      dateTime: DateTime.now().add(const Duration(days: 8, hours: 20)),
      totalSeats: 10,
      bookedSeats: 4,
      pricePerSeat: 85.0,
      imagePath: 'assets/images/dish_dessert.png',
      menu: [
        const MenuItem(
          id: 'menu_14',
          name: 'Chocolate Sphere',
          description: 'Dark chocolate, raspberry coulis, gold leaf',
          price: 28.0,
        ),
        const MenuItem(
          id: 'menu_15',
          name: 'Wine Pairing',
          description: '3 dessert wines',
          price: 57.0,
        ),
      ],
      tags: ['Desserts', 'Wine Pairing', 'Sweet'],
      isPublic: true,
      ageRestriction: '18+',
      cancellationPolicy: 'Free cancellation up to 48 hours before',
      category: 'Tasting',
      attendees: [users[0]],
    ),
  ];

  // Bookings
  static List<Booking> get bookings => [
    Booking(
      id: 'booking_1',
      dinner: dinners[0],
      user: currentUser,
      seats: 2,
      subtotal: 370.0,
      serviceFee: 37.0,
      discount: 0,
      totalAmount: 407.0,
      status: BookingStatus.confirmed,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      guestName: 'Alex Morgan',
      guestEmail: 'alex@example.com',
      guestPhone: '+1 (415) 555-0101',
      paymentMethod: cardMasked,
      qrCode: 'DC-PASS-booking_1',
      checkInStatus: CheckInStatus.notCheckedIn,
    ),
    Booking(
      id: 'booking_2',
      dinner: dinners[3],
      user: currentUser,
      seats: 1,
      subtotal: 45.0,
      serviceFee: 4.50,
      discount: 5.0,
      totalAmount: 44.50,
      status: BookingStatus.confirmed,
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      promoCode: 'FOODIE5',
      guestName: 'Alex Morgan',
      paymentMethod: 'Apple Pay',
      qrCode: 'DC-PASS-booking_2',
      checkInStatus: CheckInStatus.notCheckedIn,
    ),
    Booking(
      id: 'booking_3',
      dinner: dinners[4],
      user: currentUser,
      seats: 2,
      subtotal: 250.0,
      serviceFee: 25.0,
      discount: 0,
      totalAmount: 275.0,
      status: BookingStatus.pending,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      guestName: 'Alex Morgan',
      guestEmail: 'alex@example.com',
      paymentMethod: 'Google Pay',
      qrCode: 'DC-PASS-booking_3',
      checkInStatus: CheckInStatus.notCheckedIn,
    ),
    Booking(
      id: 'booking_4',
      dinner: dinners[1],
      user: currentUser,
      seats: 1,
      subtotal: 95.0,
      serviceFee: 9.50,
      discount: 0,
      totalAmount: 104.50,
      status: BookingStatus.completed,
      createdAt: DateTime.now().subtract(const Duration(days: 14)),
      guestName: 'Alex Morgan',
      paymentMethod: cardMasked,
      qrCode: 'DC-PASS-booking_4',
      checkInStatus: CheckInStatus.checkedIn,
      checkInTime: DateTime.now()
          .subtract(const Duration(days: 14))
          .add(const Duration(hours: 19, minutes: 45)),
    ),
    Booking(
      id: 'booking_5',
      dinner: dinners[2],
      user: currentUser,
      seats: 1,
      subtotal: 145.0,
      serviceFee: 14.50,
      discount: 0,
      totalAmount: 159.50,
      status: BookingStatus.cancelled,
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
      guestName: 'Alex Morgan',
      paymentMethod: cardMasked,
      qrCode: 'DC-PASS-booking_5',
      checkInStatus: CheckInStatus.expired,
    ),
    Booking(
      id: 'booking_6',
      dinner: dinners[5],
      user: currentUser,
      seats: 2,
      subtotal: 330.0,
      serviceFee: 33.0,
      discount: 0,
      totalAmount: 363.0,
      status: BookingStatus.noShow,
      createdAt: DateTime.now().subtract(const Duration(days: 21)),
      guestName: 'Alex Morgan',
      paymentMethod: 'Apple Pay',
      qrCode: 'DC-PASS-booking_6',
      checkInStatus: CheckInStatus.expired,
    ),
    Booking(
      id: 'booking_7',
      dinner: dinners[6],
      user: currentUser,
      seats: 1,
      subtotal: 55.0,
      serviceFee: 5.50,
      discount: 10.0,
      totalAmount: 50.50,
      status: BookingStatus.refunded,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      promoCode: 'WELCOME10',
      guestName: 'Alex Morgan',
      paymentMethod: 'Google Pay',
      qrCode: 'DC-PASS-booking_7',
      checkInStatus: CheckInStatus.expired,
    ),
  ];

  // Conversations
  static List<ChatConversation> get conversations => [
    ChatConversation(
      id: 'conv_1',
      title: 'Omakase Experience',
      dinner: dinners[0],
      participants: [users[0], users[1], users[2], users[3]],
      lastMessage: Message(
        id: 'msg_1',
        content: 'Looking forward to meeting everyone!',
        sender: users[0],
        timestamp: DateTime.now(),
        isRead: false,
      ),
      unreadCount: 3,
      isGroupChat: true,
    ),
    ChatConversation(
      id: 'conv_2',
      title: 'Sofia Chen',
      participants: [users[0]],
      lastMessage: Message(
        id: 'msg_2',
        content: 'Thanks for hosting such a great dinner!',
        sender: users[0],
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        isRead: true,
      ),
      unreadCount: 0,
      isGroupChat: false,
    ),
    ChatConversation(
      id: 'conv_3',
      title: 'Taco Tuesday Social',
      dinner: dinners[3],
      participants: [users[3], users[0], users[1], users[2], users[4]],
      lastMessage: Message(
        id: 'msg_3',
        content: 'See you all tomorrow!',
        sender: users[3],
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        isRead: false,
      ),
      unreadCount: 5,
      isGroupChat: true,
    ),
    ChatConversation(
      id: 'conv_4',
      title: 'Marcus Rivera',
      participants: [users[1]],
      lastMessage: Message(
        id: 'msg_4',
        content: 'Would love to collaborate on a dinner event.',
        sender: users[1],
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        isRead: true,
      ),
      unreadCount: 0,
      isGroupChat: false,
    ),
  ];

  // Partner offers
  static List<PartnerOffer> get partnerOffers => [
    PartnerOffer(
      id: 'offer_1',
      restaurant: restaurants[0],
      title: '20% Off Omakase',
      description: 'Exclusive discount on our signature omakase experience for DineCircle members.',
      type: OfferType.discount,
      discountPercentage: 20.0,
      validUntil: DateTime.now().add(const Duration(days: 14)),
      maxRedemptions: 50,
      currentRedemptions: 23,
    ),
    PartnerOffer(
      id: 'offer_2',
      restaurant: restaurants[1],
      title: 'Pasta Making Special',
      description: 'Join our pasta making workshop and get a complimentary wine pairing.',
      type: OfferType.specialMenu,
      specialPrice: 95.0,
      validUntil: DateTime.now().add(const Duration(days: 30)),
    ),
    PartnerOffer(
      id: 'offer_3',
      restaurant: restaurants[4],
      title: 'Chef\'s Table Experience',
      description: 'Exclusive 7-course tasting menu with wine pairing at the chef\'s table.',
      type: OfferType.exclusiveExperience,
      specialPrice: 225.0,
      validUntil: DateTime.now().add(const Duration(days: 60)),
      maxRedemptions: 20,
      currentRedemptions: 8,
    ),
    PartnerOffer(
      id: 'offer_4',
      restaurant: restaurants[5],
      title: 'Sunset Dinner Package',
      description:
          '5-course tasting menu with signature cocktail and panoramic views.',
      type: OfferType.specialMenu,
      specialPrice: 165.0,
      validUntil: DateTime.now().add(const Duration(days: 45)),
    ),
  ];

  // Notifications
  static List<NotificationItem> get notifications => [
    NotificationItem(
      id: 'notif_1',
      type: NotificationType.bookingConfirmed,
      title: 'Booking Confirmed',
      message: 'Your booking for Omakase Experience has been confirmed.',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      dinner: dinners[0],
    ),
    NotificationItem(
      id: 'notif_2',
      type: NotificationType.newAttendee,
      title: 'New Attendee',
      message: 'Emma Thompson joined your French Bistro Evening dinner.',
      timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      user: users[4],
      dinner: dinners[4],
    ),
    NotificationItem(
      id: 'notif_3',
      type: NotificationType.hostEarnings,
      title: 'Earnings Update',
      message: 'You earned Rs 285 from your recent dinner.',
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    NotificationItem(
      id: 'notif_4',
      type: NotificationType.message,
      title: 'New Message',
      message: 'Sofia Chen sent you a message.',
      timestamp: DateTime.now().subtract(const Duration(hours: 8)),
      user: users[0],
    ),
    NotificationItem(
      id: 'notif_5',
      type: NotificationType.dinnerReminder,
      title: 'Dinner Tomorrow',
      message: 'Taco Tuesday Social is tomorrow at 7:00 PM.',
      timestamp: DateTime.now().subtract(const Duration(hours: 12)),
      dinner: dinners[3],
    ),
    NotificationItem(
      id: 'notif_6',
      type: NotificationType.followRequest,
      title: 'Follow Request',
      message: 'Marcus Rivera wants to follow you.',
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
      user: users[1],
    ),
    NotificationItem(
      id: 'notif_7',
      type: NotificationType.specialOffer,
      title: 'Special Offer',
      message: '20% off Omakase at Nobu San Francisco!',
      timestamp: DateTime.now().subtract(const Duration(days: 2)),
    ),
    NotificationItem(
      id: 'notif_8',
      type: NotificationType.review,
      title: 'New Review',
      message: 'You received a 5-star review from Emma Thompson.',
      timestamp: DateTime.now().subtract(const Duration(days: 3)),
      user: users[4],
    ),
  ];

  // Cuisine categories
  static const cuisineCategories = [
    'All',
    'Italian',
    'Japanese',
    'French',
    'American',
    'Mexican',
    'Asian Fusion',
    'Mediterranean',
    'Wine',
    'Desserts',
  ];

  // Interest tags
  static const interestTags = [
    'Fine Dining',
    'Casual',
    'Wine Pairing',
    'Cooking Class',
    'Social',
    'Romantic',
    'Business',
    'Food Photography',
    'Farm-to-Table',
    'Street Food',
    'Brunch',
    'Cocktails',
    'Desserts',
    'Vegetarian',
    'Vegan',
    'Gluten-Free',
  ];

  // Dietary options
  static const dietaryOptions = [
    'Vegetarian',
    'Vegan',
    'Gluten-Free',
    'Dairy-Free',
    'Nut-Free',
    'Halal',
    'Kosher',
    'None',
  ];

  // Dress code options
  static const dressCodeOptions = [
    'Casual',
    'Smart Casual',
    'Business Casual',
    'Formal',
    'Traditional Attire',
  ];

  // Age restriction options
  static const ageRestrictionOptions = ['None', '18+', '21+'];

  // Event rule options
  static const eventRuleOptions = [
    'No photography',
    'No outside food',
    'Punctuality required',
    'Dress to impress',
    'Social media friendly',
  ];

  // Event category options
  static const eventCategoryOptions = [
    'Public Dinner',
    'Private Dinner',
    'Food Experience',
    'Influencer Event',
    'Tasting',
    'Special Menu',
    'Group Dining',
  ];

  // Cancellation policy options
  static const cancellationPolicyOptions = [
    'Free up to 48h',
    'Free up to 24h',
    'No refunds',
    'Custom',
  ];

  // Followed hosts/influencers (IDs of users the current user follows)
  static const followedHostIds = ['user_1', 'user_2'];
  static const followedInfluencerIds = ['user_0', 'user_3', 'user_4'];

  // --- Home feed convenience getters ---

  /// Dinners sorted by soonest date first
  static List<Dinner> get upcomingEvents =>
      List<Dinner>.from(dinners)
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  /// Restaurants ranked by rating desc, then review count desc
  static List<Restaurant> get trendingRestaurants =>
      List<Restaurant>.from(restaurants)..sort((a, b) {
        final cmp = b.rating.compareTo(a.rating);
        return cmp != 0 ? cmp : b.reviewCount.compareTo(a.reviewCount);
      });

  /// Partner offers of type exclusiveExperience
  static List<PartnerOffer> get exclusiveMenus => partnerOffers
      .where((o) => o.type == OfferType.exclusiveExperience)
      .toList();

  /// Partner offers of type discount
  static List<PartnerOffer> get discountedExperiences =>
      partnerOffers.where((o) => o.type == OfferType.discount).toList();

  /// Dinners sorted by most recently created (latest dateTime first)
  static List<Dinner> get newEvents =>
      List<Dinner>.from(dinners)
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

  /// Dinners hosted by followed hosts
  static List<Dinner> get eventsFromFollowedHosts =>
      dinners.where((d) => followedHostIds.contains(d.host.id)).toList();

  /// Dinners hosted by followed influencers
  static List<Dinner> get eventsFromFollowedInfluencers =>
      dinners.where((d) => followedInfluencerIds.contains(d.host.id)).toList();

  /// Partner restaurants
  static List<Restaurant> get featuredRestaurants =>
      restaurants.where((r) => r.isPartner).toList();

  // --- Location & Discovery ---

  /// Available cities for location selection (Pakistan-first, matching the
  /// seeded Karachi world the app ships in).
  static const cities = [
    'Karachi',
    'Lahore',
    'Islamabad',
    'Rawalpindi',
    'Faisalabad',
    'Multan',
    'Peshawar',
    'Hyderabad',
  ];

  /// Recently selected/searched locations
  static const recentLocations = [
    'Karachi',
    'DHA Karachi',
    'Clifton',
    'Gulshan-e-Iqbal',
  ];

  /// Mock distances (miles) from "current location" for dinners
  static const dinnerDistances = {
    'dinner_1': 0.3,
    'dinner_2': 1.2,
    'dinner_3': 2.5,
    'dinner_4': 0.8,
    'dinner_5': 3.1,
    'dinner_6': 1.7,
    'dinner_7': 4.2,
    'dinner_8': 2.9,
  };

  /// Mock distances (miles) from "current location" for restaurants
  static const restaurantDistances = {
    'rest_1': 0.3,
    'rest_2': 1.2,
    'rest_3': 2.5,
    'rest_4': 0.8,
    'rest_5': 3.1,
    'rest_6': 1.7,
  };

  /// Get mock distance for a dinner by ID
  static double distanceForDinner(String id) => dinnerDistances[id] ?? 5.0;

  /// Get mock distance for a restaurant by ID
  static double distanceForRestaurant(String id) =>
      restaurantDistances[id] ?? 5.0;

  // Reviews
  static List<Review> get reviews => [
    Review(
      id: 'review_1',
      reviewer: users[1],
      rating: 5,
      comment: 'Absolutely incredible omakase experience! Every course was a masterpiece. The chef really knows how to highlight the best seasonal ingredients.',
      createdAt: DateTime(2025, 9, 15),
    ),
    Review(
      id: 'review_2',
      reviewer: users[2],
      rating: 5,
      comment: 'Best dining event I have ever attended. The atmosphere was intimate and the food was world-class.',
      createdAt: DateTime(2025, 9, 10),
    ),
    Review(
      id: 'review_3',
      reviewer: users[3],
      rating: 4,
      comment: 'Great experience overall. The wine pairing was exceptional. Would have loved a bit more time between courses.',
      createdAt: DateTime(2025, 8, 28),
    ),
    Review(
      id: 'review_4',
      reviewer: users[4],
      rating: 5,
      comment: 'The pasta making class was so much fun! Learned techniques I still use at home. Highly recommend.',
      createdAt: DateTime(2025, 8, 20),
    ),
    Review(
      id: 'review_5',
      reviewer: users[0],
      rating: 4,
      comment: 'Wonderful rooftop setting and the sunset views were breathtaking. Food was delicious.',
      createdAt: DateTime(2025, 8, 15),
    ),
    Review(
      id: 'review_6',
      reviewer: users[1],
      rating: 5,
      comment: 'The steak was perfectly cooked and the Napa wine selections were superb. A must-attend for wine lovers.',
      createdAt: DateTime(2025, 7, 30),
    ),
  ];

  /// Get reviews for a specific dinner (returns subset based on dinner index)
  static List<Review> reviewsForDinner(String dinnerId) {
    final index = dinners.indexWhere((d) => d.id == dinnerId);
    if (index < 0) return reviews.take(2).toList();
    final start = (index * 2) % reviews.length;
    final count = 2 + (index % 3);
    final result = <Review>[];
    for (var i = 0; i < count; i++) {
      result.add(reviews[(start + i) % reviews.length]);
    }
    return result;
  }

  /// Get other events hosted by the same user
  static List<Dinner> otherEventsByHost(String dinnerId) {
    final dinner = dinners.firstWhere((d) => d.id == dinnerId);
    return dinners
        .where((d) => d.host.id == dinner.host.id && d.id != dinnerId)
        .toList();
  }

  // ── Host Studio (sections 11 + 12) ──

  /// Platform commission rate applied to host gross revenue
  static const double platformCommissionRate = 0.10;

  /// Dinners hosted by the current user across all lifecycle states
  static List<Dinner> get myHostedEvents => [
    Dinner(
      id: 'mine_1',
      title: 'Golden Gate Tasting Night',
      description: 'An intimate 7-course tasting journey through California\u2019s seasonal best, paired with local wines. Hosted at the chef\u2019s counter.',
      restaurant: restaurants[0],
      host: currentUser,
      dateTime: DateTime.now().add(const Duration(days: 3, hours: 19)),
      totalSeats: 12,
      bookedSeats: 10,
      pricePerSeat: 155.0,
      imagePath: 'assets/images/dish_sushi.png',
      menu: [
        const MenuItem(
          id: 'mine_menu_1',
          name: 'Seasonal Crudo',
          description: 'Local catch, citrus, chili oil',
          price: 24.0,
        ),
        const MenuItem(
          id: 'mine_menu_2',
          name: '7-Course Tasting',
          description: 'Chef\u2019s seasonal journey with wine pairing',
          price: 155.0,
        ),
      ],
      tags: ['Tasting', 'Wine Pairing', 'Fine Dining'],
      isPublic: true,
      isSpecialEvent: true,
      dressCode: 'Smart Casual',
      cancellationPolicy: 'Free cancellation up to 48 hours before',
      category: 'Food Experience',
      attendees: [users[0], users[1], users[2], users[3], users[4]],
    ),
    Dinner(
      id: 'mine_2',
      title: 'Secret Supper: Chinatown Crawl',
      description: 'A guided crawl through four of Chinatown\u2019s hidden kitchens, ending with a private family-style dinner.',
      restaurant: restaurants[3],
      host: currentUser,
      dateTime: DateTime.now().add(const Duration(days: 9, hours: 18)),
      totalSeats: 14,
      bookedSeats: 3,
      pricePerSeat: 95.0,
      imagePath: 'assets/images/dish_tacos.png',
      menu: [
        const MenuItem(
          id: 'mine_menu_3',
          name: 'Crawl Passport',
          description: 'Tastings at 4 stops + family dinner',
          price: 95.0,
        ),
      ],
      tags: ['Street Food', 'Social', 'Casual'],
      isPublic: true,
      cancellationPolicy: 'Free cancellation up to 24 hours before',
      category: 'Food Experience',
      attendees: [users[0], users[2], users[4]],
    ),
    Dinner(
      id: 'mine_3',
      title: 'Winter Wine Pairing Dinner',
      description: 'A cozy 5-course winter menu built around bold reds from small Napa producers. Bookings temporarily paused while the menu is finalized.',
      restaurant: restaurants[2],
      host: currentUser,
      dateTime: DateTime.now().add(const Duration(days: 14, hours: 19)),
      totalSeats: 10,
      bookedSeats: 4,
      pricePerSeat: 140.0,
      imagePath: 'assets/images/dish_steak.png',
      menu: [
        const MenuItem(
          id: 'mine_menu_4',
          name: 'Winter Tasting Menu',
          description: '5 courses with 4 wine pours',
          price: 140.0,
        ),
      ],
      tags: ['Wine Pairing', 'Seasonal'],
      isPublic: true,
      ageRestriction: '21+',
      cancellationPolicy: 'Free cancellation up to 48 hours before',
      category: 'Tasting',
      attendees: [users[1], users[3], users[8]],
      hostStatus: HostEventStatus.pausedBookings,
    ),
    Dinner(
      id: 'mine_4',
      title: 'Autumn Harvest Dinner',
      description: 'A family-style harvest celebration at Le Petit Bistro: roasted vegetables, slow-braised mains and a cider toast.',
      restaurant: restaurants[4],
      host: currentUser,
      dateTime: DateTime.now().subtract(const Duration(days: 12, hours: 5)),
      totalSeats: 8,
      bookedSeats: 8,
      pricePerSeat: 125.0,
      imagePath: 'assets/images/venue_interior.png',
      menu: [
        const MenuItem(
          id: 'mine_menu_5',
          name: 'Harvest Feast',
          description: 'Family-style seasonal dinner',
          price: 125.0,
        ),
      ],
      tags: ['Seasonal', 'Family Style'],
      isPublic: true,
      cancellationPolicy: 'Free cancellation up to 48 hours before',
      category: 'Public Dinner',
      attendees: [users[0], users[1], users[2], users[3], users[4], users[6]],
      hostStatus: HostEventStatus.completed,
    ),
    Dinner(
      id: 'mine_5',
      title: 'Summer Beach BBQ Night',
      description: 'A sunset beach barbecue with grilled classics and frozen cocktails. Cancelled due to venue permits.',
      restaurant: restaurants[3],
      host: currentUser,
      dateTime: DateTime.now().subtract(const Duration(days: 20, hours: 5)),
      totalSeats: 16,
      bookedSeats: 9,
      pricePerSeat: 85.0,
      imagePath: 'assets/images/venue_rooftop.png',
      menu: [
        const MenuItem(
          id: 'mine_menu_6',
          name: 'Beach BBQ Plate',
          description: 'Grilled plate + frozen cocktail',
          price: 85.0,
        ),
      ],
      tags: ['BBQ', 'Outdoor', 'Casual'],
      isPublic: true,
      cancellationPolicy: 'Free cancellation up to 24 hours before',
      category: 'Group Dining',
      attendees: [users[1], users[2], users[4], users[6], users[8]],
      hostStatus: HostEventStatus.cancelled,
    ),
  ];

  /// Gross revenue across non-cancelled hosted events
  static double get grossRevenue => myHostedEvents
      .where((d) => d.hostStatus != HostEventStatus.cancelled)
      .fold(0.0, (sum, d) => sum + d.bookedSeats * d.pricePerSeat);

  /// Platform commission on gross revenue
  static double get platformCommission => grossRevenue * platformCommissionRate;

  /// Gross minus platform commission
  static double get netEarnings => grossRevenue - platformCommission;

  /// Withdrawable net earnings (from completed events)
  static double get availableBalance => myHostedEvents
      .where((d) => d.hostStatus == HostEventStatus.completed)
      .fold(
        0.0,
        (sum, d) =>
            sum + d.bookedSeats * d.pricePerSeat * (1 - platformCommissionRate),
      );

  /// Net earnings from active events, not yet paid out
  static double get pendingEarnings => netEarnings - availableBalance;

  /// Seats sold across non-cancelled hosted events
  static int get seatsSold => myHostedEvents
      .where((d) => d.hostStatus != HostEventStatus.cancelled)
      .fold(0, (sum, d) => sum + d.bookedSeats);

  /// Seats still open on active events
  static int get seatsAvailable => myHostedEvents
      .where(
        (d) =>
            d.hostStatus == HostEventStatus.published ||
            d.hostStatus == HostEventStatus.pausedBookings,
      )
      .fold(0, (sum, d) => sum + d.availableSeats);

  /// Distinct confirmed guests expected on active events
  static int get guestCount => myHostedEvents
      .where(
        (d) =>
            d.hostStatus == HostEventStatus.published ||
            d.hostStatus == HostEventStatus.pausedBookings,
      )
      .expand(
        (d) =>
            guestEntriesFor(d.id)
                .where((g) => g.status == GuestRequestStatus.approved),
      )
      .map((g) => g.user.id)
      .toSet()
      .length;

  /// Confirmed bookings across hosted events
  static int get totalBookings => myHostedEvents.fold(
    0,
    (sum, d) =>
        guestEntriesFor(d.id)
            .where((g) => g.status != GuestRequestStatus.rejected)
            .length,
  );

  /// Guest entries (approved + requests) for a hosted event
  static List<GuestEntry> guestEntriesFor(String eventId) {
    final now = DateTime.now();
    switch (eventId) {
      case 'mine_1':
        return [
          GuestEntry(
            id: 'ge_101',
            user: users[0],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 2)),
            message: 'So excited for this one!',
          ),
          GuestEntry(
            id: 'ge_102',
            user: users[1],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 1)),
          ),
          GuestEntry(
            id: 'ge_103',
            user: users[2],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(hours: 22)),
          ),
          GuestEntry(
            id: 'ge_104',
            user: users[3],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(hours: 20)),
          ),
          GuestEntry(
            id: 'ge_105',
            user: users[4],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(hours: 18)),
          ),
          GuestEntry(
            id: 'ge_106',
            user: users[6],
            seats: 2,
            status: GuestRequestStatus.pending,
            requestedAt: now.subtract(const Duration(hours: 5)),
            message: 'Celebrating our anniversary. Would love to join!',
          ),
          GuestEntry(
            id: 'ge_107',
            user: users[7],
            seats: 1,
            status: GuestRequestStatus.pending,
            requestedAt: now.subtract(const Duration(hours: 3)),
            message: 'Vegetarian. Is a veg menu possible?',
          ),
          GuestEntry(
            id: 'ge_108',
            user: users[8],
            seats: 2,
            status: GuestRequestStatus.pending,
            requestedAt: now.subtract(const Duration(hours: 1)),
            message: 'Bringing a bottle of Barolo to share.',
          ),
        ];
      case 'mine_2':
        return [
          GuestEntry(
            id: 'ge_201',
            user: users[0],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 3)),
          ),
          GuestEntry(
            id: 'ge_202',
            user: users[2],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 2)),
          ),
          GuestEntry(
            id: 'ge_203',
            user: users[4],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 1)),
          ),
          GuestEntry(
            id: 'ge_204',
            user: users[7],
            seats: 2,
            status: GuestRequestStatus.pending,
            requestedAt: now.subtract(const Duration(hours: 8)),
            message: 'Two of us. First crawl, can\u2019t wait!',
          ),
        ];
      case 'mine_3':
        return [
          GuestEntry(
            id: 'ge_301',
            user: users[1],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 4)),
          ),
          GuestEntry(
            id: 'ge_302',
            user: users[3],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 2)),
          ),
          GuestEntry(
            id: 'ge_303',
            user: users[8],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 1)),
            message: 'Happy to contribute a bottle from my cellar.',
          ),
        ];
      case 'mine_4':
        return [
          GuestEntry(
            id: 'ge_401',
            user: users[0],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 16)),
            checkIn: CheckInStatus.checkedIn,
            checkInTime: now
                .subtract(const Duration(days: 12))
                .add(const Duration(hours: 19, minutes: 2)),
          ),
          GuestEntry(
            id: 'ge_402',
            user: users[1],
            seats: 2,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 15)),
            checkIn: CheckInStatus.checkedIn,
            checkInTime: now
                .subtract(const Duration(days: 12))
                .add(const Duration(hours: 18, minutes: 55)),
          ),
          GuestEntry(
            id: 'ge_403',
            user: users[2],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 14)),
            checkIn: CheckInStatus.checkedIn,
            checkInTime: now
                .subtract(const Duration(days: 12))
                .add(const Duration(hours: 19, minutes: 10)),
          ),
          GuestEntry(
            id: 'ge_404',
            user: users[3],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 13)),
            checkIn: CheckInStatus.checkedIn,
            checkInTime: now
                .subtract(const Duration(days: 12))
                .add(const Duration(hours: 19, minutes: 21)),
          ),
          GuestEntry(
            id: 'ge_405',
            user: users[4],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 13)),
            checkIn: CheckInStatus.checkedIn,
            checkInTime: now
                .subtract(const Duration(days: 12))
                .add(const Duration(hours: 19, minutes: 38)),
          ),
          GuestEntry(
            id: 'ge_406',
            user: users[6],
            seats: 1,
            status: GuestRequestStatus.approved,
            requestedAt: now.subtract(const Duration(days: 12)),
            checkIn: CheckInStatus.expired,
          ),
        ];
      case 'mine_5':
        return [
          GuestEntry(
            id: 'ge_501',
            user: users[1],
            seats: 2,
            status: GuestRequestStatus.cancelled,
            requestedAt: now.subtract(const Duration(days: 25)),
          ),
          GuestEntry(
            id: 'ge_502',
            user: users[2],
            seats: 1,
            status: GuestRequestStatus.cancelled,
            requestedAt: now.subtract(const Duration(days: 24)),
          ),
          GuestEntry(
            id: 'ge_503',
            user: users[4],
            seats: 2,
            status: GuestRequestStatus.cancelled,
            requestedAt: now.subtract(const Duration(days: 23)),
          ),
          GuestEntry(
            id: 'ge_504',
            user: users[6],
            seats: 2,
            status: GuestRequestStatus.cancelled,
            requestedAt: now.subtract(const Duration(days: 22)),
          ),
          GuestEntry(
            id: 'ge_505',
            user: users[8],
            seats: 2,
            status: GuestRequestStatus.cancelled,
            requestedAt: now.subtract(const Duration(days: 22)),
          ),
        ];
      default:
        return const [];
    }
  }

  /// Pending seat requests for a hosted event
  static int pendingRequestsFor(String eventId) =>
      guestEntriesFor(eventId)
          .where((g) => g.status == GuestRequestStatus.pending)
          .length;

  /// Collaboration invitations from restaurant partners
  static List<CollaborationInvite> get collaborationInvites => [
    CollaborationInvite(
      id: 'inv_1',
      restaurant: restaurants[0],
      title: 'Omakase Collaboration Series',
      message: 'Hi Alex, our head chef loved your last tasting night. We would like to invite you to co-host a 4-night omakase collaboration series at Nobu this season: chef\u2019s counter, full creative control on the menu.',
      receivedAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
    CollaborationInvite(
      id: 'inv_2',
      restaurant: restaurants[2],
      title: 'Brand-Sponsored Tasting Evening',
      message: 'A wine brand partner wants to sponsor a steak & wine tasting evening hosted by you. We cover the venue, product and a guaranteed honorarium. 20 seats, invite-only.',
      receivedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    CollaborationInvite(
      id: 'inv_3',
      restaurant: restaurants[5],
      title: 'Rooftop Sunset Series',
      message: 'Welcome back! The rooftop sunset series is confirmed for monthly editions. Your September edition sold out in 48 hours. The October slot is yours whenever you are ready.',
      receivedAt: DateTime.now().subtract(const Duration(days: 9)),
      isAccepted: true,
    ),
  ];

  /// Host payout history
  static List<HostPayout> get myPayouts => [
    HostPayout(
      id: 'po_1',
      amount: 900.0,
      method: bankMasked,
      status: 'paid',
      date: DateTime.now().subtract(const Duration(days: 5)),
      period: 'Autumn Harvest Dinner',
    ),
    HostPayout(
      id: 'po_2',
      amount: 1116.0,
      method: bankMasked,
      status: 'processing',
      date: DateTime.now().subtract(const Duration(days: 1)),
      period: 'September events',
    ),
    HostPayout(
      id: 'po_3',
      amount: 1240.0,
      method: 'PayPal',
      status: 'paid',
      date: DateTime(2026, 9, 2),
      period: 'August events',
    ),
    HostPayout(
      id: 'po_4',
      amount: 860.0,
      method: bankMasked,
      status: 'paid',
      date: DateTime(2026, 8, 2),
      period: 'July events',
    ),
    HostPayout(
      id: 'po_5',
      amount: 1120.0,
      method: bankMasked,
      status: 'paid',
      date: DateTime(2026, 7, 3),
      period: 'June events',
    ),
  ];

  /// Per-event performance metrics for hosted events
  static List<EventPerformance> get eventPerformance => [
    EventPerformance(
      dinner: myHostedEvents[0],
      views: 2840,
      bookings: 10,
      checkedIn: 0,
    ),
    EventPerformance(
      dinner: myHostedEvents[1],
      views: 1930,
      bookings: 3,
      checkedIn: 0,
    ),
    EventPerformance(
      dinner: myHostedEvents[2],
      views: 1120,
      bookings: 4,
      checkedIn: 0,
    ),
    EventPerformance(
      dinner: myHostedEvents[3],
      views: 2410,
      bookings: 8,
      checkedIn: 7,
    ),
    EventPerformance(
      dinner: myHostedEvents[4],
      views: 1580,
      bookings: 9,
      checkedIn: 0,
    ),
  ];

  /// Number of events hosted together with a partner restaurant
  static int eventsWithRestaurant(String restaurantId) {
    switch (restaurantId) {
      case 'rest_1':
        return 3;
      case 'rest_5':
        return 2;
      case 'rest_6':
        return 2;
      case 'rest_2':
        return 1;
      case 'rest_3':
        return 1;
      default:
        return 0;
    }
  }
}
