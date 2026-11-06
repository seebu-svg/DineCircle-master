/// Currency-aware money helpers.
///
/// DineCircle settles guest bookings in a single currency today, so the
/// backend stores bare numeric totals. Every total surfaced in the app is
/// still grouped by an explicit currency code, so a future multi-currency
/// catalogue can never be summed into one misleading number.
library;

/// Currency assumed for booking/payment records that carry no explicit code.
///
/// DineCircle operates in Pakistan: the backend stores bare numeric rupee
/// totals and guests settle with the venue in PKR, so this is the display
/// currency everywhere a code is absent.
const String kDefaultCurrency = 'PKR';

/// Symbol for [code]; unknown currencies fall back to the ISO code itself so
/// an amount is never displayed with the wrong symbol.
String currencySymbol(String code) {
  switch (code.toUpperCase()) {
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'PKR':
      return 'Rs ';
    case 'AED':
      return 'AED ';
    default:
      return '${code.toUpperCase()} ';
  }
}

/// Formats [amount] in [currency]. [decimals] defaults to 2 so refunds,
/// partial payments and fees never silently lose cents.
String formatMoney(
  double amount, {
  String currency = kDefaultCurrency,
  int decimals = 2,
}) {
  final negative = amount < 0;
  final body = amount.abs().toStringAsFixed(decimals);
  return '${negative ? '-' : ''}${currencySymbol(currency)}$body';
}

/// A single amount together with the currency it was charged in.
class MoneyAmount {
  const MoneyAmount(this.currency, this.amount);

  final String currency;
  final double amount;
}

/// Sums [entries] per currency. Callers render one line per key instead of
/// blending currencies into a single, incorrect total.
Map<String, double> sumByCurrency(Iterable<MoneyAmount> entries) {
  final totals = <String, double>{};
  for (final entry in entries) {
    final code = entry.currency.isEmpty ? kDefaultCurrency : entry.currency;
    totals[code] = (totals[code] ?? 0) + entry.amount;
  }
  return totals;
}

/// Formats a menu price as `Rs 2,450` / `Rs 690.50`.
///
/// Every `restaurant_menu_items.price` is a PKR numeric, and menu prices are
/// quoted in whole rupees, so whole amounts drop the decimals while fractional
/// ones keep two. Thousands are grouped so long prices stay scannable.
String formatPkr(num value) {
  final fractionDigits = value == value.roundToDouble() ? 0 : 2;
  final parts = value.toStringAsFixed(fractionDigits).split('.');
  final grouped = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return parts.length > 1 ? 'Rs $grouped.${parts[1]}' : 'Rs $grouped';
}
