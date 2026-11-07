import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the device currently has any network connection.
///
/// Backed by [connectivity_plus]. Kept as a tiny notifier so any screen can
/// watch it (the app-wide [ConnectivityBanner] does) without each one wiring up
/// its own stream subscription.
final connectivityProvider = NotifierProvider<ConnectivityNotifier, bool>(
  ConnectivityNotifier.new,
);

class ConnectivityNotifier extends Notifier<bool> {
  @override
  bool build() {
    final connectivity = Connectivity();
    final sub = connectivity.onConnectivityChanged.listen((results) {
      state = _resolve(results);
    });
    ref.onDispose(sub.cancel);
    // Seed the initial value asynchronously so the first build isn't blocked.
    unawaited(_seed(connectivity));
    return true;
  }

  Future<void> _seed(Connectivity connectivity) async {
    try {
      state = _resolve(await connectivity.checkConnectivity());
    } catch (_) {
      // Plugin unavailable (e.g. unsupported platform), assume online.
      state = true;
    }
  }

  static bool _resolve(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
}

/// A slim banner shown at the top of the shell when the device is offline.
///
/// It renders as a 0-height widget while online so it never disturbs the
/// layout; when offline it slides in a warning strip. Screens continue to show
/// their cached content underneath.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider);
    if (online) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You are offline. Reconnect to load the latest dinners.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
