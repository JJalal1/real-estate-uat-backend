import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/domain/access_models.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';

void main() {
  test(
      'platform owner receives admin access regardless of explicit permissions',
      () {
    final user = AuthUser.fromJson({
      'id': 1,
      'name': 'Owner',
      'email': 'owner@example.test',
      'phone': '+967700000000',
      'account_status': 'active',
      'phone_verified_at': '2026-08-19T00:00:00+00:00',
      'is_platform_owner': true,
      'roles': ['registered_user', 'super_admin'],
      'permissions': [],
    });
    expect(user.isPlatformOwner, isTrue);
    expect(user.canAccessAdminPanel, isTrue);
    expect(user.hasPermission('users.manage_roles'), isTrue);
  });

  test('ordinary registered user has no admin panel', () {
    final user = AuthUser.fromJson({
      'id': 2,
      'name': 'User',
      'email': 'user@example.test',
      'account_status': 'active',
      'phone_verified_at': '2026-08-19T00:00:00+00:00',
      'roles': ['registered_user'],
      'permissions': [],
    });
    expect(user.canAccessAdminPanel, isFalse);
  });

  test('access user summary parses roles and overrides', () {
    final user = AccessUserSummary.fromJson({
      'id': 3,
      'name': 'Support',
      'email': 'support@example.test',
      'account_status': 'active',
      'is_platform_owner': false,
      'roles': ['support_manager'],
      'permissions': ['audit.view'],
      'permission_overrides': [
        {'permission_key': 'audit.view', 'effect': 'deny'},
      ],
    });
    expect(user.roles, contains('support_manager'));
    expect(user.permissionOverrides.single.effect, 'deny');
  });
}
