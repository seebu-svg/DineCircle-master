/// Cuisine label normalisation.
///
/// Venues were seeded with both `Cafe` and `Café`, so Explore rendered two
/// chips for one filter and each chip matched only the half of the list spelled
/// its way. Chips are grouped on [cuisineKey] (case- and diacritic-insensitive)
/// so a single spelling cannot split a filter in two again, and a venue
/// matches whenever any of its cuisines folds to the selected key.
///
/// This is presentation and matching only: the stored cuisine strings are left
/// exactly as the venue entered them.
library;

/// Accented letters folded to their plain ASCII counterpart. Only the letters
/// that actually occur in cuisine names are listed; anything else falls back to
/// the character itself, and case is already folded before lookup.
const Map<String, String> _foldedLetters = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
  'ß': 'ss',
};

/// Comparison key for a cuisine label: trimmed, lower-cased, diacritics
/// folded, internal whitespace collapsed. `Cafe`, `CAFE` and `Café` all
/// produce `cafe`.
String cuisineKey(String label) {
  final buffer = StringBuffer();
  for (final rune in label.trim().toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    buffer.write(_foldedLetters[character] ?? character);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// One display label per distinct cuisine across [raws], sorted alphabetically.
///
/// The longest spelling wins a tie, so the accented form (`Café`) is the label
/// the guest reads while `Cafe` still matches it.
List<String> canonicalCuisines(Iterable<String> raws) {
  final labelByKey = <String, String>{};
  for (final raw in raws) {
    final label = raw.trim();
    if (label.isEmpty) continue;
    final key = cuisineKey(label);
    if (key.isEmpty) continue;
    final existing = labelByKey[key];
    if (existing == null || label.length > existing.length) {
      labelByKey[key] = label;
    }
  }
  return labelByKey.values.toList()..sort();
}

/// Whether [cuisineCsv] (the comma-joined `restaurants.cuisines` string)
/// contains the cuisine [selection], tolerating spelling variants.
bool cuisineMatches(String cuisineCsv, String selection) {
  final target = cuisineKey(selection);
  if (target.isEmpty) return true;
  return cuisineCsv
      .split(',')
      .any((part) => cuisineKey(part) == target);
}
