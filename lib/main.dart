import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/preferences/preferences_screen.dart';
import 'providers/app_prefs_provider.dart';
import 'providers/session_provider.dart';
import 'app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log configuration in debug mode
  if (AppConfig.enableDebugLogging) {
    debugPrint('🔧 App Configuration:');
    AppConfig.toDebugMap().forEach((key, value) {
      debugPrint('   $key: $value');
    });
  }
  
  runApp(const ProviderScope(child: DineCircleApp()));

  // The API lives on a public host that may be asleep when the app is opened.
  // Probe it now, while the user is still reading the splash screen, so the
  // cold start lands here instead of on their first sign-in tap.
  unawaited(ApiClient().warmUp());
}

class DineCircleApp extends StatelessWidget {
  const DineCircleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DineCircle',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppFlow(),
    );
  }
}

/// Root flow. Shows the branded splash until the user taps Get Started, then a
/// purely session-driven gate: onboarding/auth while signed out, the taste
/// preferences for a freshly signed-in user, and finally the app shell. All
/// first-run flags persist, so this never replays for a returning user.
class AppFlow extends ConsumerStatefulWidget {
  const AppFlow({super.key});

  @override
  ConsumerState<AppFlow> createState() => _AppFlowState();
}

class _AppFlowState extends ConsumerState<AppFlow> {
  bool _userStarted = false;

  @override
  Widget build(BuildContext context) {
    if (!_userStarted) {
      return SplashScreen(
        onGetStarted: () => setState(() => _userStarted = true),
      );
    }

    final session = ref.watch(sessionControllerProvider);
    final prefs = ref.watch(appPrefsProvider);

    // Keep the splash up while the stored token is still being validated.
    if (session.isLoading) {
      return SplashScreen(onGetStarted: () {});
    }

    final signedIn = session.valueOrNull?.signedIn ?? false;
    if (!signedIn) {
      return prefs.onboardingComplete
          ? const AuthScreen()
          : OnboardingScreen(
              onComplete: () =>
                  ref.read(appPrefsProvider.notifier).completeOnboarding(),
            );
    }

    if (!prefs.preferencesComplete) {
      return PreferencesScreen(
        onComplete: () =>
            ref.read(appPrefsProvider.notifier).completePreferences(),
      );
    }

    return const AppShell();
  }
}
