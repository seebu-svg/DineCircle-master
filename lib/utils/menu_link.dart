/// Pure parser for QR-code payloads that point at a restaurant's public menu.
///
/// Four shapes are accepted:
///   1. `dinecircle://menu/<uuid>` — deep-link scheme
///   2. `https://<any host>/menu/<uuid>` — universal link (new canonical)
///   3. `https://<any host>/venues/<uuid>` — legacy universal link
///   4. A bare `<uuid>` — printed directly on the QR
///
/// Anything else returns `null` so the caller can show a friendly error.
/// Kept as a top-level pure function for unit-testability without a camera.
library;

final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Extracts a restaurant UUID from a scanned QR payload, or `null`.
String? parseMenuPayload(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Bare UUID.
  if (_uuidRe.hasMatch(trimmed)) return trimmed;

  // dinecircle://menu/<uuid>
  const schemePrefix = 'dinecircle://menu/';
  if (trimmed.startsWith(schemePrefix)) {
    final candidate = trimmed.substring(schemePrefix.length);
    if (_uuidRe.hasMatch(candidate)) return candidate;
  }

  // https://<host>/menu/<uuid> or /venues/<uuid> (any host, any path prefix)
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme && (uri.scheme == 'https' || uri.scheme == 'http')) {
    final segments = uri.pathSegments;
    // Look for a 'menu' or 'venues' segment followed by a UUID segment.
    for (var i = 0; i < segments.length - 1; i++) {
      if ((segments[i] == 'menu' || segments[i] == 'venues') && _uuidRe.hasMatch(segments[i + 1])) {
        return segments[i + 1];
      }
    }
  }

  return null;
}

/// Alias for [parseMenuPayload] used by route resolvers and deep-link handlers.
/// Returns the restaurant UUID extracted from a QR payload or deep link, or
/// `null` if the payload is invalid.
String? resolveRestaurantIdFromLink(String raw) => parseMenuPayload(raw);
