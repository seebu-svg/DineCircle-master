import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client_provider.dart';

/// Which first-run surfaces the user has already passed. Persisted to secure
/// storage so onboarding and the preferences picker are never replayed.
class AppPrefs {
  const AppPrefs({
    this.onboardingComplete = false,
    this.preferencesComplete = false,
  });

  final bool onboardingComplete;
  final bool preferencesComplete;

  AppPrefs copyWith({bool? onboardingComplete, bool? preferencesComplete}) =>
      AppPrefs(
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        preferencesComplete: preferencesComplete ?? this.preferencesComplete,
      );
}

final appPrefsProvider = NotifierProvider<AppPrefsNotifier, AppPrefs>(
  AppPrefsNotifier.new,
);

class AppPrefsNotifier extends Notifier<AppPrefs> {
  static const _onboardingKey = 'dinecircle.prefs.onboarding';
  static const _preferencesKey = 'dinecircle.prefs.completed';

  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);

  @override
  AppPrefs build() {
    // Flags live in secure storage; hydrate them just after the first frame.
    // AppFlow keeps the splash visible while the session restores, which covers
    // this short window, so the onboarding screen never flashes for a returning
    // user.
    var alive = true;
    ref.onDispose(() => alive = false);
    Future<void>.microtask(() async {
      late final AppPrefs loaded;
      try {
        final values = await _storage.readAll();
        loaded = AppPrefs(
          onboardingComplete: values[_onboardingKey] == 'true',
          preferencesComplete: values[_preferencesKey] == 'true',
        );
      } catch (_) {
        // Storage unavailable (e.g. unsupported platform) — keep defaults.
        return;
      }
      if (alive) state = loaded;
    });
    return const AppPrefs();
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingComplete: true);
    await _write(_onboardingKey);
  }

  Future<void> completePreferences() async {
    state = state.copyWith(preferencesComplete: true);
    await _write(_preferencesKey);
  }

  Future<void> _write(String key) async {
    try {
      await _storage.write(key: key, value: 'true');
    } catch (_) {
      // Best-effort persistence; the in-memory state already advanced.
    }
  }
}
