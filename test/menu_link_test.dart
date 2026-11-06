import 'package:flutter_test/flutter_test.dart';

import 'package:dine_circle/utils/menu_link.dart';

/// The customer scanner must accept both the new canonical `/menu/<uuid>` path
/// and the legacy `/venues/<uuid>` path so previously printed QR codes keep
/// working. It must also accept bare UUIDs and the `dinecircle://menu/<uuid>`
/// deep-link scheme.
void main() {
  group('parseMenuPayload', () {
    const testUuid = '12345678-1234-1234-1234-123456789abc';

    test('accepts bare UUID', () {
      expect(parseMenuPayload(testUuid), testUuid);
    });

    test('accepts UUID with whitespace', () {
      expect(parseMenuPayload('  $testUuid  '), testUuid);
    });

    test('accepts dinecircle://menu/<uuid> deep-link scheme', () {
      expect(parseMenuPayload('dinecircle://menu/$testUuid'), testUuid);
    });

    test('accepts https://<host>/menu/<uuid> (new canonical)', () {
      expect(parseMenuPayload('https://dinecircle.app/menu/$testUuid'), testUuid);
    });

    test('accepts http://<host>/menu/<uuid>', () {
      expect(parseMenuPayload('http://example.com/menu/$testUuid'), testUuid);
    });

    test('accepts https://<host>/venues/<uuid> (legacy path)', () {
      expect(parseMenuPayload('https://dinecircle.app/venues/$testUuid'), testUuid);
    });

    test('accepts http://<host>/venues/<uuid> (legacy path)', () {
      expect(parseMenuPayload('http://example.com/venues/$testUuid'), testUuid);
    });

    test('accepts UUID after arbitrary path prefix', () {
      expect(parseMenuPayload('https://dinecircle.app/some/prefix/menu/$testUuid'), testUuid);
      expect(parseMenuPayload('https://dinecircle.app/some/prefix/venues/$testUuid'), testUuid);
    });

    test('rejects empty string', () {
      expect(parseMenuPayload(''), isNull);
      expect(parseMenuPayload('   '), isNull);
    });

    test('rejects non-UUID payload', () {
      expect(parseMenuPayload('not-a-uuid'), isNull);
    });

    test('rejects URL with non-UUID segment', () {
      expect(parseMenuPayload('https://dinecircle.app/menu/not-a-uuid'), isNull);
      expect(parseMenuPayload('https://dinecircle.app/venues/not-a-uuid'), isNull);
    });

    test('rejects malformed URL', () {
      expect(parseMenuPayload('https://'), isNull);
      expect(parseMenuPayload('not-a-url'), isNull);
    });

    test('rejects wrong scheme', () {
      expect(parseMenuPayload('ftp://dinecircle.app/menu/$testUuid'), isNull);
    });
  });
}
