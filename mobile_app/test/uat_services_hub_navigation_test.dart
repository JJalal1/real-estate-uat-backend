import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('services hub contains the requested Arabic sections and actions', () {
    final source = File(
      'lib/features/services/presentation/services_screen.dart',
    ).readAsStringSync();

    for (final label in <String>[
      'خدمات سريعة',
      'أضف عقارك',
      'اطلب عقار',
      'احجز معاينة',
      'قيّم عقارك',
      'الخدمات الرئيسية',
      'إعلانات اليوم',
      'عقود الإيجار',
      'طلبات البحث',
      'خدمات التسويق الحصري',
      'متوسط الأسعار',
      'الصفقات العقارية',
      'تطبيق',
      'المدونة',
      'المستندات القانونية',
    ]) {
      expect(source, contains(label), reason: 'Missing services label: $label');
    }

    expect(source, contains("context.push('/add-property')"));
    expect(source, contains("context.push('/bookings')"));
    expect(source, contains("context.go('/')"));
    expect(
      source,
      contains('constraints: const BoxConstraints(minHeight: 74)'),
      reason: 'Service rows must use valid Container constraints.',
    );
    expect(
      source,
      isNot(contains('minHeight: 74,')),
      reason: 'Container has no minHeight named parameter.',
    );
  });

  test('projects interface is removed from mobile navigation and routes', () {
    final shell = File(
      'lib/features/app_shell/presentation/app_shell_screen.dart',
    ).readAsStringSync();
    final router = File('lib/router/app_router.dart').readAsStringSync();

    expect(shell, isNot(contains('ProjectsScreen')));
    expect(shell, isNot(contains("label: 'المشاريع'")));
    expect(shell, contains("label: 'حسابي'"));
    expect(shell, contains("label: 'الإعلانات'"));
    expect(shell, contains("label: 'الحجوزات'"));
    expect(shell, contains("label: 'المحادثات'"));
    expect(shell, contains("label: 'الخدمات'"));

    expect(router, isNot(contains("path: '/developments'")));
    expect(router, isNot(contains("path: '/developments/:id'")));
    expect(router, isNot(contains("path: '/admin/developments'")));
    expect(router, isNot(contains('DevelopmentsScreen')));
    expect(router, isNot(contains('DevelopmentDetailsScreen')));
    expect(router, isNot(contains('DevelopmentAdminScreen')));
  });
}
