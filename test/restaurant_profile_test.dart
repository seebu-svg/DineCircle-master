import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/models/deal.dart';
import 'package:dine_circle/models/dinner.dart';
import 'package:dine_circle/models/public_menu.dart';
import 'package:dine_circle/models/restaurant.dart';
import 'package:dine_circle/models/restaurant_review.dart';
import 'package:dine_circle/models/table_reservation.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/deals_provider.dart';
import 'package:dine_circle/providers/reservations_provider.dart';
import 'package:dine_circle/providers/restaurant_reviews_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/repositories/public_menu_repository.dart';
import 'package:dine_circle/screens/deals/deal_detail_screen.dart';
import 'package:dine_circle/screens/restaurant_detail/profile_info_sections.dart';
import 'package:dine_circle/screens/restaurant_detail/restaurant_detail_screen.dart';
import 'package:dine_circle/widgets/experience_card.dart';

import 'fake_repositories.dart';
import 'support/overflow_harness.dart';

/// Open every day, all day, so the hero pill is deterministic regardless of the
/// wall clock the test runs at.
final Map<String, dynamic> _alwaysOpen = {
  for (final day in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
    day: {
      'closed': false,
      'windows': [
        {'open': '00:00', 'close': '24:00'},
      ],
    },
};

Restaurant _venue({
  String name = 'Kolachi Restaurant',
  String? description,
  List<String> gallery = const [],
  List<String> amenities = const ['Rooftop', 'WiFi', 'Valet parking'],
  Map<String, dynamic>? openingHours,
  double rating = 4.7,
  int reviewCount = 128,
}) => Restaurant(
  id: 'r1',
  name: name,
  description: description ?? 'A seaside room built around the day\'s catch.',
  cuisine: 'Seafood',
  address: '16 Do Darya Avenue',
  neighborhood: 'Do Darya',
  city: 'Karachi',
  imagePath: 'assets/images/venue_rooftop.png',
  gallery: gallery,
  phoneNumber: '+92 300 1234567',
  rating: rating,
  reviewCount: reviewCount,
  priceRange: r'$$',
  tags: const ['Seafood', 'Fine dining'],
  isPartner: true,
  partnershipStatus: 'verified',
  openingHours: openingHours ?? _alwaysOpen,
  amenities: amenities,
);

PublicMenu _menu({List<PublicMenuSection>? sections}) => PublicMenu(
  restaurant: const PublicMenuRestaurant(
    id: 'r1',
    name: 'Kolachi Restaurant',
    city: 'Karachi',
    neighborhood: 'Do Darya',
  ),
  sections:
      sections ??
      const [
        PublicMenuSection(
          id: 's1',
          name: 'Starters',
          items: [
            PublicMenuItem(
              id: 'i1',
              name: 'Garlic Prawns',
              description: 'Charred tiger prawns, lemon butter',
              price: 2450,
              photoUrl: 'assets/images/dish_steak.png',
            ),
            PublicMenuItem(
              id: 'i2',
              name: 'Clam Chowder',
              description: 'Creamy clam soup',
              price: 690.5,
            ),
          ],
        ),
        PublicMenuSection(
          id: 's2',
          name: 'Grills',
          items: [
            PublicMenuItem(id: 'i3', name: 'Lamb Chops', price: 3200),
          ],
        ),
        PublicMenuSection(
          id: 's3',
          name: 'Desserts',
          items: [
            PublicMenuItem(id: 'i4', name: 'Gulab Jamun', price: 450),
          ],
        ),
      ],
);

Deal _deal({String title = 'Summer Seafood Feast'}) => Deal(
  id: 'd1',
  restaurantId: 'r1',
  restaurantName: 'Kolachi Restaurant',
  title: title,
  description: '20% off the a la carte menu',
  kind: 'percent',
  value: 20,
  startsAt: DateTime.now().subtract(const Duration(days: 2)),
  endsAt: DateTime.now().add(const Duration(days: 10)),
  terms: 'Dine-in only',
  coverImage: 'assets/images/dish_steak.png',
);

RestaurantReviewFeed _feed({bool empty = false}) => RestaurantReviewFeed(
  aggregate: RestaurantReviewAggregate(
    rating: empty ? 0 : 4.6,
    count: empty ? 0 : 4,
  ),
  reviews: empty
      ? const []
      : [
          for (final entry in const [
            (1, 5.0, 'Best seafood in the city.'),
            (2, 5.0, 'Service was impeccable.'),
            (3, 4.0, 'Lovely views, slow starters.'),
            (4, 3.0, 'Good food, noisy room.'),
          ])
            RestaurantReview(
              id: 'rv${entry.$1}',
              authorId: 'u${entry.$1}',
              authorName: 'Guest ${entry.$1}',
              restaurantId: 'r1',
              rating: entry.$2,
              text: entry.$3,
              createdAt: DateTime.now().subtract(Duration(days: entry.$1)),
            ),
        ],
);

class _FakeMenuRepository implements PublicMenuRepository {
  _FakeMenuRepository(this.menu);

  final PublicMenu menu;
  int scans = 0;

  @override
  Future<PublicMenu> fetch(String restaurantId) async => menu;

  @override
  Future<void> recordScan(String restaurantId) async => scans += 1;
}

List<Override> _overrides({
  Restaurant? venue,
  List<Dinner> events = const [],
  PublicMenu? menu,
  List<Deal> deals = const [],
  RestaurantReviewFeed? feed,
}) {
  final v = venue ?? _venue();
  return [
    authReadyProvider.overrideWithValue(true),
    restaurantsRepositoryProvider.overrideWithValue(
      FakeRestaurantsRepository(restaurants: [v], detailEvents: events),
    ),
    publicMenuRepositoryProvider.overrideWithValue(
      _FakeMenuRepository(menu ?? _menu()),
    ),
    restaurantDealsProvider.overrideWith((ref, id) async => deals),
    restaurantReviewsProvider.overrideWith((ref, id) async => feed ?? _feed()),
    myReservationsProvider.overrideWith(
      (ref) async => const <TableReservation>[],
    ),
  ];
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpProfile(
    WidgetTester tester, {
    required List<Override> overrides,
    Restaurant? seed,
    void Function(Dinner dinner)? onDinnerTap,
  }) async {
    await tester.pumpWidget(
      themedApp(
        home: RestaurantDetailScreen(
          restaurant: seed ?? _venue(),
          onDinnerTap: onDinnerTap,
        ),
        overrides: overrides,
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollController scrollController(WidgetTester tester) {
    final view = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    return view.controller!;
  }

  testWidgets('renders the venue identity, rating and open status', (
    tester,
  ) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(tester, overrides: _overrides());

    expect(find.text('Kolachi Restaurant'), findsWidgets);
    expect(find.textContaining('Do Darya · Karachi'), findsOneWidget);
    expect(find.textContaining('Seafood · Do Darya'), findsOneWidget);
    expect(find.text('4.7'), findsOneWidget);
    expect(find.text('Open now'), findsOneWidget);
    expect(find.text('VERIFIED'), findsOneWidget);
  });

  testWidgets('section nav lists only sections that exist', (tester) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(tester, overrides: _overrides());

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Deals'), findsWidgets);
    expect(find.text('Reviews'), findsWidgets);
    // No upcoming events at this venue → no Experiences tab at all.
    expect(find.text('Experiences'), findsNothing);
  });

  testWidgets('tapping a nav pill scrolls the profile down', (tester) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(tester, overrides: _overrides(deals: [_deal()]));

    expect(scrollController(tester).offset, 0);
    await tester.tap(find.text('Reviews').first);
    await tester.pumpAndSettle();

    expect(scrollController(tester).offset, greaterThan(0));
  });

  testWidgets('About text expands and collapses', (tester) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(
      tester,
      overrides: _overrides(
        venue: _venue(
          description:
              'A seaside room built around the day\'s catch, with an open '
              'kitchen, a charcoal grill at its centre and a rooftop terrace '
              'that faces the Arabian Sea. The menu changes with the boats, so '
              'expect a different catch every evening alongside the classics.',
        ),
      ),
    );

    expect(find.text('Read more'), findsOneWidget);
    expect(find.text('Show less'), findsNothing);

    await tester.ensureVisible(find.text('Read more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('menu preview shows grouped PKR prices and opens the dish sheet', (
    tester,
  ) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(tester, overrides: _overrides());

    expect(find.text('Garlic Prawns'), findsOneWidget);
    expect(find.text('Rs 2,450'), findsOneWidget);
    expect(find.text('Rs 690.50'), findsOneWidget);
    // Only the first two non-empty sections are previewed.
    expect(find.text('Gulab Jamun'), findsNothing);

    await tester.ensureVisible(find.text('Garlic Prawns'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garlic Prawns'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Served at the restaurant'), findsOneWidget);
  });

  testWidgets('deal rail shows the live deal and opens its detail', (
    tester,
  ) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(tester, overrides: _overrides(deals: [_deal()]));

    expect(find.text('1 active'), findsOneWidget);
    expect(find.text('Summer Seafood Feast'), findsOneWidget);

    await tester.ensureVisible(find.text('Summer Seafood Feast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Summer Seafood Feast'));
    await tester.pumpAndSettle();

    expect(find.byType(DealDetailScreen), findsOneWidget);
  });

  testWidgets('money is never invented for empty sections', (tester) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(
      tester,
      overrides: _overrides(
        venue: _venue(amenities: const [], reviewCount: 0, rating: 0),
        menu: _menu(sections: const []),
        feed: _feed(empty: true),
      ),
    );

    expect(
      find.text('This venue has not published a menu yet.'),
      findsOneWidget,
    );
    expect(
      find.text('No active deals at this venue right now.'),
      findsOneWidget,
    );
    expect(
      find.text('No reviews yet. Be the first to share your visit.'),
      findsOneWidget,
    );
    expect(find.text('No reviews yet'), findsOneWidget); // hero meta
    expect(find.byType(ExperienceCard), findsNothing);
  });

  testWidgets('experience cards surface upcoming events and are tappable', (
    tester,
  ) async {
    applyViewport(tester, 360, logicalHeight: 780);
    Dinner? tapped;
    await pumpProfile(
      tester,
      overrides: _overrides(
        events: [fixtureDinner(id: 'e9', title: 'Chef Counter')],
      ),
      onDinnerTap: (dinner) => tapped = dinner,
    );

    expect(find.text('Experiences'), findsWidgets);

    await tester.ensureVisible(find.byType(ExperienceCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExperienceCard));
    await tester.pumpAndSettle();

    expect(tapped?.id, 'e9');
  });

  testWidgets('gallery grid opens the full-screen viewer', (tester) async {
    applyViewport(tester, 360, logicalHeight: 780);
    await pumpProfile(
      tester,
      overrides: _overrides(
        venue: _venue(
          gallery: const [
            'assets/images/venue_bar.png',
            'assets/images/venue_interior.png',
            'assets/images/portrait_1.png',
            'assets/images/portrait_2.png',
          ],
        ),
      ),
    );

    expect(find.byType(GalleryGrid), findsOneWidget);

    await tester.ensureVisible(find.byType(GalleryGrid));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(GalleryGrid),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(GalleryViewer), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
  });

  testWidgets('no overflow at 320x568 with 1.3x text', (tester) async {
    applyViewport(tester, 320, logicalHeight: 568);
    applyTextScale(tester, 1.3);
    await pumpProfile(
      tester,
      overrides: _overrides(
        venue: _venue(gallery: const ['assets/images/venue_bar.png']),
        events: [fixtureDinner(id: 'e9', title: 'Chef Counter')],
        deals: [_deal()],
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
