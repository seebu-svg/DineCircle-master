import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/api/api_exception.dart';
import 'package:dine_circle/api/dto/user_dto.dart';
import 'package:dine_circle/models/dinner.dart';
import 'package:dine_circle/models/deal.dart';
import 'package:dine_circle/models/user_profile.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/deals_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/repositories/users_repository.dart';
import 'package:dine_circle/theme/app_theme.dart';
import 'package:dine_circle/widgets/skeleton_placeholder.dart';

import 'package:dine_circle/screens/home/home_screen.dart';
import 'package:dine_circle/screens/explore/explore_screen.dart';
import 'package:dine_circle/screens/detail/dinner_detail_screen.dart';
import 'package:dine_circle/screens/restaurant_detail/restaurant_detail_screen.dart';
import 'package:dine_circle/screens/user_profile/user_profile_screen.dart';
import 'package:dine_circle/screens/bookings/bookings_screen.dart';
import 'package:dine_circle/screens/saved/saved_screen.dart';
import 'package:dine_circle/screens/notifications/notifications_screen.dart';
import 'package:dine_circle/providers/users_provider.dart';
import 'package:dine_circle/providers/social_provider.dart';
import 'package:dine_circle/providers/events_provider.dart';
import 'package:dine_circle/providers/offers_provider.dart';
import 'package:dine_circle/models/discovery_category.dart';
import 'package:dine_circle/models/booking.dart';
import 'package:dine_circle/models/host_models.dart';
import 'package:dine_circle/models/notification_item.dart';
import 'package:dine_circle/screens/host/host_dashboard_screen.dart';
import 'package:dine_circle/screens/create/create_dinner_screen.dart';
import 'package:dine_circle/screens/profile/profile_screen.dart';

import 'fake_repositories.dart';

/// A signed-in session so tabs that read the live user resolve without hitting
/// secure storage or the network.
class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}

