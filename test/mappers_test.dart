import 'package:flutter_test/flutter_test.dart';

import 'package:dine_circle/api/dto/event_dto.dart';
import 'package:dine_circle/api/dto/restaurant_dto.dart';
import 'package:dine_circle/api/dto/review_dto.dart';
import 'package:dine_circle/api/dto/user_dto.dart';
import 'package:dine_circle/api/dto/tier_dto.dart';
import 'package:dine_circle/api/dto/offer_dto.dart';
import 'package:dine_circle/api/mappers/mappers.dart';
import 'package:dine_circle/models/dinner.dart';
import 'package:dine_circle/models/host_models.dart';
import 'package:dine_circle/models/offer.dart';
import 'package:dine_circle/models/discovery_category.dart';

/// A slim list-feed event payload (only host + venue references, no menu).
Map<String, dynamic> slimEventJson() => {
  'id': 'e1',
  'title': 'Omakase Night',
  'tagline': 'Chef\u2019s counter',
  'description': '',
  'hostId': 'h1',
  'host': {
    'id': 'h1',
    'name': 'Nora Chen',
    'handle': 'nora',
    'avatarUrl': null,
  },
  'restaurantId': 'r1',
  'restaurant': {'id': 'r1', 'name': 'Skyline Room', 'neighborhood': 'SoMa'},
  'startAt': '2030-01-01T18:00:00Z',
  'durationMinutes': 120,
  'seatsTotal': 10,
  'seatsBooked': 4,
  'pricePerSeat': 120,
  'type': 'tasting',
  'audience': 'public',
  'tags': ['sushi'],
  'isFeatured': true,
};

