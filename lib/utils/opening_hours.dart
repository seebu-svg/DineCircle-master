/// Parses the restaurant `opening_hours` JSONB column into display-ready
/// structures.
///
/// The server stores hours in lowercase weekday keys:
/// ```json
/// {
///   "mon": {"windows": [{"open": "17:00", "close": "24:00"}], "closed": false},
///   "tue": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "17:00", "close": "23:00"}]},
///   "wed": {"closed": true}
/// }
/// ```
///
/// A legacy shape (`{"Mon": "17:00-24:00"}`) is also tolerated for backwards
/// compatibility but is not produced by the current server.
library;

/// Canonical day-of-week order (Monday-first, matching DateTime.weekday).
const List<String> kDayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// Display labels for each day.
const List<String> kDayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// One parsed time-window inside a day.
class WindowView {
  const WindowView({required this.open, required this.close});
  final String open;
  final String close;

  @override
  String toString() => '$open–$close';
}

/// Parsed opening-hours for a single weekday.
class DayView {
  const DayView({required this.key, required this.label, required this.closed, required this.windows});
  final String key;
  final String label;
  final bool closed;
  final List<WindowView> windows;

  /// Human-readable summary: "Closed" or "17:00–24:00" (first window only for
  /// brevity when there are splits).
  String get summary {
    if (closed || windows.isEmpty) return 'Closed';
    return windows.map((w) => '${w.open}–${w.close}').join(', ');
  }
}

/// Parse the raw `openingHours` map from the API into an ordered list of
/// [DayView]s (Mon → Sun). Returns an empty list when the map is empty or
/// unparseable.
List<DayView> parseOpeningHours(Map<String, dynamic> raw) {
  if (raw.isEmpty) return const [];

  return List.generate(7, (i) {
    final key = kDayKeys[i];
    final label = kDayLabels[i];
    final entry = raw[key] ?? raw[label]; // tolerate lowercase or title-case

    if (entry == null) {
      return DayView(key: key, label: label, closed: true, windows: const []);
    }

    // Legacy string shape: "17:00-24:00" or "Closed"
    if (entry is String) {
      if (entry.toLowerCase() == 'closed' || entry.trim().isEmpty) {
        return DayView(key: key, label: label, closed: true, windows: const []);
      }
      final parts = entry.split('-').map((s) => s.trim()).toList();
      if (parts.length == 2) {
        return DayView(
          key: key,
          label: label,
          closed: false,
          windows: [WindowView(open: parts[0], close: parts[1])],
        );
      }
      return DayView(key: key, label: label, closed: true, windows: const []);
    }

    // Structured shape: {closed: bool, windows: [{open, close}]}
    if (entry is Map) {
      final isClosed = entry['closed'] == true;
      if (isClosed) {
        return DayView(key: key, label: label, closed: true, windows: const []);
      }
      final rawWindows = entry['windows'];
      if (rawWindows is List) {
        final windows = rawWindows
            .whereType<Map>()
            .map((w) {
              final open = w['open']?.toString() ?? '';
              final close = w['close']?.toString() ?? '';
              if (open.isEmpty || close.isEmpty) return null;
              return WindowView(open: open, close: close);
            })
            .whereType<WindowView>()
            .toList();
        return DayView(key: key, label: label, closed: windows.isEmpty, windows: windows);
      }
      // Map but no windows array → treat as closed
      return DayView(key: key, label: label, closed: true, windows: const []);
    }

    return DayView(key: key, label: label, closed: true, windows: const []);
  });
}

/// Returns true if the venue is currently open based on its opening hours and
/// the device's local clock.
bool isCurrentlyOpen(List<DayView> days) {
  if (days.isEmpty) return false;
  final now = DateTime.now();
  // DateTime.weekday: Monday=1 … Sunday=7
  final todayIndex = now.weekday - 1;
  if (todayIndex < 0 || todayIndex >= days.length) return false;
  final today = days[todayIndex];
  if (today.closed || today.windows.isEmpty) return false;

  final nowMinutes = now.hour * 60 + now.minute;
  for (final w in today.windows) {
    final openMin = _toMinutes(w.open);
    var closeMin = _toMinutes(w.close);
    if (openMin == null || closeMin == null) continue;
    // Handle midnight wrap: "24:00" → treat as 24*60=1440
    if (closeMin <= openMin) closeMin += 24 * 60;
    if (nowMinutes >= openMin && nowMinutes <= closeMin) return true;
  }
  return false;
}

/// Parse "HH:MM" (24-hour) into total minutes since midnight.
int? _toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null) return null;
  return h * 60 + m;
}
