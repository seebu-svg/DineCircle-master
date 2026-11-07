import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/models/booking.dart';
import 'package:dine_circle/models/host_models.dart';
import 'package:dine_circle/models/safety.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/hosts_provider.dart';
import 'package:dine_circle/providers/safety_provider.dart';
import 'package:dine_circle/providers/saved_locations_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/providers/users_provider.dart';
import 'package:dine_circle/repositories/users_repository.dart';
import 'package:dine_circle/theme/app_theme.dart';

// Screens under audit
import 'package:dine_circle/screens/auth/auth_screen.dart';
import 'package:dine_circle/screens/booking_confirmed/booking_confirmed_screen.dart';
import 'package:dine_circle/screens/checkout/checkout_screen.dart';
import 'package:dine_circle/screens/help/help_screen.dart';
import 'package:dine_circle/screens/host/analytics_screen.dart';
import 'package:dine_circle/screens/host/event_manage_screen.dart';
import 'package:dine_circle/screens/location/location_settings_screen.dart';
import 'package:dine_circle/screens/location/saved_locations_screen.dart';
import 'package:dine_circle/screens/onboarding/onboarding_screen.dart';
import 'package:dine_circle/screens/preferences/food_preferences_screen.dart';
import 'package:dine_circle/screens/preferences/preferences_screen.dart';
import 'package:dine_circle/screens/restaurant_detail/restaurant_detail_screen.dart';
import 'package:dine_circle/screens/safety/blocked_users_screen.dart';
import 'package:dine_circle/screens/safety/my_reports_screen.dart';
import 'package:dine_circle/screens/settings/privacy_settings_screen.dart';
import 'package:dine_circle/screens/settings/settings_screen.dart';
import 'package:dine_circle/screens/splash/splash_screen.dart';
import 'package:dine_circle/screens/support/feedback_form_screen.dart';
import 'package:dine_circle/screens/tables/my_tables_screen.dart';
import 'package:dine_circle/screens/user_profile/user_profile_screen.dart';

import 'fake_repositories.dart';

