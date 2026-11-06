import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/api/dto/user_dto.dart';
import 'package:dine_circle/models/dinner.dart';
import 'package:dine_circle/models/booking.dart';
import 'package:dine_circle/models/host_models.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/providers/users_provider.dart';
import 'package:dine_circle/providers/social_provider.dart';
import 'package:dine_circle/theme/app_theme.dart';

import 'package:dine_circle/screens/home/home_screen.dart';
import 'package:dine_circle/screens/explore/explore_screen.dart';
import 'package:dine_circle/screens/bookings/bookings_screen.dart';
import 'package:dine_circle/screens/detail/dinner_detail_screen.dart';
import 'package:dine_circle/screens/create/create_dinner_screen.dart';
import 'package:dine_circle/screens/profile/profile_screen.dart';
import 'package:dine_circle/screens/saved/saved_screen.dart';
import 'package:dine_circle/screens/notifications/notifications_screen.dart';
import 'package:dine_circle/screens/host/host_dashboard_screen.dart';

import 'fake_repositories.dart';

/// Overflow detection harness — catches RenderFlex overflow at multiple
/// device widths and text scales.
///
/// This test renders each screen at widths [320, 360, 390, 430, 600] ×
/// textScale [1.0, 1.3, 2.0] and fails if any RenderFlex overflow is detected.
///
/// Unlike the existing tests that use tolerateOverflow() to swallow these
/// errors, this harness treats overflow as a failure condition.
void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Captures RenderFlex overflow errors and fails the test if any are found.
  OverflowCapture captureOverflow() {
    final capture = OverflowCapture();
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        capture.add(details.exceptionAsString());
      }
      original?.call(details);
    };
    capture._restore = () => FlutterError.onError = original;
    return capture;
  }

  /// Sets the test viewport to a specific logical width.
  void setViewport(WidgetTester tester, double logicalWidth) {
    const devicePixelRatio = 3.0;
    final logicalHeight = logicalWidth * 2.0; // 2:1 aspect ratio (portrait)
    tester.view.physicalSize = Size(
      logicalWidth * devicePixelRatio,
      logicalHeight * devicePixelRatio,
    );
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
  }

  /// Sets the text scale factor.
  void setTextScale(WidgetTester tester, double textScale) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Standard provider overrides for screens that read live data.
  List<Override> standardOverrides({
    FakeEventsRepository? events,
    FakeRestaurantsRepository? restaurants,
    FakeUsersRepository? users,
    FakeOffersRepository? offers,
  }) => [
    authReadyProvider.overrideWithValue(true),
    eventsRepositoryProvider.overrideWithValue(
      events ?? FakeEventsRepository(events: [fixtureDinner()]),
    ),
    restaurantsRepositoryProvider.overrideWithValue(
      restaurants ?? FakeRestaurantsRepository(),
    ),
    usersRepositoryProvider.overrideWithValue(users ?? FakeUsersRepository()),
    offersRepositoryProvider.overrideWithValue(
      offers ?? FakeOffersRepository(),
    ),
  ];

  /// Signed-in session override.
  Override signedIn() => sessionControllerProvider.overrideWith(
    () =>
        _StubSession(AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me'))),
  );

  Widget screen(Widget child, List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.darkTheme, home: child),
  );

  // Test matrix: widths × textScales
  const widths = [320.0, 360.0, 390.0, 430.0, 600.0];
  const textScales = [1.0, 1.3, 2.0];

  group('Overflow detection — HomeScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          final events = FakeEventsRepository(events: [fixtureDinner()]);
          await tester.pumpWidget(
            screen(
              HomeScreen(onDinnerTap: (_) {}),
              standardOverrides(events: events),
            ),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — BookingsScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          final booking = fixtureBooking(
            dinner: fixtureDinner(id: 'e1', title: 'Test Dinner'),
            user: fixtureHost(id: 'me', name: 'Me'),
            status: BookingStatus.confirmed,
          );

          await tester.pumpWidget(
            screen(const BookingsScreen(), [
              signedIn(),
              myBookingsProvider.overrideWith((ref) async => [booking]),
              ...standardOverrides(),
            ]),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — DinnerDetailScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          final dinner = fixtureDinner(
            id: 'e1',
            title: 'Test Dinner with a Very Long Title That Might Overflow',
            menu: const [
              MenuItem(
                id: 'm1',
                name: 'Appetizer',
                description: 'Starter',
                price: 0,
              ),
            ],
          );
          final events = FakeEventsRepository(events: [dinner]);

          await tester.pumpWidget(
            screen(
              DinnerDetailScreen(dinner: dinner),
              standardOverrides(events: events),
            ),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — CreateDinnerScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          final restaurants = FakeRestaurantsRepository(
            restaurants: [fixtureRestaurant(id: 'v1', name: 'Test Venue')],
          );

          await tester.pumpWidget(
            screen(
              const CreateDinnerScreen(),
              standardOverrides(restaurants: restaurants),
            ),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — ExploreScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          final events = FakeEventsRepository(events: [fixtureDinner()]);

          await tester.pumpWidget(
            screen(
              ExploreScreen(onDinnerTap: (_) {}),
              standardOverrides(events: events),
            ),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — ProfileScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          final repo = FakeSessionRepository(
            user: UserDto(id: 'me', name: 'Me', role: 'host'),
          );
          final storage = InMemorySecureStorage();
          await storage.write(
            key: 'dinecircle.auth.token',
            value: 'fake-token',
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                secureStorageProvider.overrideWithValue(storage),
                sessionRepositoryProvider.overrideWithValue(repo),
                ...standardOverrides(),
              ],
              child: MaterialApp(
                theme: AppTheme.darkTheme,
                home: const ProfileScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — SavedScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          await tester.pumpWidget(
            screen(const SavedScreen(), [
              signedIn(),
              savedEventsProvider.overrideWith(
                (ref) async => [fixtureDinner()],
              ),
              ...standardOverrides(),
            ]),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — NotificationsScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          await tester.pumpWidget(
            screen(const NotificationsScreen(), [
              signedIn(),
              activityProvider.overrideWith((ref) async => const []),
              ...standardOverrides(),
            ]),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });

  group('Overflow detection — HostDashboardScreen', () {
    for (final width in widths) {
      for (final textScale in textScales) {
        testWidgets('renders at ${width.toInt()}px width, ${textScale}x text', (
          tester,
        ) async {
          setViewport(tester, width);
          setTextScale(tester, textScale);
          final capture = captureOverflow();

          final hosts = FakeHostsRepository(
            partnerRows: [
              HostPartner(
                venue: fixtureRestaurant(id: 'r1', name: 'Test Venue'),
                eventsTogether: 3,
              ),
            ],
            invites: [fixtureInvite(id: 'i1', title: 'Test Invite')],
          );

          await tester.pumpWidget(
            screen(const HostDashboardScreen(initialTab: 3), [
              signedIn(),
              hostsRepositoryProvider.overrideWithValue(hosts),
              ...standardOverrides(),
            ]),
          );
          await tester.pumpAndSettle();

          capture.restore();
          expect(
            capture.errors,
            isEmpty,
            reason: 'Overflow at ${width.toInt()}px, ${textScale}x text',
          );
        });
      }
    }
  });
}

/// Captures RenderFlex overflow errors during a test.
class OverflowCapture {
  final List<String> errors = [];
  late void Function() _restore;

  void add(String error) => errors.add(error);
  void restore() => _restore();
}

/// Stub session for signed-in state.
class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}
