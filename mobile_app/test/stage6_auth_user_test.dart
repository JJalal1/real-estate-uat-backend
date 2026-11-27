import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';

void main() {
  test('account badge follows the office choice without changing the account role', () {
    AuthUser user(Map<String, dynamic> fields) => AuthUser.fromJson(fields);
    expect(user({}).marketplaceRoleLabel, isNull);
    expect(user({'verification_profile': {'type': 'owner'}}).marketplaceRoleLabel, isNull);
    expect(user({'account_type': 'broker'}).marketplaceRoleLabel, 'دلال');
    expect(user({'verification_profile': {'type': 'office'}}).marketplaceRoleLabel, 'مكتب عقاري');
    final office = user({'broker_enrolled': true, 'marketplace_is_office': true});
    expect(office.marketplaceRoleLabel, 'مكتب عقاري');
    expect(office.isBroker, isTrue);
    expect(user({'broker_enrolled': true, 'marketplace_is_office': false}).marketplaceRoleLabel, 'دلال');
  });

  test('active verified account is active', () {
    final user = AuthUser.fromJson({
      'id': 7,
      'name': 'User',
      'email': 'user@example.test',
      'phone': '+967700000000',
      'account_status': 'active',
      'phone_verified_at': '2026-08-19T00:00:00+00:00',
    });
    expect(user.isActive, isTrue);
    expect(user.needsPhoneVerification, isFalse);
  });

  test('pending account requires verification', () {
    final user = AuthUser.fromJson({
      'id': 8,
      'name': 'Pending',
      'email': 'pending@example.test',
      'phone': '+967700000001',
      'account_status': 'pending_verification',
      'phone_verified_at': null,
    });
    expect(user.isActive, isFalse);
    expect(user.needsPhoneVerification, isTrue);
  });
}
