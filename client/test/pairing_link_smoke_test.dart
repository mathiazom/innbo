import 'package:flutter_test/flutter_test.dart';
import 'package:innbo/pairing/pairing_link.dart';

void main() {
  test('parses a full pairing link', () {
    final data = parsePairingLink(
      'innbo://pair?url=https%3A%2F%2Finnbo.example.no&code=AB12CD34',
    );
    expect(data, isNotNull);
    expect(data!.serverUrl, 'https://innbo.example.no');
    expect(data.code, 'AB12CD34');
  });

  test('parses a code-only pairing link', () {
    final data = parsePairingLink('innbo://pair?code=AB12CD34');
    expect(data, isNotNull);
    expect(data!.serverUrl, isNull);
    expect(data.code, 'AB12CD34');
  });

  test('rejects an unrelated link', () {
    expect(parsePairingLink('https://example.com'), isNull);
  });
}