void main() {
  group('dinnerFromEvent — partial-safe list payload', () {
    final dinner = Mappers.dinnerFromEvent(EventDto.fromJson(slimEventJson()));

    test('maps core scalar fields', () {
      expect(dinner.id, 'e1');
      expect(dinner.title, 'Omakase Night');
      // Empty description falls back to the tagline.
      expect(dinner.description, 'Chef\u2019s counter');
      expect(dinner.totalSeats, 10);
      expect(dinner.bookedSeats, 4);
      expect(dinner.availableSeats, 6);
      expect(dinner.pricePerSeat, 120);
    });

    test('leaves absent restaurant coordinates null (kept off the map)', () {
      expect(dinner.restaurant.id, 'r1');
      expect(dinner.restaurant.name, 'Skyline Room');
      // No coordinates in the payload → null, so the venue is not pinned to
      // (0,0) in the Gulf of Guinea; it simply stays off the map.
      expect(dinner.restaurant.latitude, isNull);
      expect(dinner.restaurant.longitude, isNull);
      expect(dinner.restaurant.hasCoordinates, isFalse);
      expect(dinner.restaurant.description, '');
      // Address falls back to the venue neighborhood when there is no street.
      expect(dinner.restaurant.address, 'SoMa');
    });

    test('host reference becomes a UserProfile with defaults', () {
      expect(dinner.host.id, 'h1');
      expect(dinner.host.name, 'Nora Chen');
      expect(dinner.host.isVerified, isFalse);
      expect(dinner.host.isInfluencer, isFalse);
    });

    test('derives category label, endsAt, visibility and featured flag', () {
      expect(dinner.category, 'Tasting'); // type label for 'tasting'
      expect(dinner.isSpecialEvent, isTrue); // isFeatured → isSpecialEvent
      expect(dinner.isPublic, isTrue); // audience == 'public'
      expect(dinner.endsAt, dinner.dateTime.add(const Duration(minutes: 120)));
    });

    test('no menu/attendees on a list payload', () {
      expect(dinner.menu, isEmpty);
      expect(dinner.attendees, isEmpty);
    });
  });

  test('dinnerFromEvent — detail payload maps venue, menu and attendees', () {
    final dto = EventDto.fromJson({
      ...slimEventJson(),
      'venue': {
        'id': 'r1',
        'name': 'Skyline Room',
        'about': 'A refined tasting room.',
        'cuisines': ['Japanese', 'Korean'],
        'address': '1 Market St',
        'rating': 4.7,
        'reviewCount': 12,
        'isPartner': true,
      },
      'menu': [
        {
          'id': 'm1',
          'name': 'Nigiri',
          'description': 'Assorted',
          'pairing': 'Sake',
          'isSignature': true,
        },
      ],
      'attendees': [
        {'id': 'a1', 'name': 'Guest One'},
      ],
    });

    final dinner = Mappers.dinnerFromEvent(dto);

    // The full venue replaces the slim reference.
    expect(dinner.restaurant.description, 'A refined tasting room.');
    expect(dinner.restaurant.cuisine, 'Japanese, Korean');
    expect(dinner.restaurant.address, '1 Market St');
    expect(dinner.restaurant.rating, 4.7);
    expect(dinner.restaurant.isPartner, isTrue);

    // Courses → menu items; price defaults to 0 (API has no course price) and
    // the pairing is folded into the description; signature is tagged.
    expect(dinner.menu, hasLength(1));
    expect(dinner.menu.first.name, 'Nigiri');
    expect(dinner.menu.first.price, 0);
    expect(dinner.menu.first.description, 'Assorted \u2022 Sake');
    expect(dinner.menu.first.tags, contains('Signature'));

    expect(dinner.attendees, hasLength(1));
    expect(dinner.attendees.first.name, 'Guest One');
  });

  // P0-2: the server exposes a lifecycle `status`; the Host Studio drafts
  // section keys off the mapped hostStatus.
  group('dinnerFromEvent — status → hostStatus', () {
    Dinner dinnerWithStatus(String status) => Mappers.dinnerFromEvent(
      EventDto.fromJson({...slimEventJson(), 'status': status}),
    );

    test('draft maps to HostEventStatus.draft', () {
      expect(dinnerWithStatus('draft').hostStatus, HostEventStatus.draft);
    });

    test('completed and cancelled map to their terminal states', () {
      expect(
        dinnerWithStatus('completed').hostStatus,
        HostEventStatus.completed,
      );
      expect(
        dinnerWithStatus('cancelled').hostStatus,
        HostEventStatus.cancelled,
      );
      expect(
        dinnerWithStatus('declined').hostStatus,
        HostEventStatus.cancelled,
      );
    });

    test('public lifecycle states collapse to published', () {
      for (final status in ['confirmed', 'live', 'requested']) {
        expect(dinnerWithStatus(status).hostStatus, HostEventStatus.published);
      }
    });

    test('a payload without status defaults to published', () {
      expect(
        Mappers.dinnerFromEvent(EventDto.fromJson(slimEventJson())).hostStatus,
        HostEventStatus.published,
      );
    });
  });

  group('userFromDto — derived flags from role', () {
    test('partner_admin maps to isRestaurantPartner', () {
      final user = Mappers.userFromDto(
        UserDto.fromJson({'id': 'u1', 'name': 'Pat', 'role': 'partner_admin'}),
      );
      expect(user.isRestaurantPartner, isTrue);
    });

    test('a plain user is not a partner', () {
      final user = Mappers.userFromDto(
        UserDto.fromJson({'id': 'u2', 'name': 'Kim', 'role': 'user'}),
      );
      expect(user.isRestaurantPartner, isFalse);
      expect(user.isVerified, isFalse);
      expect(user.isInfluencer, isFalse);
      expect(user.socialLinks, isEmpty);
    });

    test('renames API fields onto the domain model', () {
      final user = Mappers.userFromDto(
        UserDto.fromJson({
          'id': 'u3',
          'name': 'Ada',
          'dinnersJoined': 7,
          'tastes': ['Ramen'],
          'city': 'Oakland',
          'bio': '',
        }),
      );
      expect(user.dinnersAttended, 7); // dinnersJoined → dinnersAttended
      expect(user.interests, ['Ramen']); // tastes → interests
      expect(user.location, 'Oakland'); // city → location
      expect(user.bio, isNull); // empty bio collapses to null
    });
  });

  test('restaurantFromDto address falls back to neighborhood and keeps coords null', () {
    final r = Mappers.restaurantFromDto(
      RestaurantDto.fromJson({
        'id': 'r9',
        'name': 'Bistro',
        'neighborhood': 'Downtown',
        'address': '',
      }),
    );
    expect(r.address, 'Downtown');
    expect(r.latitude, isNull);
    expect(r.longitude, isNull);
    expect(r.hasCoordinates, isFalse);
  });

  test('restaurantFromDto carries real coordinates when present', () {
    final r = Mappers.restaurantFromDto(
      RestaurantDto.fromJson({
        'id': 'r10',
        'name': 'Kolachi',
        'latitude': 24.8055,
        'longitude': 67.0305,
        'distanceKm': 1.2,
      }),
    );
    expect(r.latitude, 24.8055);
    expect(r.longitude, 67.0305);
    expect(r.distanceKm, 1.2);
    expect(r.hasCoordinates, isTrue);
  });

  test('restaurantFromDto carries partnershipStatus and defaults to empty', () {
    final r = Mappers.restaurantFromDto(
      RestaurantDto.fromJson({
        'id': 'r9',
        'name': 'Bistro',
        'isPartner': true,
        'partnershipStatus': 'verified',
      }),
    );
    expect(r.isPartner, isTrue);
    expect(r.partnershipStatus, 'verified');
    final d = Mappers.restaurantFromDto(
      RestaurantDto.fromJson({'id': 'r8', 'name': 'NoStatus'}),
    );
    expect(d.partnershipStatus, '');
  });

  test('reviewFromDto fills a placeholder author name and keeps rating', () {
    final review = Mappers.reviewFromDto(
      ReviewDto.fromJson({
        'id': 'rev1',
        'rating': 5,
        'text': 'Lovely',
        'author': {'id': 'a1', 'name': ''},
      }),
    );
    expect(review.rating, 5);
    expect(review.comment, 'Lovely');
    expect(review.reviewer.name, 'A diner'); // empty author name fallback
  });

  // Growth ladder on one account: role 'influencer' keeps host capability,
  // verified flows from the server flag or the legacy badge, and tier status
  // parses straight off the /users/me/tier envelope.
  group('Growth tier mapping', () {
    test('influencer role implies host capability + flags', () {
      final dto = UserDto.fromJson({
        'id': 'u1',
        'name': 'Fatima',
        'role': 'influencer',
        'isVerified': true,
      });
      expect(dto.isHost, isTrue);
      expect(dto.isInfluencer, isTrue);

      final user = Mappers.userFromDto(dto);
      expect(user.isInfluencer, isTrue);
      expect(user.isVerified, isTrue);
    });

    test('verified badge is the fallback when the flag is absent', () {
      final dto = UserDto.fromJson({
        'id': 'u2',
        'name': 'Nora',
        'role': 'host',
        'badges': ['verified'],
      });
      expect(dto.isVerified, isTrue);
      expect(dto.isInfluencer, isFalse);
      expect(Mappers.userFromDto(dto).isVerified, isTrue);
    });

    test('host ref carries tier flags onto the dinner host', () {
      final dinner = Mappers.dinnerFromEvent(
        EventDto.fromJson({
          ...slimEventJson(),
          'host': {
            'id': 'h1',
            'name': 'Fatima',
            'isVerified': true,
            'isInfluencer': true,
          },
        }),
      );
      expect(dinner.host.isInfluencer, isTrue);
      expect(dinner.host.isVerified, isTrue);
    });

    test('TierDto.fromJson normalizes progress + thresholds to double', () {
      final tier = TierDto.fromJson({
        'tier': 'host',
        'eligible': true,
        'progress': {'followers': 80, 'rating': 4.5},
        'thresholds': {'minFollowers': 50, 'minRating': 4},
      });
      expect(tier.tier, 'host');
      expect(tier.eligible, isTrue);
      expect(tier.progress['followers'], 80.0);
      expect(tier.thresholds['minRating'], 4.0);
    });
  });

  // Discovery categories: JSON → Offer/PromoCode mapping plus the UI-only
  // DiscoveryCategory parser used to round-trip route/param strings.
  group('offerFeedFromDto — /offers envelope', () {
    final feed = Mappers.offerFeedFromDto(
      OfferFeedDto.fromJson({
        'offers': [
          {
            'id': 'o1',
            'name': 'Date Night Tasting',
            'description': 'Five courses for two',
            'restaurantId': 'r1',
            'restaurantName': 'Skyline Room',
            'city': 'Karachi',
            'pricePerGuest': 120,
            'minGuests': 2,
            'tags': ['couple', 'wine'],
            'kind': 'couple',
          },
        ],
        'promos': [
          {'code': 'DINE20', 'discountPct': 20},
        ],
      }),
    );

    test('maps an offer row onto the domain model', () {
      final offer = feed.offers.single;
      expect(offer.id, 'o1');
      expect(offer.name, 'Date Night Tasting');
      expect(offer.restaurantName, 'Skyline Room');
      expect(offer.pricePerGuest, 120);
      expect(offer.minGuests, 2);
      expect(offer.kind, 'couple');
      expect(offer.kindLabel, 'For two');
      expect(offer.tags, ['couple', 'wine']);
    });

    test('maps a promo row and derives its label', () {
      final promo = feed.promos.single;
      expect(promo.code, 'DINE20');
      expect(promo.discountPct, 20);
      expect(promo.label, 'DINE20 \u00b7 20% off');
    });

    test('an offer keys off its id for ==/hashCode', () {
      const a = Offer(
        id: 'o1',
        name: 'X',
        description: '',
        restaurantId: 'r1',
        restaurantName: '',
        city: '',
        pricePerGuest: 0,
        minGuests: 2,
      );
      const b = Offer(
        id: 'o1',
        name: 'Different',
        description: '',
        restaurantId: 'r2',
        restaurantName: '',
        city: '',
        pricePerGuest: 99,
        minGuests: 4,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a ==
            const Offer(
              id: 'zz',
              name: 'X',
              description: '',
              restaurantId: 'r1',
              restaurantName: '',
              city: '',
              pricePerGuest: 0,
              minGuests: 2,
            ),
        isFalse,
      );
    });
  });

  test('empty /offers payload yields an empty feed', () {
    final feed = Mappers.offerFeedFromDto(OfferFeedDto.fromJson({}));
    expect(feed.offers, isEmpty);
    expect(feed.promos, isEmpty);
  });

  group('DiscoveryCategory.fromName', () {
    test('round-trips every category key', () {
      for (final category in DiscoveryCategory.values) {
        expect(DiscoveryCategoryX.fromName(category.key), category);
      }
    });

    test('is case-insensitive and tolerant of whitespace', () {
      expect(DiscoveryCategoryX.fromName('  DEALS '), DiscoveryCategory.deals);
      expect(
        DiscoveryCategoryX.fromName('socialDining'),
        DiscoveryCategory.socialDining,
      );
    });

    test('returns null for unknown or empty input', () {
      expect(DiscoveryCategoryX.fromName(null), isNull);
      expect(DiscoveryCategoryX.fromName(''), isNull);
      expect(DiscoveryCategoryX.fromName('nope'), isNull);
    });
  });
}
