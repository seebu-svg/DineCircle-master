/// Venue-facing date and time formatting.
///
/// Instants arrive from the API as ISO-8601 with a `Z` suffix, so Dart parses
/// them into **UTC** `DateTime`s. Reading `.hour` on such a value yields the UTC
/// wall clock, which for a Karachi venue is five hours behind the time the guest
/// actually chose: a chip labelled "4:00 PM" would be stored (correctly) as
/// 21:00 PKT, so the app told the guest the wrong time to turn up.
///
/// Every formatter here applies [DateTime.toLocal] itself. Callers must pass the
/// raw instant and never read `.hour` / `.day` themselves, so the conversion can
/// only happen in one place.
///
/// The server is authoritative: opening hours are resolved in the venue's own
/// timezone (`restaurant_branches.timezone`) and compared as real instants, so
/// these helpers change presentation only, never which bookings are allowed.
library;

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [instant] as a 12-hour clock time in the guest's local zone,
/// e.g. `4:00 PM`. Midnight and noon render as `12:00 AM` / `12:00 PM`.
///
/// All venue times use 12-hour AM/PM so tables and experiences read the same;
/// mixing 24-hour (experiences) with 12-hour (tables) made the same evening look
/// like two different times.
String formatVenueTime(DateTime instant) {
  final local = instant.toLocal();
  final rawHour = local.hour;
  final hour = rawHour == 0 ? 12 : (rawHour > 12 ? rawHour - 12 : rawHour);
  final minute = local.minute.toString().padLeft(2, '0');
  final period = rawHour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

/// Formats a window as `4:00 PM - 5:30 PM`, or just the start when [end] is
/// unknown. Both ends are converted to the guest's local zone independently.
String formatVenueTimeRange(DateTime start, DateTime? end) {
  final from = formatVenueTime(start);
  if (end == null) return from;
  return '$from - ${formatVenueTime(end)}';
}

/// Formats [instant] as a short calendar date in the guest's local zone,
/// e.g. `Mon, Nov 9`. The date is derived from the local value, so a late
/// evening booking does not slide onto the previous day.
String formatVenueDate(DateTime instant) {
  final local = instant.toLocal();
  return '${_weekdays[local.weekday - 1]}, '
      '${_months[local.month - 1]} ${local.day}';
}
