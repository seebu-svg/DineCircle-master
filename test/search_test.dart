import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/saved_locations_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/screens/deals/deal_detail_screen.dart';
import 'package:dine_circle/screens/deals/deals_screen.dart';
import 'package:dine_circle/screens/detail/dinner_detail_screen.dart';
import 'package:dine_circle/screens/qr_menu/qr_menu_screen.dart';
import 'package:dine_circle/screens/restaurant_detail/restaurant_detail_screen.dart';
import 'package:dine_circle/screens/search/search_result_tiles.dart';
import 'package:dine_circle/screens/search/universal_search_screen.dart';
import 'package:dine_circle/screens/user_profile/user_profile_screen.dart';
import 'package:dine_circle/services/recent_searches_store.dart';
import 'package:dine_circle/theme/app_theme.dart';

import 'fake_repositories.dart';

/// A signed-in session so the viewer-scoped providers resolve without touching
/// secure storage or `/auth/me`.
class _SignedInSession extends SessionController {
  @override
  Future<AppSession> build() async =>
      AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me'));
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  List<Override> overrides({
    required FakeSearchRepository search,
    FakeDealsRepository? deals,
    FakeRestaurantsRepository? restaurants,
    FakeUsersRepository? users,
    FakeEventsRepository? events,
    InMemorySecureStorage? storage,
  }) => [
    secureStorageProvider.overrideWithValue(storage ?? InMemorySecureStorage()),
    sessionControllerProvider.overrideWith(_SignedInSession.new),
    searchRepositoryProvider.overrideWithValue(search),
    dealsRepositoryProvider.overrideWithValue(
      deals ?? FakeDealsRepository(),
    ),
    restaurantsRepositoryProvider.overrideWithValue(
      restaurants ?? FakeRestaurantsRepository(),
    ),
    usersRepositoryProvider.overrideWithValue(users ?? FakeUsersRepository()),
    eventsRepositoryProvider.overrideWithValue(events ?? FakeEventsRepository()),
    supportedCityNamesProvider.overrideWithValue(const [
      'Karachi',
      'Lahore',
      'Islamabad',
    ]),
  ];

