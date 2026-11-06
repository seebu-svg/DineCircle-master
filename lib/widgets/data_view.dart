import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import 'skeleton_placeholder.dart';

/// Consistent error panel with an optional retry action.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  String get _message => switch (error) {
    final ApiException e => e.message,
    _ => 'Something went wrong.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent "nothing here yet" panel.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    this.message = 'Nothing here yet.',
    this.icon = Icons.ramen_dining_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uniform loading / empty / error / data wrapper around an [AsyncValue].
///
/// Screens use this so every surface handles the four states identically. A
/// [value] that is still loading shows a [SkeletonList]; an error shows
/// [ErrorStateView] (with retry when [onRetry] is supplied); resolved data
/// that satisfies [isEmpty] shows [emptyMessage]; otherwise [builder] renders.
class DataView<T> extends StatelessWidget {
  const DataView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.emptyMessage,
    this.emptyWidget,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final String? emptyMessage;
  final Widget? emptyWidget;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: false,
      loading: () => const SkeletonList(),
      error: (error, _) => ErrorStateView(error: error, onRetry: onRetry),
      data: (data) {
        final empty = isEmpty?.call(data) ?? data == null;
        if (empty) {
          return emptyWidget ??
              EmptyStateView(message: emptyMessage ?? 'Nothing here yet.');
        }
        return builder(context, data);
      },
    );
  }
}
