import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_screen.dart';

class _AccountAuthRepository extends AuthRepository {
  _AccountAuthRepository(this.user) : super(Dio());

  final AuthUser user;

  @override
  Future<AuthUser?> restoreSession() async => user;
}

AuthUser _verifiedOwner() => AuthUser.fromJson({
      'id': 9001,
      'name': 'مالك اختبار W4b',
      'email': 'w4b-owner@example.test',
      'phone': '+967700000001',
      'account_type': 'regular',
      'account_status': 'active',
      'phone_verified_at': '2026-10-05T00:00:00Z',
      'profile_completed_at': '2026-10-05T00:00:00Z',
      'is_platform_owner': false,
      'roles': ['registered_user'],
      'permissions': [],
      'verification_profile': {
        'type': 'owner',
        'status': 'approved',
        'submitted_at': '2026-10-04T00:00:00Z',
        'reviewed_at': '2026-10-05T00:00:00Z',
        'flags': {'identity_reviewed': true},
      },
    });

void main() {
  testWidgets('verified owner account has free-core actions without finance entries',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final user = _verifiedOwner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_AccountAuthRepository(user)),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إعلاناتي'), findsOneWidget);
    expect(find.text('إضافة عقار'), findsOneWidget);
    expect(find.text('المعاينات'), findsOneWidget);
    expect(find.text('اتفاقاتي وعقودي'), findsOneWidget);
    expect(find.text('المفضلة'), findsOneWidget);

    expect(find.text('مدفوعاتي'), findsNothing);
    expect(find.text('الحساب المالي'), findsNothing);
    expect(find.byIcon(Icons.payments_outlined), findsNothing);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
  });
}
