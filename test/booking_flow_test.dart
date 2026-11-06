import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/api/api_exception.dart';
import 'package:dine_circle/models/booking.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/theme/app_theme.dart';
import 'package:dine_circle/screens/checkout/checkout_screen.dart';

import 'fake_repositories.dart';

/// A signed-in session so [currentUserProvider] resolves and checkout is
/// allowed to submit, without touching secure storage or the network.
class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  // The review step's recap rows trip RenderFlex overflow warnings in the
  // fixed headless viewport — layout warnings, not failures.
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

  // Walks Seats → Guest Info → Review, then taps "Confirm Booking".
  Future<void> reachPayAndSubmit(WidgetTester tester) async {
    await tester.tap(find.text('Continue — Guest Info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue — Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Booking'));
  }

  Widget checkout(
    FakeBookingsRepository bookings,
    void Function(Booking) done,
  ) {
    return ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(
          () => _StubSession(
            AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me')),
          ),
        ),
        bookingsRepositoryProvider.overrideWithValue(bookings),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: CheckoutScreen(
          dinner: fixtureDinner(id: 'e1', title: 'Omakase Night'),
          onComplete: done,
        ),
      ),
    );
  }

  testWidgets(
    'checkout posts exactly one join and hands back the server booking',
    (tester) async {
      usePhoneViewport(tester);
      tolerateOverflow();
      final bookings = FakeBookingsRepository();
      Booking? completed;

      await tester.pumpWidget(checkout(bookings, (b) => completed = b));
      await tester.pumpAndSettle();

      await reachPayAndSubmit(tester);
      // The button swaps to an indeterminate spinner on success (the real app
      // navigates away), so advance a couple frames instead of pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(bookings.joinCalls, 1);
      expect(bookings.lastSeats, 1);
      expect(completed, isNotNull);
      expect(completed!.id, 'b1');
      expect(completed!.status, BookingStatus.confirmed);
    },
  );

  testWidgets('an applied promo is forwarded so the server is the authority', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final bookings = FakeBookingsRepository();

    await tester.pumpWidget(checkout(bookings, (_) {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue — Guest Info'));
    await tester.pumpAndSettle();

    // Apply a valid promo, then continue to review & pay.
    await tester.enterText(
      find.widgetWithText(TextField, 'Enter promo code'),
      'WELCOME10',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('discount applied!'), findsOneWidget);

    await tester.tap(find.text('Continue — Review'));
    await tester.pumpAndSettle();

    // Phase 2a: Stripe removed — no payment step; confirm directly.
    await tester.tap(find.text('Confirm Booking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(bookings.joinCalls, 1);
    expect(bookings.lastPromo, 'WELCOME10');
  });

  testWidgets('a server error is surfaced inline and does not complete', (
    tester,
  ) async {
    usePhoneViewport(tester);
    tolerateOverflow();
    final bookings = FakeBookingsRepository(
      error: const ApiException(
        ApiErrorKind.network,
        message: 'That dinner is fully booked.',
      ),
    );
    Booking? completed;

    await tester.pumpWidget(checkout(bookings, (b) => completed = b));
    await tester.pumpAndSettle();

    await reachPayAndSubmit(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('That dinner is fully booked.'), findsOneWidget);
    expect(completed, isNull);
    expect(bookings.joinCalls, 0);

    // Drain the SnackBar's dismissal timer so teardown has nothing pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
