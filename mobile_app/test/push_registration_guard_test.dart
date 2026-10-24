import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/messages/data/push_registration_repository.dart';

void main() {
  test('only valid opted-in Android registration can be sent to Laravel', () {
    final valid = PushNativeRegistration.fromMap({
      'configured': true, 'granted': true,
      'installation_id': '11111111-2222-3333-4444-555555555555',
      'token': '  ${List.filled(32, 'f').join()}  ',
    });
    expect(valid.hasUsableInstallationId, isTrue);
    expect(valid.hasUsableToken, isTrue);
    expect(valid.canRegister, isTrue);
    expect(valid.token, List.filled(32, 'f').join());
  });

  test('missing or malformed bridge data never permits registration', () {
    for (final payload in <Map<String, dynamic>>[
      {},
      {'configured': true, 'granted': false,
       'installation_id': '11111111-2222-3333-4444-555555555555',
       'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true, 'installation_id': '', 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true, 'installation_id': 'abc', 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true, 'installation_id': List.filled(201, 'x').join(), 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true,
       'installation_id': '11111111-2222-3333-4444-555555555555',
       'token': 'short'},
      {'configured': true, 'granted': true,
       'installation_id': '11111111-2222-3333-4444-555555555555',
       'token': List.filled(4097, 'f').join()},
      {'configured': true, 'granted': true,
       'installation_id': 1234567890123456789, 'token': List.filled(32, 'f').join()},
      {'configured': true, 'granted': true,
       'installation_id': '11111111-2222-3333-4444-555555555555', 'token': 1234567890123456789},
    ]) {
      expect(PushNativeRegistration.fromMap(payload).canRegister, isFalse, reason: '$payload');
    }
  });
}
