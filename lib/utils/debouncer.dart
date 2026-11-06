import 'dart:async';

/// Coalesces a burst of input into one callback.
///
/// Search boxes previously each carried their own `Timer?` field (Explore at
/// 500 ms, the old search screen at 350 ms, Deals with none at all). One small
/// class keeps the delay consistent and the disposal path impossible to forget.
class Debouncer {
  Debouncer(this.duration);

  final Duration duration;
  Timer? _timer;

  bool get isActive => _timer?.isActive ?? false;

  /// Schedules [action], cancelling any callback still pending.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
