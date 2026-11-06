import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/api/dto/user_dto.dart';
import 'package:dine_circle/models/user_profile.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/screens/settings/settings_screen.dart';
import 'package:dine_circle/theme/app_theme.dart';

import 'fake_repositories.dart';

const String _tokenKey = 'dinecircle.auth.token';

const _diner = UserDto(
  id: 'u1',
  name: 'Test Diner',
  role: 'user',
  email: 'diner@example.com',
  city: 'Karachi',
);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Renders Settings for a restored (signed-in) session and returns the
  /// container plus the two fakes the account surfaces write through.
  Future<(ProviderContainer, FakeSessionRepository, FakeUsersRepository)>
  pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final storage = InMemorySecureStorage();
    await storage.write(key: _tokenKey, value: 'tok');
    final sessionRepo = FakeSessionRepository(user: _diner);
    final usersRepo = FakeUsersRepository(
      meResult: const UserProfile(id: 'u1', name: 'Test Diner'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          sessionRepositoryProvider.overrideWithValue(sessionRepo),
          usersRepositoryProvider.overrideWithValue(usersRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(); // bootstrap restores the stored token

    final container = ProviderScope.containerOf(
      tester.element(find.text('Settings')),
    );
    // Sanity: we are signed in with the email-carrying profile.
    expect(
      container.read(sessionControllerProvider).requireValue.signedIn,
      true,
    );
    return (container, sessionRepo, usersRepo);
  }

  testWidgets('shows the minimal P1 row set and no phone/OTP surfaces', (
    tester,
  ) async {
    await pumpSettings(tester);

    for (final row in [
      'Personal Information',
      'Change Email',
      'Change Password',
      'Food Preferences',
      'Location',
      'Privacy & Security',
      'Log Out',
      'Logout All Devices',
      'Delete Account',
    ]) {
      expect(find.text(row), findsOneWidget, reason: '$row row missing');
    }
    // Phone/OTP exists server-side but is deliberately not exposed in P1.
    expect(find.text('Change Phone'), findsNothing);
    expect(find.textContaining('Phone'), findsNothing);
    // The personal-information subtitle carries the account email.
    expect(find.text('diner@example.com'), findsOneWidget);
  });

  testWidgets('change-password sheet validates then calls the controller', (
    tester,
  ) async {
    final (container, sessionRepo, _) = await pumpSettings(tester);

    await tester.tap(find.text('Change Password'));
    await tester.pumpAndSettle();

    // Blank submission surfaces the inline validation without a network call.
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your current password.'), findsOneWidget);
    expect(sessionRepo.changePasswordCalls, 0);

    await tester.enterText(
      find.byKey(const Key('currentPasswordField')),
      'old12345',
    );
    await tester.enterText(
      find.byKey(const Key('newPasswordField')),
      'new1234567',
    );
    await tester.enterText(
      find.byKey(const Key('confirmPasswordField')),
      'different1',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(find.text('The new passwords do not match.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('confirmPasswordField')),
      'new1234567',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(sessionRepo.changePasswordCalls, 1);
    expect(sessionRepo.lastCurrentPassword, 'old12345');
    expect(sessionRepo.lastNewPassword, 'new1234567');
    expect(find.textContaining('Password changed.'), findsOneWidget);
    expect(
      container.read(sessionControllerProvider).requireValue.signedIn,
      isTrue,
    );
  });

  testWidgets('change-email sheet stages the challenge before confirming', (
    tester,
  ) async {
    final (container, sessionRepo, _) = await pumpSettings(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Change Email'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('newEmailField')),
      'moved@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('confirmPasswordEmailField')),
      'dinerpass',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(sessionRepo.requestEmailChangeCalls, 1);
    expect(sessionRepo.lastRequestedEmail, 'moved@example.com');
    // Still on the old address until the 6-digit code is confirmed.
    expect(
      container.read(sessionControllerProvider).requireValue.user!.email,
      'diner@example.com',
    );

    // The fake dev challenge surfaces its code; a wrong one is refused and
    // the sheet stays open with the server's copy.
    expect(find.textContaining('654321'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('emailCodeField')), '000000');
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(find.text('That code is not right. Try again.'), findsOneWidget);
    expect(
      container.read(sessionControllerProvider).requireValue.user!.email,
      'diner@example.com',
    );

    await tester.enterText(find.byKey(const Key('emailCodeField')), '654321');
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();

    expect(sessionRepo.confirmEmailChangeCalls, 2);
    expect(
      container.read(sessionControllerProvider).requireValue.user!.email,
      'moved@example.com',
    );
    expect(
      find.textContaining('Email updated to moved@example.com.'),
      findsOneWidget,
    );
  });

  testWidgets('privacy screen writes toggles through PATCH', (tester) async {
    final (_, _, usersRepo) = await pumpSettings(tester);

    await tester.tap(find.text('Privacy & Security'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('showFollowListSwitch')));
    await tester.pumpAndSettle();

    expect(usersRepo.patchSettingsCalls, 1);
    expect(usersRepo.lastSettingsPatch, {'showFollowList': false});
    // The switch re-reads the republished session: it stayed off.
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('showFollowListSwitch')))
          .value,
      isFalse,
    );
  });

  testWidgets('logout all devices clears the local session', (tester) async {
    final (container, sessionRepo, _) = await pumpSettings(tester);

    await tester.tap(find.text('Logout All Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Log out everywhere?'), findsOneWidget);

    await tester.tap(find.text('Log out all devices'));
    await tester.pumpAndSettle();

    expect(sessionRepo.logoutAllCalls, 1);
    expect(
      container.read(sessionControllerProvider).requireValue.signedIn,
      isFalse,
    );
  });

  testWidgets('delete account requires the password and signs out', (
    tester,
  ) async {
    final (container, sessionRepo, _) = await pumpSettings(tester);

    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();

    // Confirming without a password must not fire the request.
    // The button is disabled (onPressed=null) so the dialog stays open.
    expect(find.text('Delete forever'), findsOneWidget);
    expect(sessionRepo.deleteAccountCalls, 0);
    expect(
      container.read(sessionControllerProvider).requireValue.signedIn,
      isTrue,
    );

    // Enter the password in the still-open dialog and submit.
    await tester.enterText(
      find.byKey(const Key('deleteAccountPassword')),
      'dinerpass',
    );
    await tester.pump(); // rebuild the now-enabled Delete button
    await tester.tap(find.text('Delete forever'));
    // The cleared session swaps the screen for a spinner; don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(sessionRepo.deleteAccountCalls, 1);
    expect(sessionRepo.lastDeletePassword, 'dinerpass');
    expect(
      container.read(sessionControllerProvider).requireValue.signedIn,
      isFalse,
    );
  });
}
