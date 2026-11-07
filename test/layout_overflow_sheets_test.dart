import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/models/booking.dart';
import 'package:dine_circle/models/safety.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/theme/app_theme.dart';
import 'package:dine_circle/screens/safety/report_sheet.dart';
import 'package:dine_circle/screens/settings/change_email_sheet.dart';
import 'package:dine_circle/screens/settings/change_password_sheet.dart';
import 'package:dine_circle/widgets/booking_check_in_sheet.dart';
import 'package:dine_circle/widgets/booking_receipt_sheet.dart';
import 'package:dine_circle/widgets/edit_profile_sheet.dart';

import 'fake_repositories.dart';
import 'support/overflow_harness.dart';

/// Overflow audit for every modal surface.
///
/// Sheets are opened through the same `show*Sheet()` helpers the app calls, so
/// they are laid out by a real modal route (Material ancestor, bottom-sheet
/// constraints, `viewInsets` padding) instead of being rendered bare, a bare
/// `TextField`/`ListTile` would report a missing Material ancestor rather than
/// a layout defect.
void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  List<Override> overrides() => [
    authReadyProvider.overrideWithValue(true),
    sessionControllerProvider.overrideWith(
      () => _StubSession(
        AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me')),
      ),
    ),
    usersRepositoryProvider.overrideWithValue(FakeUsersRepository()),
    safetyRepositoryProvider.overrideWithValue(FakeSafetyRepository()),
  ];

  /// Opens [open] as a modal sheet and settles.
  Future<void> pumpSheet(
    WidgetTester tester,
    void Function(BuildContext context) open, {
    List<Override>? extra,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides(), ...?extra],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: _SheetLauncher(open: open),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final user = fixtureHost(id: 'me', name: 'Me');
  final booking = fixtureBooking(
    dinner: fixtureDinner(id: 'e1', title: 'Test Dinner'),
    user: fixtureHost(id: 'me', name: 'Me'),
    status: BookingStatus.confirmed,
  );

  final sheets = <String, void Function(BuildContext)>{
    'ChangeEmailSheet': (context) => showChangeEmailSheet(context, user),
    'ChangePasswordSheet': (context) => showChangePasswordSheet(context),
    'EditProfileSheet': (context) => showEditProfileSheet(context, user),
    'BookingCheckInSheet': (context) =>
        showBookingCheckInSheet(context, booking),
    'BookingReceiptSheet': (context) =>
        showBookingReceiptSheet(context, booking),
    'ReportSheet': (context) =>
        ReportSheet.show(context, ReportTargetType.user, 'u1'),
  };

  sheets.forEach((label, open) {
    group('Sheet: $label', () {
      for (final width in kAuditWidths) {
        for (final scale in kAuditTextScales) {
          testWidgets('${width.toInt()}px × ${scale}x', (tester) async {
            applyViewport(tester, width);
            applyTextScale(tester, scale);
            final capture = startOverflowCapture();

            await pumpSheet(tester, open);

            capture.restore();
            expectNoOverflow(
              capture,
              'Sheet: $label at ${width.toInt()}px, ${scale}x text',
            );
          });
        }
      }
    });
  });

  // Sheets that host a form must stay usable while the keyboard is up: the
  // sheet is pushed up by `viewInsets` and only the scrollable area shrinks.
  final formSheets = <String, void Function(BuildContext)>{
    'ChangeEmailSheet': (context) => showChangeEmailSheet(context, user),
    'ChangePasswordSheet': (context) => showChangePasswordSheet(context),
    'EditProfileSheet': (context) => showEditProfileSheet(context, user),
    'ReportSheet': (context) =>
        ReportSheet.show(context, ReportTargetType.user, 'u1'),
  };

  formSheets.forEach((label, open) {
    group('Sheet + keyboard: $label', () {
      for (final width in const [320.0, 390.0]) {
        for (final scale in const [1.0, 2.0]) {
          testWidgets('${width.toInt()}px × ${scale}x + keyboard', (
            tester,
          ) async {
            applyViewport(tester, width);
            applyTextScale(tester, scale);
            applyKeyboardInset(tester, 300);
            final capture = startOverflowCapture();

            await pumpSheet(tester, open);

            capture.restore();
            expectNoOverflow(
              capture,
              'Sheet: $label with keyboard at ${width.toInt()}px, ${scale}x',
            );
          });
        }
      }
    });
  });
}

class _SheetLauncher extends StatefulWidget {
  const _SheetLauncher({required this.open});

  final void Function(BuildContext context) open;

  @override
  State<_SheetLauncher> createState() => _SheetLauncherState();
}

class _SheetLauncherState extends State<_SheetLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}
