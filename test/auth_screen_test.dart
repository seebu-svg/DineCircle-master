import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/screens/auth/auth_screen.dart';
import 'package:dine_circle/theme/app_theme.dart';

import 'fake_repositories.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<(ProviderContainer, FakeSessionRepository)> pumpAuth(
    WidgetTester tester, {
    Object? repoError,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final repo = FakeSessionRepository(error: repoError);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const AuthScreen(),
        ),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AuthScreen)),
    );
    return (container, repo);
  }

  testWidgets('starts in sign-in mode with no name field', (tester) async {
    await pumpAuth(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('switching to create account reveals the name field', (
    tester,
  ) async {
    await pumpAuth(tester);

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('blank fields surface validation errors and skip the call', (
    tester,
  ) async {
    final (_, repo) = await pumpAuth(tester);

    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(repo.loginCalls, 0);
  });

  testWidgets('a valid sign-in establishes the session', (tester) async {
    final (container, repo) = await pumpAuth(tester);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'diner@example.com');
    await tester.enterText(fields.at(1), 'hunter2hunter2');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(repo.loginCalls, 1);
    final session = container.read(sessionControllerProvider).valueOrNull;
    expect(session?.signedIn, isTrue);
    expect(session?.userId, 'u1');
  });

  testWidgets('a short sign-up password is rejected client-side', (
    tester,
  ) async {
    final (_, repo) = await pumpAuth(tester);
    await tester.tap(find.text('Create account'));
    await tester.pump();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alex Rivera');
    await tester.enterText(fields.at(1), 'alex@example.com');
    await tester.enterText(fields.at(2), 'short');
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(repo.signUpCalls, 0);
  });

  testWidgets('a server error is surfaced inline', (tester) async {
    await pumpAuth(
      tester,
      repoError: Exception('Email or password is incorrect.'),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'diner@example.com');
    await tester.enterText(fields.at(1), 'hunter2hunter2');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    // Non-ApiException failures fall back to the generic connectivity message.
    expect(
      find.textContaining('Could not reach the server'),
      findsOneWidget,
    );
  });
}
