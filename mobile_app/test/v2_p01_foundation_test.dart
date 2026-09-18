import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P01 foundation remains present in cumulative packages', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();
    expect(router, contains('P02LoginScreen'));
    expect(router, contains('P02RegisterScreen'));
    expect(router, contains('P01PhoneVerificationScreen'));
    expect(router, contains('P01CompleteProfileScreen'));
    expect(router, contains('P01ProfileScreen'));
    expect(
      File('lib/features/app_shell/presentation/p01_app_shell_screen.dart')
          .existsSync(),
      isTrue,
    );
  });

  test('P01 regular shell exposes only foundation navigation', () {
    final shell = File(
      'lib/features/app_shell/presentation/p01_app_shell_screen.dart',
    ).readAsStringSync();

    expect(shell, contains("label: 'الرئيسية'"));
    expect(shell, contains("label: 'حسابي'"));
    expect(shell, isNot(contains("label: 'السوق'")));
    expect(shell, isNot(contains("label: 'الرسائل'")));
    expect(shell, isNot(contains("label: 'الخدمات'")));
  });

  test('P01 account keeps publishing identity separate from base account', () {
    final account = File(
      'lib/features/account/presentation/p01/p01_account_screen.dart',
    ).readAsStringSync();

    expect(account, contains('التوثيق والنشر'));
    expect(account, contains('مالك أو دلال أو مكتب'));
    expect(account, isNot(contains('اتفاقاتي وعقودي')));
    expect(account, isNot(contains('مدفوعاتي')));
    expect(account, isNot(contains('إدارة عقاراتي')));
  });

  test('P01 design remains Arabic-first and token-based', () {
    final main = File('lib/main.dart').readAsStringSync();
    final theme = File('lib/core/theme/app_theme.dart').readAsStringSync();
    final typography =
        File('lib/core/theme/app_typography.dart').readAsStringSync();

    expect(main, contains("locale: const Locale('ar')"));
    expect(theme, contains('ColorScheme.fromSeed'));
    expect(typography, contains("fontFamily = 'NotoSansArabic'"));
  });
}
