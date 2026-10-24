import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/release/release_gate.dart';

void main() {
  test('official HTTPS Play Store release destination is accepted', () {
    final uri = verifiedAndroidStoreUri(
      'https://play.google.com/store/apps/details?id=com.example.aqer',
    );
    expect(uri?.host, 'play.google.com');
    expect(uri?.queryParameters['id'], 'com.example.aqer');
  });

  test('official market destination can open Play Store app', () {
    expect(
      verifiedAndroidStoreUri('market://details?id=com.example.aqer')?.scheme,
      'market',
    );
  });

  test('rejects arbitrary web hosts, insecure and dangerous schemes', () {
    for (final url in [
      'https://play.google.com.evil.test/store/apps/details?id=a',
      'https://example.test/store/apps/details?id=a',
      'http://play.google.com/store/apps/details?id=a',
      'javascript:alert(1)',
      'intent://details?id=a',
      'file:///private/settings',
      'https://user:password@play.google.com/store/apps/details?id=a',
      'https://play.google.com/store/apps/details?id=a#other',
      'https://play.google.com/store/apps/details',
      'market://other?id=a',
      'market://details?id=',
    ]) {
      expect(verifiedAndroidStoreUri(url), isNull, reason: url);
    }
  });

  test('release payloads without valid store URI remain non-clickable', () {
    expect(verifiedAndroidStoreUri(null), isNull);
    expect(verifiedAndroidStoreUri(''), isNull);
    expect(verifiedAndroidStoreUri(0), isNull);
  });
}