/// Extended overflow detection harness, covers the remaining screens not
/// included in the original [layout_overflow_test.dart].
///
/// Matrix: each screen × 5 widths × 3 text scales = 15 test cases per screen.
void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ── Helpers ────────────────────────────────────────────────────────────

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

  void setViewport(WidgetTester tester, double logicalWidth) {
    const dpr = 3.0;
    final h = logicalWidth * 2.0;
    tester.view.physicalSize = Size(logicalWidth * dpr, h * dpr);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  void setTextScale(WidgetTester tester, double scale) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Override signedIn() => sessionControllerProvider.overrideWith(
    () =>
        _StubSession(AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me'))),
  );

  List<Override> baseOverrides() => [
    authReadyProvider.overrideWithValue(true),
    eventsRepositoryProvider.overrideWithValue(
      FakeEventsRepository(events: [fixtureDinner()]),
    ),
    restaurantsRepositoryProvider.overrideWithValue(
      FakeRestaurantsRepository(),
    ),
    usersRepositoryProvider.overrideWithValue(FakeUsersRepository()),
    offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
  ];

  Widget app(Widget child, List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.darkTheme, home: child),
  );

  const widths = [320.0, 360.0, 390.0, 430.0, 600.0];
  const textScales = [1.0, 1.3, 2.0];

  /// Runs the standard overflow matrix for [label] rendering [child].
  void runMatrix(String label, Widget child, List<Override> overrides) {
    group('Overflow: $label', () {
      for (final w in widths) {
        for (final s in textScales) {
          testWidgets('${w.toInt()}px × ${s}x', (tester) async {
            setViewport(tester, w);
            setTextScale(tester, s);
            final cap = captureOverflow();
            await tester.pumpWidget(
              app(child, [...baseOverrides(), ...overrides]),
            );
            await tester.pumpAndSettle();
            cap.restore();
            expect(
              cap.errors,
              isEmpty,
              reason: 'Overflow at ${w.toInt()}px, ${s}x text',
            );
          });
        }
      }
    });
  }

  // ── Group 1: Plain widgets (no/minimal providers) ─────────────────────

  runMatrix('OnboardingScreen', OnboardingScreen(onComplete: () {}), []);

  runMatrix('SplashScreen', SplashScreen(onGetStarted: () {}), []);

  runMatrix('MyTablesScreen', const MyTablesScreen(), []);

  // ── Group 2: Screens needing auth/session overrides ───────────────────

  runMatrix('AuthScreen', const AuthScreen(), [signedIn()]);

  runMatrix(
    'BookingConfirmedScreen',
    BookingConfirmedScreen(dinner: fixtureDinner()),
    [signedIn()],
  );

  // With a confirmed booking the screen renders the pass card instead of the
  // empty-state placeholder, the path a guest actually lands on after paying.
  final passDinner = fixtureDinner();
  runMatrix(
    'BookingConfirmedScreen (pass card)',
    BookingConfirmedScreen(
      dinner: passDinner,
      booking: fixtureBooking(
        dinner: passDinner,
        user: fixtureHost(id: 'me', name: 'Me'),
      ),
    ),
    [signedIn()],
  );

  runMatrix('FoodPreferencesScreen', const FoodPreferencesScreen(), [
    signedIn(),
  ]);

  runMatrix('SettingsScreen', const SettingsScreen(), [signedIn()]);

  runMatrix('PrivacySettingsScreen', const PrivacySettingsScreen(), [
    signedIn(),
  ]);

  runMatrix('LocationSettingsScreen', const LocationSettingsScreen(), [
    signedIn(),
  ]);

  // ── Group 3: Safety screens ────────────────────────────────────────────

  final fakeSafety = FakeSafetyRepository(
    blocked: [
      const BlockedUser(id: 'u1', name: 'Blocked User', handle: 'blocked1'),
    ],
    reports: [
      const ReportItem(
        id: 'r1',
        reference: 'RP-TEST',
        targetType: ReportTargetType.user,
        targetId: 'u1',
        reason: ReportReason.spam,
        description: 'Test',
        status: ReportStatus.pending,
        createdAt: null,
      ),
    ],
    feedback: const [],
  );

  runMatrix('HelpScreen', const HelpScreen(), [
    signedIn(),
    safetyRepositoryProvider.overrideWithValue(fakeSafety),
    myFeedbackProvider.overrideWith((ref) async => const []),
  ]);

  runMatrix('BlockedUsersScreen', const BlockedUsersScreen(), [
    signedIn(),
    safetyRepositoryProvider.overrideWithValue(fakeSafety),
    blockedUsersProvider.overrideWith((ref) async => fakeSafety.blocked),
  ]);

  runMatrix('MyReportsScreen', const MyReportsScreen(), [
    signedIn(),
    safetyRepositoryProvider.overrideWithValue(fakeSafety),
    myReportsProvider.overrideWith((ref) async => fakeSafety.reports),
  ]);

  runMatrix('FeedbackFormScreen', const FeedbackFormScreen(), [
    signedIn(),
    safetyRepositoryProvider.overrideWithValue(fakeSafety),
    myFeedbackProvider.overrideWith((ref) async => const []),
  ]);

  // ReportSheet, ChangeEmailSheet and ChangePasswordSheet are intentionally
  // absent here: they are bottom sheets, not screens, and mounting them as
  // `MaterialApp.home` has no Material ancestor, so TextField/RadioListTile
  // throw "No Material widget found" instead of reporting a layout defect.
  // They run the same 5 widths x 3 scales matrix,plus keyboard-insert cases,
  // through their real `show*Sheet()` hosts in layout_overflow_sheets_test.dart.

  // ── Group 4: Complex screens ──────────────────────────────────────────

  runMatrix('CheckoutScreen', CheckoutScreen(dinner: fixtureDinner()), [
    signedIn(),
  ]);

  final testRestaurant = fixtureRestaurant();
  runMatrix(
    'RestaurantDetailScreen',
    RestaurantDetailScreen(restaurant: testRestaurant),
    [
      signedIn(),
      restaurantsRepositoryProvider.overrideWithValue(
        FakeRestaurantsRepository(
          restaurants: [testRestaurant],
          detailEvents: [fixtureDinner()],
        ),
      ),
    ],
  );

  runMatrix('EventManageScreen', EventManageScreen(dinner: fixtureDinner()), [
    signedIn(),
    eventGuestsProvider.overrideWith((ref, _) async => <Booking>[]),
  ]);

  final testHost = fixtureHost(id: 'me', name: 'Me');
  runMatrix('UserProfileScreen', UserProfileScreen(user: testHost), [
    signedIn(),
    userProfileProvider.overrideWith(
      (ref, _) async => HostProfile(user: testHost),
    ),
  ]);

  runMatrix('AnalyticsScreen', const AnalyticsScreen(), [
    signedIn(),
    hostsRepositoryProvider.overrideWithValue(
      FakeHostsRepository(
        performanceRows: [
          HostEventStat(
            eventId: 'e1',
            title: 'Test',
            views: 10,
            seatsBooked: 5,
            bookings: 5,
            pending: 0,
            checkedIn: 3,
            gross: 500,
          ),
        ],
      ),
    ),
    myHostPerformanceProvider.overrideWith(
      (ref) async => [
        HostEventStat(
          eventId: 'e1',
          title: 'Test',
          views: 10,
          seatsBooked: 5,
          bookings: 5,
          pending: 0,
          checkedIn: 3,
          gross: 500,
        ),
      ],
    ),
  ]);

  runMatrix('SavedLocationsScreen', const SavedLocationsScreen(), [
    signedIn(),
    locationRepositoryProvider.overrideWithValue(FakeLocationRepository()),
    savedLocationsProvider.overrideWith((ref) => SavedLocationsNotifier(ref)),
  ]);

  runMatrix('PreferencesScreen', PreferencesScreen(onComplete: () {}), [
    signedIn(),
  ]);
}

// ── Stub helpers ───────────────────────────────────────────────────────────

class OverflowCapture {
  final List<String> errors = [];
  late void Function() _restore;
  void add(String error) => errors.add(error);
  void restore() => _restore();
}

class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}
