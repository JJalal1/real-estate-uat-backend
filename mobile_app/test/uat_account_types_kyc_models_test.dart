import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/domain/broker_verification.dart';

void main() {
  test('regular account parses with listing access after phone verification',
      () {
    final user = AuthUser.fromJson({
      'id': 10,
      'name': 'أحمد محمد علي',
      'email': 'wa_hidden@phone.local.invalid',
      'phone': '+967711111101',
      'account_type': 'regular',
      'account_status': 'active',
      'phone_verified_at': '2026-08-25T00:00:00Z',
      'broker_verification_status': 'not_required',
      'is_platform_owner': false,
      'roles': ['registered_user'],
      'permissions': <String>[],
    });

    expect(user.isRegular, isTrue);
    expect(user.isBroker, isFalse);
    expect(user.canCreateListing, isTrue);
    expect(user.accountTypeLabel, 'مستخدم عادي');
  });

  test('broker cannot create listing until support verification is approved',
      () {
    final pending = AuthUser.fromJson({
      'id': 11,
      'name': 'محمد أحمد علي صالح',
      'phone': '+967711111102',
      'account_type': 'broker',
      'account_status': 'active',
      'phone_verified_at': '2026-08-25T00:00:00Z',
      'broker_verification_status': 'pending',
      'is_platform_owner': false,
      'roles': ['registered_user'],
      'permissions': <String>[],
    });
    final approved = AuthUser.fromJson({
      'id': 11,
      'name': 'محمد أحمد علي صالح',
      'phone': '+967711111102',
      'account_type': 'broker',
      'account_status': 'active',
      'phone_verified_at': '2026-08-25T00:00:00Z',
      'broker_verification_status': 'approved',
      'broker_verified_at': '2026-08-25T00:01:00Z',
      'is_platform_owner': false,
      'roles': ['registered_user', 'broker'],
      'permissions': <String>[],
    });

    expect(pending.canCreateListing, isFalse);
    expect(approved.isBrokerVerified, isTrue);
    expect(approved.canCreateListing, isTrue);
  });

  test('broker verification application parses private document kinds', () {
    final application = BrokerVerificationApplication.fromJson({
      'user_id': 11,
      'name': 'محمد أحمد علي صالح',
      'phone': '+967711111102',
      'status': 'pending',
      'documents': [
        {'kind': 'id_front', 'url': '/api/front'},
        {'kind': 'id_back', 'url': '/api/back'},
        {'kind': 'selfie', 'url': '/api/selfie'},
      ],
    });

    expect(application.pending, isTrue);
    expect(application.documents.map((item) => item.kind),
        containsAll(['id_front', 'id_back', 'selfie']));
  });
}