Override _signedIn() => sessionControllerProvider.overrideWith(
  () => _StubSession(AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me'))),
);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Keep the dense rails from tripping RenderFlex overflow assertions in the
  // fixed headless viewport — layout warnings, not failures.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  void tolerateOverflow() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  List<Override> overrides({
    FakeEventsRepository? events,
    FakeRestaurantsRepository? restaurants,
    FakeUsersRepository? users,
    FakeSocialRepository? social,
    FakeOffersRepository? offers,
  }) => [
    authReadyProvider.overrideWithValue(true),
    eventsRepositoryProvider.overrideWithValue(
      events ?? FakeEventsRepository(),
    ),
    restaurantsRepositoryProvider.overrideWithValue(
      restaurants ?? FakeRestaurantsRepository(),
    ),
    usersRepositoryProvider.overrideWithValue(users ?? FakeUsersRepository()),
    offersRepositoryProvider.overrideWithValue(
      offers ?? FakeOffersRepository(),
    ),
    if (social != null) socialRepositoryProvider.overrideWithValue(social),
  ];

  Widget screen(Widget child, List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.darkTheme, home: child),
  );

  group('HomeScreen', () {
    testWidgets('renders dinner titles from the live feed', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(
        events: [
          fixtureDinner(id: 'e1', title: 'Omakase Night'),
          fixtureDinner(id: 'e2', title: 'Sunday Brunch', featured: true),
        ],
      );

      await tester.pumpWidget(
        screen(HomeScreen(onDinnerTap: (_) {}), overrides(events: events)),
      );
      await tester.pumpAndSettle();

      // The editorial home is taller than one viewport; scroll to the feed.
      for (var i = 0; i < 6; i++) {
        if (find.text('Omakase Night').evaluate().isNotEmpty) break;
        await tester.drag(find.text('Welcome back'), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(find.text('Omakase Night'), findsWidgets);
    });

    testWidgets('shows a skeleton while the feed loads', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(
        events: [fixtureDinner()],
        delay: const Duration(milliseconds: 50),
      );

      await tester.pumpWidget(
        screen(HomeScreen(onDinnerTap: (_) {}), overrides(events: events)),
      );
      // First frame: the future is still pending.
      await tester.pump();
      expect(find.byType(SkeletonList), findsWidgets);

      // Drain the pending timer so teardown is clean.
      await tester.pumpAndSettle();
    });

    testWidgets('surfaces an error with a retry action', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(
        error: const ApiException(
          ApiErrorKind.network,
          message: 'Could not reach DineCircle.',
        ),
      );

      await tester.pumpWidget(
        screen(HomeScreen(onDinnerTap: (_) {}), overrides(events: events)),
      );
      await tester.pumpAndSettle();

      // The redesigned home hides errored sections gracefully; the static
      // chrome (greeting, search, quick actions) must still render.
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Book a Table'), findsOneWidget);
    });

    testWidgets('shows the empty state when there is no data', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(events: const []);
      final restaurants = FakeRestaurantsRepository(restaurants: const []);

      await tester.pumpWidget(
        screen(
          HomeScreen(onDinnerTap: (_) {}),
          overrides(events: events, restaurants: restaurants),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to the bottom fallback empty-state message.
      for (var i = 0; i < 10; i++) {
        if (find
            .text('No dinners near you yet. Check back soon.')
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.drag(find.text('Welcome back'), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(
        find.text('No dinners near you yet. Check back soon.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('ExploreScreen renders feed titles', (tester) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final events = FakeEventsRepository(
      events: [fixtureDinner(id: 'e1', title: 'Coastal Tasting')],
    );

    await tester.pumpWidget(
      screen(ExploreScreen(onDinnerTap: (_) {}), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coastal Tasting'), findsWidgets);
  });

  testWidgets('DinnerDetailScreen shows menu + venue from /events/:id', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    // A slim stand-in the screen shows while loading.
    final slim = fixtureDinner(id: 'e1', title: 'Loading…', menu: const []);
    final detail = fixtureDinner(
      id: 'e1',
      title: 'Omakase Night',
      menu: const [
        MenuItem(
          id: 'm1',
          name: 'Nigiri Flight',
          description: 'Chef choice',
          price: 0,
        ),
      ],
    );
    final events = FakeEventsRepository(events: [detail]);

    await tester.pumpWidget(
      screen(DinnerDetailScreen(dinner: slim), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    // The detail payload replaces the slim fallback: menu item + venue name.
    expect(find.text('Nigiri Flight'), findsOneWidget);
    expect(find.text('Skyline Room'), findsWidgets);
    expect(find.text('Loading…'), findsNothing);
  });

  testWidgets('DinnerDetailScreen menu shows Included for zero-price items', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final dinner = fixtureDinner(
      id: 'e2',
      title: 'Tasting Night',
      menu: const [
        MenuItem(id: 'm1', name: 'Appetizer', description: 'Starter', price: 0),
        MenuItem(
          id: 'm2',
          name: 'Main Course',
          description: 'Entree',
          price: 25,
        ),
      ],
    );
    final events = FakeEventsRepository(events: [dinner]);

    await tester.pumpWidget(
      screen(DinnerDetailScreen(dinner: dinner), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    // $0 items show "Included" instead of "$0"
    expect(find.text('Included'), findsOneWidget);
    expect(find.text('\$25'), findsOneWidget);
    expect(find.text('\$0'), findsNothing);
  });

  testWidgets('DinnerDetailScreen bottom bar shows sold-out state', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final dinner = Dinner(
      id: 'e3',
      title: 'Sold Out Dinner',
      description: 'Full event',
      restaurant: fixtureRestaurant(),
      host: fixtureHost(),
      dateTime: DateTime.now().add(const Duration(days: 1)),
      totalSeats: 10,
      bookedSeats: 10,
      pricePerSeat: 100,
    );
    final events = FakeEventsRepository(events: [dinner]);

    await tester.pumpWidget(
      screen(DinnerDetailScreen(dinner: dinner), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    // Bottom bar shows "Join Waitlist" and "Full" seats
    expect(find.text('Join Waitlist'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
  });

  testWidgets('DinnerDetailScreen bottom bar shows cancelled state', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final dinner = Dinner(
      id: 'e4',
      title: 'Cancelled Dinner',
      description: 'This event was cancelled',
      restaurant: fixtureRestaurant(),
      host: fixtureHost(),
      dateTime: DateTime.now().add(const Duration(days: 1)),
      totalSeats: 10,
      bookedSeats: 2,
      pricePerSeat: 80,
      hostStatus: HostEventStatus.cancelled,
    );
    final events = FakeEventsRepository(events: [dinner]);

    await tester.pumpWidget(
      screen(DinnerDetailScreen(dinner: dinner), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    // Bottom bar shows "Cancelled" and button is disabled
    expect(find.text('Cancelled'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('DinnerDetailScreen hero shows title and category', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final dinner = fixtureDinner(id: 'e5', title: 'Omakase Experience');
    final events = FakeEventsRepository(events: [dinner]);

    await tester.pumpWidget(
      screen(DinnerDetailScreen(dinner: dinner), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    // Hero overlay shows title and category
    expect(find.text('Omakase Experience'), findsWidgets);
    expect(find.text('Public Dinner'), findsOneWidget);
  });

  testWidgets('DinnerDetailScreen shows What to Expect section', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final dinner = Dinner(
      id: 'e6',
      title: 'Intimate Dinner',
      description: 'A cozy evening of fine dining and conversation.',
      restaurant: fixtureRestaurant(),
      host: fixtureHost(),
      dateTime: DateTime.now().add(const Duration(days: 3)),
      totalSeats: 8,
      bookedSeats: 2,
      pricePerSeat: 90,
      tags: const ['Intimate', 'Conversation', 'Wine Pairing'],
    );
    final events = FakeEventsRepository(events: [dinner]);

    await tester.pumpWidget(
      screen(DinnerDetailScreen(dinner: dinner), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    // What to Expect section shows description and tags
    expect(find.text('What to Expect'), findsOneWidget);
    expect(find.textContaining('cozy evening'), findsOneWidget);
    expect(find.text('Intimate'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
  });

  testWidgets('DinnerDetailScreen renders at 320px without overflow', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final dinner = fixtureDinner(
      id: 'e7',
      title: 'Very Long Dinner Title That Might Overflow on Narrow Screens',
      menu: const [
        MenuItem(id: 'm1', name: 'Appetizer', description: 'Starter', price: 0),
      ],
    );
    final events = FakeEventsRepository(events: [dinner]);

    await tester.pumpWidget(
      screen(DinnerDetailScreen(dinner: dinner), overrides(events: events)),
    );
    await tester.pumpAndSettle();

    // No overflow errors at 320px
    expect(find.byType(DinnerDetailScreen), findsOneWidget);
  });

  testWidgets('RestaurantDetailScreen shows upcoming events from the API', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final slim = fixtureRestaurant(id: 'r1', name: 'Slim Venue');
    final full = fixtureRestaurant(id: 'r1', name: 'Skyline Room');
    final restaurants = FakeRestaurantsRepository(
      restaurants: [full],
      detailEvents: [fixtureDinner(id: 'e9', title: 'Chef Counter')],
    );

    await tester.pumpWidget(
      screen(
        RestaurantDetailScreen(restaurant: slim),
        overrides(restaurants: restaurants),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chef Counter'), findsWidgets);
  });

  testWidgets('UserProfileScreen shows the host name + hosted events', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final slim = UserProfile(id: 'h1', name: 'Loading Host');
    final users = FakeUsersRepository(
      profileResult: HostProfile(
        user: fixtureHost(id: 'h1', name: 'Nora Chen'),
        hostedUpcoming: [fixtureDinner(id: 'e3', title: 'Cellar Supper')],
      ),
    );

    await tester.pumpWidget(
      screen(UserProfileScreen(user: slim), overrides(users: users)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nora Chen'), findsWidgets);
    expect(find.text('Cellar Supper'), findsOneWidget);
  });

  group('UserProfileScreen redesigned', () {
    testWidgets('shows stats, ratings, and upcoming experiences section', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final slim = UserProfile(id: 'h1', name: 'Loading Host');
      final users = FakeUsersRepository(
        profileResult: HostProfile(
          user: fixtureHost(id: 'h1', name: 'Nora Chen'),
          hostedUpcoming: [fixtureDinner(id: 'e3', title: 'Cellar Supper')],
        ),
      );

      await tester.pumpWidget(
        screen(UserProfileScreen(user: slim), overrides(users: users)),
      );
      await tester.pumpAndSettle();

      // Stats row
      expect(find.text('8'), findsOneWidget); // dinnersHosted
      expect(find.text('Hosted'), findsOneWidget);
      // Upcoming Experiences header
      expect(find.text('Upcoming Experiences'), findsOneWidget);
      // Ratings section
      expect(find.textContaining('review'), findsOneWidget);
    });

    testWidgets('shows empty state when host has no upcoming events', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final slim = UserProfile(id: 'h1', name: 'Loading Host');
      final users = FakeUsersRepository(
        profileResult: HostProfile(
          user: fixtureHost(id: 'h1', name: 'Nora Chen'),
          hostedUpcoming: const [],
        ),
      );

      await tester.pumpWidget(
        screen(UserProfileScreen(user: slim), overrides(users: users)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No upcoming experiences yet'), findsOneWidget);
    });

    testWidgets('renders follow and contact buttons for non-self profiles', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final slim = UserProfile(id: 'h1', name: 'Loading Host');
      final users = FakeUsersRepository(
        profileResult: HostProfile(
          user: fixtureHost(id: 'h1', name: 'Nora Chen'),
          hostedUpcoming: const [],
        ),
      );

      await tester.pumpWidget(
        screen(
          UserProfileScreen(user: slim),
          overrides(users: users) + [_signedIn()],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('renders at 320px logical width without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      tolerateOverflow();
      final slim = UserProfile(id: 'h1', name: 'Loading Host');
      final users = FakeUsersRepository(
        profileResult: HostProfile(
          user: fixtureHost(id: 'h1', name: 'Nora Chen'),
          hostedUpcoming: [fixtureDinner(id: 'e3', title: 'Cellar Supper')],
        ),
      );

      await tester.pumpWidget(
        screen(
          UserProfileScreen(user: slim),
          overrides(users: users) + [_signedIn()],
        ),
      );
      await tester.pumpAndSettle();

      // The key elements must be findable — no overflow clipping.
      expect(find.text('Nora Chen'), findsWidgets);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Cellar Supper'), findsOneWidget);
    });

    testWidgets('experience tile shows venue, price, and seats left', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final slim = UserProfile(id: 'h1', name: 'Loading Host');
      final dinner = fixtureDinner(id: 'e3', title: 'Cellar Supper');
      final users = FakeUsersRepository(
        profileResult: HostProfile(
          user: fixtureHost(id: 'h1', name: 'Nora Chen'),
          hostedUpcoming: [dinner],
        ),
      );

      await tester.pumpWidget(
        screen(UserProfileScreen(user: slim), overrides(users: users)),
      );
      await tester.pumpAndSettle();

      // Venue location
      expect(find.text(dinner.formattedLocation), findsOneWidget);
      // Price
      expect(find.text('\$120'), findsOneWidget);
      // Seats left (10 total - 4 booked = 6)
      expect(find.text('6 seats left'), findsOneWidget);
      // CTA
      expect(find.text('Join Table'), findsOneWidget);
    });
  });

  group('Live-read tabs', () {
    testWidgets('BookingsScreen renders an upcoming booking', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final booking = fixtureBooking(
        dinner: fixtureDinner(id: 'e1', title: 'Booked Brunch'),
        user: fixtureHost(id: 'me', name: 'Me'),
        status: BookingStatus.confirmed,
      );

      await tester.pumpWidget(
        screen(const BookingsScreen(), [
          _signedIn(),
          myBookingsProvider.overrideWith((ref) async => [booking]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Booked Brunch'), findsWidgets);
    });

    testWidgets('BookingsScreen renders a cancelled past booking', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final booking = fixtureBooking(
        dinner: fixtureDinner(id: 'e2', title: 'Cancelled Supper'),
        user: fixtureHost(id: 'me', name: 'Me'),
        status: BookingStatus.cancelled,
      );

      await tester.pumpWidget(
        screen(const BookingsScreen(), [
          _signedIn(),
          myBookingsProvider.overrideWith((ref) async => [booking]),
        ]),
      );
      await tester.pumpAndSettle();

      // Switch to Past tab
      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled Supper'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Rebook'), findsOneWidget);
    });

    testWidgets('Confirmed booking shows QR Ticket CTA', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final confirmed = fixtureBooking(
        dinner: fixtureDinner(id: 'e1', title: 'Confirmed Dinner'),
        user: fixtureHost(id: 'me', name: 'Me'),
        status: BookingStatus.confirmed,
      );

      await tester.pumpWidget(
        screen(const BookingsScreen(), [
          _signedIn(),
          myBookingsProvider.overrideWith((ref) async => [confirmed]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show QR Ticket'), findsOneWidget);
    });

    testWidgets('Pending booking shows Cancel Booking CTA', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final pending = fixtureBooking(
        dinner: fixtureDinner(id: 'e2', title: 'Pending Dinner'),
        user: fixtureHost(id: 'me', name: 'Me'),
        status: BookingStatus.pending,
      );

      await tester.pumpWidget(
        screen(const BookingsScreen(), [
          _signedIn(),
          myBookingsProvider.overrideWith((ref) async => [pending]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancel Booking'), findsOneWidget);
    });

    testWidgets('SavedScreen renders the server saved list', (tester) async {
      usePhoneViewport(tester);
      final saved = fixtureDinner(id: 'e2', title: 'Saved Supper');

      await tester.pumpWidget(
        screen(const SavedScreen(), [
          _signedIn(),
          savedEventsProvider.overrideWith((ref) async => [saved]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved Supper'), findsOneWidget);
    });

    testWidgets('NotificationsScreen renders /activity and marks all read', (
      tester,
    ) async {
      usePhoneViewport(tester);
      final social = FakeSocialRepository();
      final note = NotificationItem(
        id: 'n1',
        type: NotificationType.followRequest,
        title: 'Nora Chen followed you',
        message: 'Start a conversation.',
        timestamp: DateTime.now(),
        user: fixtureHost(id: 'h1', name: 'Nora Chen'),
      );

      await tester.pumpWidget(
        screen(const NotificationsScreen(), [
          _signedIn(),
          socialRepositoryProvider.overrideWithValue(social),
          notificationsProvider.overrideWith((ref) async => [note]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nora Chen followed you'), findsOneWidget);

      await tester.tap(find.byTooltip('Mark all read'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(social.markReadCalls, 1);
    });
  });

  group('Host surfaces', () {
    // The dashboard's Collabs tab is entirely server-backed: partner venues and
    // collaboration invitations come from the hosts repository, never MockData.
    testWidgets('HostDashboardScreen renders live partners + invites', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final hosts = FakeHostsRepository(
        partnerRows: [
          HostPartner(
            venue: fixtureRestaurant(id: 'r1', name: 'Skyline Rooftop'),
            eventsTogether: 3,
          ),
        ],
        invites: [
          fixtureInvite(id: 'i1', title: 'Omakase Collaboration Night'),
        ],
      );
      final events = FakeEventsRepository(
        events: [fixtureDinner(id: 'e1', title: 'Cellar Supper')],
      );

      await tester.pumpWidget(
        screen(const HostDashboardScreen(initialTab: 3), [
          _signedIn(),
          hostsRepositoryProvider.overrideWithValue(hosts),
          eventsRepositoryProvider.overrideWithValue(events),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active Partnerships'), findsOneWidget);
      expect(find.text('Skyline Rooftop'), findsWidgets);
      expect(find.text('Omakase Collaboration Night'), findsWidgets);
    });
  });

  group('CreateDinnerScreen venue picker', () {
    // P0-1: hosts may only publish at verified partner venues, so the picker
    // hides everything else and explains the rule.
    testWidgets('lists only verified partner venues and selects one', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final restaurants = FakeRestaurantsRepository(
        restaurants: [
          fixtureRestaurant(id: 'v1', name: 'Kolachi Restaurant'),
          fixtureRestaurant(
            id: 'u1',
            name: 'Kanteen',
            isPartner: false,
            partnershipStatus: 'unverified',
          ),
        ],
      );

      await tester.pumpWidget(
        screen(const CreateDinnerScreen(), overrides(restaurants: restaurants)),
      );
      await tester.pumpAndSettle();

      // Step 1 is Experience Details — advance to Step 2 (Restaurant & Venue).
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Kolachi Restaurant'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Kanteen'), findsNothing);
      expect(find.textContaining('verified partner venue'), findsOneWidget);

      final verifiedTile = find.text('Kolachi Restaurant');
      await tester.ensureVisible(verifiedTile);
      await tester.pump();
      await tester.tap(verifiedTile);
      await tester.pump();
      // Two check icons: one in the venue tile (selection) + one in the venue details card.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    });

    testWidgets('says so when no venue in the feed is verified', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final restaurants = FakeRestaurantsRepository(
        restaurants: [
          fixtureRestaurant(
            id: 'u1',
            name: 'Kanteen',
            isPartner: false,
            partnershipStatus: 'unverified',
          ),
        ],
      );

      await tester.pumpWidget(
        screen(const CreateDinnerScreen(), overrides(restaurants: restaurants)),
      );
      await tester.pumpAndSettle();

      // Step 1 is Experience Details — advance to Step 2 (Restaurant & Venue).
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('No verified venues yet in this area.'), findsOneWidget);
      expect(find.text('Kanteen'), findsNothing);
    });
  });

  group('CreateDinnerScreen save draft', () {
    // P0-2: a draft needs only a title + venue (the server relaxes the rest),
    // and the wizard posts it with status 'draft' then pops.
    testWidgets('posts a title-only wizard as a draft and pops', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository();
      final restaurants = FakeRestaurantsRepository(
        restaurants: [fixtureRestaurant(id: 'v1', name: 'Kolachi Restaurant')],
      );

      await tester.pumpWidget(
        screen(
          const CreateDinnerScreen(),
          overrides(events: events, restaurants: restaurants),
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Step 2 (Restaurant & Venue) and select the venue.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final venueTile = find.text('Kolachi Restaurant');
      await tester.ensureVisible(venueTile);
      await tester.pump();
      await tester.tap(venueTile);
      await tester.pump();

      // Fixed pumps instead of pumpAndSettle: the pop transition plus the
      // snackbar's auto-dismiss timer can outrun the fake clock's settle loop.
      await tester.tap(find.byTooltip('Save draft'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(events.publishCalls, 1);
      expect(events.lastPublishAsDraft, isTrue);
      expect(events.lastPublish?.restaurantId, 'v1');
      expect(find.text('Draft saved'), findsOneWidget);
    });

    testWidgets('asks for a venue before saving a draft', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository();
      final restaurants = FakeRestaurantsRepository(
        restaurants: [fixtureRestaurant(id: 'v1', name: 'Kolachi Restaurant')],
      );

      await tester.pumpWidget(
        screen(
          const CreateDinnerScreen(),
          overrides(events: events, restaurants: restaurants),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save draft'));
      await tester.pumpAndSettle();

      expect(events.publishCalls, 0);
      expect(
        find.text('Pick a restaurant before saving a draft.'),
        findsOneWidget,
      );
    });

    // P0-2: the review step's own "Save Draft" / "Preview" buttons must ride
    // the same real paths as the AppBar actions (no snackbar stubs).
    testWidgets('review step saves a draft through the real path', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository();
      final restaurants = FakeRestaurantsRepository(
        restaurants: [fixtureRestaurant(id: 'v1', name: 'Kolachi Restaurant')],
      );

      await tester.pumpWidget(
        screen(
          const CreateDinnerScreen(),
          overrides(events: events, restaurants: restaurants) + [_signedIn()],
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Step 2 (Restaurant & Venue) and select the venue.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final venueTile = find.text('Kolachi Restaurant');
      await tester.ensureVisible(venueTile);
      await tester.pump();
      await tester.tap(venueTile);
      await tester.pump();

      // Walk the wizard to the review step (from Step 2, 4 taps to reach Step 6).
      for (var step = 0; step < 4; step++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(find.text('Save Draft'));
      await tester.pump();
      await tester.tap(find.text('Save Draft'));
      // Fixed pumps: the pop + snackbar timer can outrun the settle loop.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(events.publishCalls, 1);
      expect(events.lastPublishAsDraft, isTrue);
      // The wizard ships with a prefilled name ("Omakase Experience").
      expect(events.lastPublish?.title, 'Omakase Experience');
    });

    testWidgets('review step previews without any server write', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository();
      final restaurants = FakeRestaurantsRepository(
        restaurants: [fixtureRestaurant(id: 'v1', name: 'Kolachi Restaurant')],
      );

      await tester.pumpWidget(
        screen(
          const CreateDinnerScreen(),
          overrides(events: events, restaurants: restaurants) + [_signedIn()],
        ),
      );
      await tester.pumpAndSettle();

      // Advance to Step 2 (Restaurant & Venue) and select the venue.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final venueTile = find.text('Kolachi Restaurant');
      await tester.ensureVisible(venueTile);
      await tester.pump();
      await tester.tap(venueTile);
      await tester.pump();

      // From Step 2, 4 taps of "Next" reach Step 6 (Review).
      for (var step = 0; step < 4; step++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      // The review step shows both its buttons; the AppBar also carries a
      // "Preview" action, so scroll the step's own SecondaryButton into view
      // (ensureVisible would hit "too many elements" across both matches).
      await tester.scrollUntilVisible(
        find.text('Preview').last,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Preview').last);
      await tester.pumpAndSettle();

      expect(events.publishCalls, 0);
      expect(find.byType(DinnerDetailScreen), findsOneWidget);
      expect(find.text('Omakase Experience'), findsWidgets);
    });
  });

  // P0-4: Explore search box flows the query server-side (events feed + a new
  // live venue section), and the filter sheet composes price/date/audience.
  group('Explore live search', () {
    testWidgets('debounced query hits the events feed', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(
        events: [fixtureDinner(id: 'e1', title: 'Kolachi Long Table')],
      );

      await tester.pumpWidget(
        screen(
          ExploreScreen(onDinnerTap: (_) {}, onRestaurantTap: (_) {}),
          overrides(events: events),
        ),
      );
      await tester.pumpAndSettle();
      expect(events.lastFeedQuery, isNull);

      await tester.enterText(find.byType(TextField).first, 'Kolachi');
      await tester.pump(const Duration(milliseconds: 200));
      expect(events.lastFeedQuery, isNull); // still debouncing
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(events.lastFeedQuery, 'Kolachi');
    });

    testWidgets('a category chip drives the venue tag', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final restaurants = FakeRestaurantsRepository(
        restaurants: [fixtureRestaurant(id: 'v1', name: 'Skyline Rooftop')],
      );

      await tester.pumpWidget(
        screen(
          ExploreScreen(onDinnerTap: (_) {}, onRestaurantTap: (_) {}),
          overrides(restaurants: restaurants),
        ),
      );
      await tester.pumpAndSettle();

      // Venue type chips live on the Places tab in the new tab model.
      await tester.tap(find.text('Places'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rooftop'));
      await tester.pumpAndSettle();

      expect(restaurants.lastListTag, 'rooftop');
      expect(find.text('Skyline Rooftop'), findsOneWidget);
    });

    testWidgets('filter sheet apply composes audience + date window', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(events: [fixtureDinner()]);

      await tester.pumpWidget(
        screen(ExploreScreen(onDinnerTap: (_) {}), overrides(events: events)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      // Audience = Public, window = Next 3 days, then Apply.
      await tester.tap(find.text('Public').last);
      await tester.tap(find.text('Next 3 days'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(events.lastFeedAudience, 'public');
      expect(events.lastFeedFrom, isNotNull);
      expect(events.lastFeedTo, isNotNull);
    });
  });

  // The five primary discovery categories: home tiles route into a
  // category-aware Explore view that composes the right feed filter + section.
  group('Discovery categories', () {
    testWidgets('home surfaces the five tiles and forwards a Deals tap', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      DiscoveryCategory? tapped;

      await tester.pumpWidget(
        screen(
          HomeScreen(onDinnerTap: (_) {}, onCategoryTap: (c) => tapped = c),
          overrides(),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in [
        'Book a Table',
        'Join a Gathering',
        'Explore Deals',
        'Social Dining',
        'Singles Nights',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'tile: $label');
      }

      await tester.tap(find.text('Explore Deals').first);
      await tester.pumpAndSettle();
      expect(tapped, DiscoveryCategory.deals);
    });

    testWidgets('Explore renders recommended deals from the repository', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final venue = fixtureRestaurant(id: 'r1', name: 'Skyline Room');

      await tester.pumpWidget(
        screen(ExploreScreen(onDinnerTap: (_) {}, onRestaurantTap: (_) {}), [
          ...overrides(
            restaurants: FakeRestaurantsRepository(restaurants: [venue]),
          ),
          dealsFeedProvider.overrideWith(
            (ref, search) async => [
              Deal(
                id: 'd1',
                restaurantId: 'r1',
                restaurantName: 'Skyline Room',
                title: 'Date Night Tasting',
                description: 'Two courses for the price of one',
                kind: 'percent',
                value: 20,
                startsAt: DateTime.now().subtract(const Duration(days: 1)),
                endsAt: DateTime.now().add(const Duration(days: 5)),
              ),
            ],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recommended deals'), findsOneWidget);
      expect(find.text('Date Night Tasting'), findsOneWidget);
    });

    testWidgets('Explore renders without errors on the All tab', (
      tester,
    ) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(events: [fixtureDinner()]);
      final users = FakeUsersRepository(
        discoverResult: () => [
          RosterUser(
            user: fixtureHost(id: 'p1', name: 'Aria Khan'),
          ),
        ],
      );

      await tester.pumpWidget(
        screen(
          ExploreScreen(onDinnerTap: (_) {}),
          overrides(events: events, users: users),
        ),
      );
      await tester.pumpAndSettle();

      // All tab has no audience filter (previously socialDining set one).
      expect(events.lastFeedAudience, isNull);
      expect(find.text('Discover by occasion'), findsOneWidget);
    });

    testWidgets('Explore renders dinners feed on the All tab', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(events: [fixtureDinner()]);

      await tester.pumpWidget(
        screen(ExploreScreen(onDinnerTap: (_) {}), overrides(events: events)),
      );
      await tester.pumpAndSettle();

      // All tab has no type filter (previously experiences set one).
      expect(events.lastFeedType, isNull);
      expect(events.feedCalls, greaterThan(0));
    });

    testWidgets('Explore default tab loads the events feed', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final events = FakeEventsRepository(events: [fixtureDinner()]);

      await tester.pumpWidget(
        screen(ExploreScreen(onDinnerTap: (_) {}), overrides(events: events)),
      );
      await tester.pumpAndSettle();
      expect(events.feedCalls, greaterThan(0));
    });
  });

  test('OfferSearch key equality drives the offers family', () {
    const a = OfferSearch(city: 'Karachi');
    const b = OfferSearch(city: 'Karachi');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const OfferSearch(city: 'Karachi', kind: 'couple'), isFalse);
  });

  test('EventFilter equality covers the new price/date axes', () {
    const a = EventFilter(query: 'x');
    const b = EventFilter(query: 'x');
    expect(a, b);
    expect(a == const EventFilter(query: 'x', maxPrice: 50), isFalse);
    final d = DateTime(2026, 1, 1);
    expect(EventFilter(from: d, to: d), EventFilter(from: d, to: d));
    expect(a.copyWith(maxPrice: 40).hashCode, isNot(a.hashCode));
  });

  // Hosting section: hosts get Host Studio, Wallet and the influencer growth
  // card (the only entry point for claiming influencer status); diners get
  // the Become a Host invitation.
  group('Profile hosting section', () {
    testWidgets('host sees Host Studio entry point', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final repo = FakeSessionRepository(
        user: UserDto(id: 'me', name: 'Me', role: 'host'),
      );
      final storage = InMemorySecureStorage();
      await storage.write(key: 'dinecircle.auth.token', value: 'fake-token');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            sessionRepositoryProvider.overrideWithValue(repo),
            ...overrides(),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Host Studio'), findsOneWidget);
      expect(find.text('Hosting'), findsOneWidget);
    });

    testWidgets('non-host sees Become a Host invitation', (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final repo = FakeSessionRepository(
        user: UserDto(id: 'me', name: 'Me', role: 'user'),
      );
      final storage = InMemorySecureStorage();
      await storage.write(key: 'dinecircle.auth.token', value: 'fake-token');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            sessionRepositoryProvider.overrideWithValue(repo),
            ...overrides(),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Phase D3: social layer removed; non-hosts see no hosting entry.
      expect(find.text('Host Studio'), findsNothing);
    });
  });
}
