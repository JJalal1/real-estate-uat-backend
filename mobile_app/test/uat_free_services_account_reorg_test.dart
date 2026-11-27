import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_widgets.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_screen.dart';

import 'support/owner_ux_fixtures.dart';

void main() {
  setUpAll(loadUxFixtures);

  testWidgets('broker Account groups its nine links and opens the private editor', (tester) async {
    const privateProfileKey = ValueKey('test-private-profile');
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AccountScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: SizedBox(key: privateProfileKey))),
    ]);
    addTearDown(router.dispose);
    await pumpUx(tester, uxContainer(user: uxUser(type: 'broker')), const SizedBox.shrink(),
      size: const Size(412, 1320), router: router);

    Iterable<String> rows(String key) => tester.widgetList<AppListRow>(find.descendant(
      of: find.byKey(ValueKey(key)), matching: find.byType(AppListRow),
    )).map((row) => row.title);

    expect(rows('account-preferences-group'), ['البحث الذكي', 'المفضلة', 'شوهد مؤخرًا']);
    expect(rows('account-profile-group'), ['الملف الشخصي', 'الأمان والخصوصية', 'تفضيلات الإشعارات', 'المظهر']);
    expect(rows('account-payments-support-group'), ['مدفوعاتي', 'المساعدة والدعم']);
    for (final title in ['تصفّح العقارات', 'الحساب والتفضيلات', 'الخدمات والدعم']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.descendant(of: find.byKey(const ValueKey('account-type-badge')), matching: find.text('دلال')), findsOneWidget);
    expect(find.byTooltip('تعديل الملف الشخصي'), findsNothing);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    for (final label in [
      'الخدمات والأدوات',
      'الإشعارات',
      'إدارة عقاراتي',
      'عقاراتي',
      'إضافة عقار',
      'لوحة العمل',
      'إدارة العملاء',
      'ملفي العام',
      'مستحقات المنصة',
      'نتائج الصفقات',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
    final search = tester.widget<AppListRow>(find.byKey(const ValueKey('account-smart-search')));
    expect((search.leading! as EbrokerIcon).color, AppTheme.light.colorScheme.primary);
    expect(tester.widget<Text>(find.text('البحث الذكي')).style?.color, Colors.black);
    await tester.tap(find.text('الملف الشخصي'));
    await uxFrames(tester);
    expect(find.byKey(privateProfileKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  for (final type in ['owner', 'office']) {
    testWidgets('$type Account preserves unique listing and finance entries', (tester) async {
      await pumpUx(tester, uxContainer(user: uxUser(type: type)), const AccountScreen(), size: const Size(412, 1800));
      expect(find.text(type == 'office' ? 'عقاراتي' : 'إعلاناتي'), findsOneWidget);
      expect(find.text('مستحقات المنصة'), findsOneWidget);
      expect(find.text('نتائج الصفقات'), findsOneWidget);
      expect(find.text('لوحة العمل'), type == 'office' ? findsOneWidget : findsNothing);
      expect(find.text('إدارة العملاء'), type == 'office' ? findsOneWidget : findsNothing);
      expect(find.text('الخدمات والأدوات'), findsNothing);
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }

  testWidgets('guest Account keeps browsing, appearance and sign-in without private groups', (tester) async {
    await pumpUx(tester, uxContainer(), const AccountScreen());
    expect(find.text('تصفّح العقارات'), findsOneWidget);
    expect(find.text('المظهر'), findsOneWidget);
    expect(find.text('تسجيل الدخول أو إنشاء حساب'), findsOneWidget);
    expect(find.text('الحساب والتفضيلات'), findsNothing);
    expect(find.text('الخدمات والدعم'), findsNothing);
    expect(find.byKey(const ValueKey('account-type-badge')), findsNothing);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('phone signup shows its phone and omits the provisional identity', (tester) async {
    final user = AuthUser.fromJson({
      'id': 1,
      'name': 'مستخدم جديد',
      'phone': '+967771234567',
      'email': '771234567@phone.local.invalid',
      'account_status': 'active',
      'phone_verified_at': '2026-11-26T00:00:00Z',
    });
    await pumpUx(tester, uxContainer(user: user), const AccountScreen());
    expect(find.text('+967771234567'), findsOneWidget);
    expect(find.text('مستخدم جديد'), findsNothing);
    expect(find.textContaining('@phone.local.invalid'), findsNothing);
    expect(find.text('مرحباً بك'), findsOneWidget);
    expect(find.text('أكمل الاسم الرباعي'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  test('account does not expose deferred journeys', () {
    final source = File(
      'lib/features/account/presentation/account_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains("context.push('/services')")));
    expect(source, isNot(contains("context.push('/bookings')")));
    expect(source, isNot(contains("'طلبات العقار'")));
    expect(source, isNot(contains("'طلبات الباحثين'")));
    expect(source, isNot(contains('المشاريع والتطويرات العقارية')));
    expect(source, isNot(contains('الخدمات والترقيات والمدفوعات')));
  });

  test('backend hub explicitly disables paid feature mode', () {
    final controller = File(
      '../backend-api-runtime/app/Http/Controllers/Api/FreeServicesHubController.php',
    ).readAsStringSync();
    final routes = File('../backend-api-runtime/routes/api.php').readAsStringSync();

    expect(controller, contains("'pricing_model' => 'free'"));
    expect(controller, contains("'paid_features_enabled' => false"));
    expect(routes, contains("Route::get('/services/hub'"));
  });
}