  Widget app({
    required FakeSearchRepository search,
    FakeDealsRepository? deals,
    FakeRestaurantsRepository? restaurants,
    FakeUsersRepository? users,
    FakeEventsRepository? events,
    InMemorySecureStorage? storage,
    Widget? home,
  }) => ProviderScope(
    overrides: overrides(
      search: search,
      deals: deals,
      restaurants: restaurants,
      users: users,
      events: events,
      storage: storage,
    ),
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: home ?? const UniversalSearchScreen(),
    ),
  );

  /// A viewport tall enough that every result section is laid out without
  /// scrolling; a lazily built `ListView` would otherwise skip lower sections.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> submit(WidgetTester tester, String term) async {
    await tester.enterText(find.byKey(const Key('searchField')), term);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  group('idle state', () {
    testWidgets('renders stored recent searches and Clear empties the store', (
      tester,
    ) async {
      final storage = InMemorySecureStorage();
      await storage.write(
        key: RecentSearchesStore.storageKey,
        value: jsonEncode([
          {'q': 'sushi'},
          {'q': 'brunch'},
        ]),
      );

      await tester.pumpWidget(
        app(search: FakeSearchRepository(), storage: storage),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('searchIdle')), findsOneWidget);
      expect(find.text('sushi'), findsOneWidget);
      expect(find.text('brunch'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clearRecentSearches')));
      await tester.pumpAndSettle();

      expect(find.text('sushi'), findsNothing);
      expect(await storage.read(key: RecentSearchesStore.storageKey), isNull);
    });
  });

  group('typeahead', () {
    testWidgets('two characters issue exactly one suggest after the debounce', (
      tester,
    ) async {
      final search = FakeSearchRepository(
        suggestions: [fixtureSuggestion('Sushi House')],
      );
      await tester.pumpWidget(app(search: search));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('searchField')), 'su');
      // The debounce has not elapsed: no request, and no search either.
      expect(search.suggestCalls, 0);
      expect(search.searchCalls, 0);

      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();

      expect(search.suggestCalls, 1);
      expect(find.text('Sushi House'), findsOneWidget);
    });
  });

  group('results', () {
    testWidgets('submitting renders every category with counts and rows', (
      tester,
    ) async {
      useTallViewport(tester);
      final search = FakeSearchRepository(
        restaurants: [fixtureRestaurant()],
        menu: [fixtureMenuItem()],
        deals: [fixtureDeal()],
        experiences: [fixtureDinner()],
        hosts: [fixtureHost()],
      );

      await tester.pumpWidget(app(search: search));
      await tester.pumpAndSettle();
      await submit(tester, 'sushi');

      expect(search.searchCalls, 1);
      expect(search.lastFilters?.query, 'sushi');

      // One section per category, each carrying its own total.
      expect(find.text('Restaurants (1)'), findsOneWidget);
      expect(find.text('Dishes (1)'), findsOneWidget);
      expect(find.text('Deals (1)'), findsOneWidget);
      expect(find.text('Experiences (1)'), findsOneWidget);
      expect(find.text('Hosts (1)'), findsOneWidget);

      // One row per fixture.
      expect(find.byKey(const Key('searchTile_r1')), findsOneWidget);
      expect(find.byKey(const Key('searchTile_m1')), findsOneWidget);
      expect(find.byKey(const Key('searchTile_d1')), findsOneWidget);
      expect(find.byKey(const Key('searchTile_e1')), findsOneWidget);
      expect(find.byKey(const Key('searchTile_h1')), findsOneWidget);

      // A restaurant row opens the shared restaurant profile.
      await tester.tap(find.byKey(const Key('searchTile_r1')));
      await tester.pump();
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
    });

    testWidgets('zero results show the empty state', (tester) async {
      final search = FakeSearchRepository();
      await tester.pumpWidget(app(search: search));
      await tester.pumpAndSettle();
      await submit(tester, 'nothing-matches');

      expect(find.byKey(const Key('searchEmptyState')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed search surfaces an error and retry recovers', (
      tester,
    ) async {
      final search = FakeSearchRepository(restaurants: [fixtureRestaurant()])
        ..failNext = true;
      await tester.pumpWidget(app(search: search));
      await tester.pumpAndSettle();
      await submit(tester, 'sushi');

      expect(find.byKey(const Key('searchRetry')), findsOneWidget);
      expect(find.byKey(const Key('searchTile_r1')), findsNothing);

      await tester.tap(find.byKey(const Key('searchRetry')));
      await tester.pumpAndSettle();

      expect(search.searchCalls, 2);
      expect(find.byKey(const Key('searchTile_r1')), findsOneWidget);
    });

    testWidgets('load more requests page 2 and appends without duplicates', (
      tester,
    ) async {
      useTallViewport(tester);
      final search = FakeSearchRepository(
        restaurants: [
          for (var i = 1; i <= 12; i++)
            fixtureRestaurant(id: 'r$i', name: 'Venue $i'),
        ],
      );

      await tester.pumpWidget(app(search: search));
      await tester.pumpAndSettle();
      await submit(tester, 'venue');

      expect(search.lastPage, 1);
      expect(find.byKey(const Key('searchTile_r10')), findsOneWidget);
      expect(find.byKey(const Key('searchTile_r11')), findsNothing);

      await tester.tap(find.byKey(const Key('searchLoadMore_restaurants')));
      await tester.pumpAndSettle();

      expect(search.lastPage, 2);
      expect(find.byKey(const Key('searchTile_r11')), findsOneWidget);
      expect(find.byKey(const Key('searchTile_r12')), findsOneWidget);
      // Appended, not repeated.
      expect(find.byKey(const Key('searchTile_r1')), findsOneWidget);
    });
  });

  group('filters', () {
    testWidgets('applying city, type and availability re-queries', (
      tester,
    ) async {
      final search = FakeSearchRepository(restaurants: [fixtureRestaurant()]);
      await tester.pumpWidget(app(search: search));
      await tester.pumpAndSettle();
      await submit(tester, 'sushi');

      await tester.tap(find.byKey(const Key('searchFilterButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('searchFilterSheet')), findsOneWidget);

      final sheet = find.byKey(const Key('searchFilterSheet'));
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Karachi')),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Fine dining')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('searchAvailabilitySwitch')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('searchApplyFilters')));
      await tester.pumpAndSettle();

      final applied = search.lastFilters!;
      expect(applied.city, 'Karachi');
      expect(applied.venueType, 'fine dining');
      expect(applied.availableOnly, isTrue);
      expect(applied.activeCount, 3);
      expect(search.searchCalls, 2);

      // The badge mirrors the active count.
      expect(
        find.descendant(
          of: find.byKey(const Key('searchFilterButton')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );

      // Reset + Apply clears every filter and re-queries once more.
      await tester.tap(find.byKey(const Key('searchFilterButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('searchResetFilters')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('searchApplyFilters')));
      await tester.pumpAndSettle();

      expect(search.lastFilters!.activeCount, 0);
      expect(
        find.descendant(
          of: find.byKey(const Key('searchFilterButton')),
          matching: find.text('3'),
        ),
        findsNothing,
      );
    });
  });

  group('navigation', () {
    /// Pushes [hit] through the same switch every result tile uses, so the
    /// assertion proves the routing table rather than the host screen.
    Future<void> open(WidgetTester tester, Object hit) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(search: FakeSearchRepository()),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => openSearchHit(context, hit),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
    }

    testWidgets('a dish hit opens the venue menu seeded with the dish', (
      tester,
    ) async {
      await open(tester, fixtureMenuItem());
      expect(find.byType(QrMenuScreen), findsOneWidget);
      expect(
        tester.widget<QrMenuScreen>(find.byType(QrMenuScreen)).initialQuery,
        'Truffle Sushi',
      );
    });

    testWidgets('a deal hit opens the deal detail screen', (tester) async {
      await open(tester, fixtureDeal());
      expect(find.byType(DealDetailScreen), findsOneWidget);
    });

    testWidgets('an experience hit opens the dinner detail screen', (
      tester,
    ) async {
      await open(tester, fixtureDinner());
      expect(find.byType(DinnerDetailScreen), findsOneWidget);
    });

    testWidgets('a host hit opens the user profile screen', (tester) async {
      await open(tester, fixtureHost());
      expect(find.byType(UserProfileScreen), findsOneWidget);
    });
  });

  group('recent searches', () {
    testWidgets('a repeated query keeps one entry, newest first', (
      tester,
    ) async {
      final storage = InMemorySecureStorage();
      final search = FakeSearchRepository(restaurants: [fixtureRestaurant()]);
      await tester.pumpWidget(app(search: search, storage: storage));
      await tester.pumpAndSettle();

      await submit(tester, 'sushi');
      await submit(tester, 'pizza');
      await submit(tester, 'sushi');

      final stored = await RecentSearchesStore(storage).load();
      expect(stored, ['sushi', 'pizza']);
    });
  });

  group('Deals tab', () {
    testWidgets('sends the term to the server instead of filtering locally', (
      tester,
    ) async {
      final deals = FakeDealsRepository(
        deals: [
          fixtureDeal(id: 'd1', title: 'Sunday brunch', restaurantName: 'Cafe A'),
          fixtureDeal(id: 'd2', title: 'Ramen night', restaurantName: 'Noodle B'),
        ],
      );

      await tester.pumpWidget(
        app(search: FakeSearchRepository(), deals: deals, home: const DealsScreen()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'ramen');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(deals.lastQuery, 'ramen');
      expect(find.text('Ramen night'), findsOneWidget);
      expect(find.text('Sunday brunch'), findsNothing);
    });
  });

  group('QrMenuScreen seeding', () {
    testWidgets('initialQuery pre-fills the dish search', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(search: FakeSearchRepository()),
          child: const MaterialApp(
            home: QrMenuScreen(restaurantId: 'r1', initialQuery: 'truffle'),
          ),
        ),
      );
      await tester.pump();

      final fields = find.descendant(
        of: find.byType(QrMenuScreen),
        matching: find.byType(TextField),
      );
      expect(fields, findsWidgets);
      expect(
        tester.widget<TextField>(fields.first).controller?.text,
        'truffle',
      );
    });
  });
}
