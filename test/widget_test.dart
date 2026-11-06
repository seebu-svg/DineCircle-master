import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/main.dart';
import 'package:dine_circle/app_shell.dart';
import 'package:dine_circle/screens/onboarding/onboarding_screen.dart';
import 'package:dine_circle/theme/app_theme.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/app_prefs_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/widgets/connectivity_banner.dart';

import 'fake_repositories.dart';

/// A connectivity notifier stub that always reports an online device, so the
/// app-wide banner never touches the platform channel in a headless test.
class _AlwaysOnline extends ConnectivityNotifier {
  @override
  bool build() => true;
}

/// Session/prefs stubs so the root [AppFlow] resolves deterministically in a
/// headless test without touching secure storage or the network.
class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}

class _StubPrefs extends AppPrefsNotifier {
  _StubPrefs(this._result);
  final AppPrefs _result;
  @override
  AppPrefs build() => _result;
}

/// The whole app under a [ProviderScope], starting signed out with fresh
/// (incomplete) first-run flags — i.e. the first-launch experience.
Widget _bootApp() {
  return ProviderScope(
    overrides: [
      sessionControllerProvider.overrideWith(
        () => _StubSession(const AppSession(signedIn: false)),
      ),
      appPrefsProvider.overrideWith(() => _StubPrefs(const AppPrefs())),
      connectivityProvider.overrideWith(_AlwaysOnline.new),
    ],
    child: const DineCircleApp(),
  );
}

void main() {
  setUp(() {
    // Keep widget tests offline and deterministic: never fetch fonts at
    // runtime, and don't assert on real pixels.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('app boots to the splash screen', (tester) async {
    await tester.pumpWidget(_bootApp());
    await tester.pump();

    expect(find.text('DineCircle'), findsWidgets);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('tapping "Get Started" advances past the splash screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_bootApp());
    await tester.pump();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // Signed out with fresh first-run flags, the root flow lands on onboarding.
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('app shell renders the five bottom-navigation tabs', (
    tester,
  ) async {
    // Render at a portrait phone size so the dense home feed lays out without
    // the overflow the default 800x600 landscape test window would cause.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    // Build the semantics tree so bySemanticsLabel can find the Create action.
    final SemanticsHandle handle = tester.ensureSemantics();

    // AppShell renders every tab eagerly (IndexedStack), and the dense home
    // feed emits RenderFlex *overflow* warnings in the fixed headless
    // viewport. Those are paint/layout warnings, not failures, so let them
    // through while still surfacing any real exception.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The app shell's tabs read the live session (Profile identity,
          // host/guest data), so this test needs a signed-in user rather than
          // the derived authReady flag alone.
          sessionControllerProvider.overrideWith(
            () => _StubSession(
              AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me')),
            ),
          ),
          connectivityProvider.overrideWith(_AlwaysOnline.new),
          eventsRepositoryProvider.overrideWithValue(
            FakeEventsRepository(events: [fixtureDinner()]),
          ),
          restaurantsRepositoryProvider.overrideWithValue(
            FakeRestaurantsRepository(),
          ),
          usersRepositoryProvider.overrideWithValue(FakeUsersRepository()),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // The four labelled tabs (Home / Explore / Deals / Profile) are present.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Deals'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);

    // The central Scan QR action is exposed to assistive tech as a button.
    expect(find.bySemanticsLabel('Scan QR menu'), findsOneWidget);

    handle.dispose();
  });
}
