import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('services hub exposes current marketplace paths without deferred request matching', () {
    final source = File(
      'lib/features/services/presentation/services_screen.dart',
    ).readAsStringSync();

    for (final label in <String>[
      'الخدمات والأدوات',
      'الخدمات الحالية مجانية',
      'متاح الآن',
      'إضافة عقار',
      'إعلاناتي',
      'قادم لاحقاً',
      'مقارنة العقارات',
      'الدليل العقاري',
      'نماذج وإرشادات المستندات',
    ]) {
      expect(source, contains(label), reason: 'Missing services label: $label');
    }

    for (final removed in <String>[
      'رحلتي العقارية',
      'البحوث المحفوظة والتنبيهات',
      'اتفاقاتي وعقودي',
      'مؤشرات الأسعار',
      'اطلب عقار',
      'طلبات العقار',
      'طلبات الباحثين',
      'create_property_request',
      'property_requests',
      'researcher_requests',
      'خدمات التسويق الحصري',
      'إعلانات اليوم',
      'الصفقات العقارية',
      'احجز معاينة',
      'حساب الخدمات',
      'إدارة الخدمات والترقيات',
      'المدفوعات والتسويات',
    ]) {
      expect(source, isNot(contains(removed)), reason: 'Deferred/removed service leaked: $removed');
    }

    expect(source, contains("context.push('/add-property')"));
    expect(source, contains("context.push('/my-listings')"));
    expect(source, contains('AppAppBar'));
    expect(source, contains('AppSurface'));
    expect(source, contains('AppStatusBadge'));
  });

  test('services visibility is sourced from authenticated backend hub', () {
    final repo = File(
      'lib/features/services/data/service_repository.dart',
    ).readAsStringSync();
    final model = File(
      'lib/features/services/domain/service_models.dart',
    ).readAsStringSync();

    expect(repo, contains("'/services/hub'"));
    expect(repo, contains('requiredAuthOptions()'));
    expect(repo, contains('freeServicesHubProvider'));
    expect(model, contains('class FreeServicesHubModel'));
    expect(model, contains('paidFeaturesEnabled'));
    expect(model, contains('bool can(String key)'));
  });

  test('projects and the Account services shortcut stay removed while the hub remains routed', () {
    final shell = File(
      'lib/features/app_shell/presentation/app_shell_screen.dart',
    ).readAsStringSync();
    final account = File(
      'lib/features/account/presentation/account_screen.dart',
    ).readAsStringSync();
    final router = File('lib/router/app_router.dart').readAsStringSync();

    expect(shell, isNot(contains('ProjectsScreen')));
    expect(shell, isNot(contains("label: 'المشاريع'")));
    expect(shell, contains("label: 'العقارات'"));
    expect(shell, contains("label: 'الرسائل'"));
    expect(shell, contains("label: 'إعلاناتي'"));
    final addRoute = router.substring(router.indexOf("path: '/add-property'"), router.indexOf("path: '/my-listings'"));
    expect(addRoute, contains('requireListingEligible: true'));
    expect(account, isNot(contains("context.push('/bookings')")));
    expect(shell, contains("label: 'حسابي'"));
    expect(shell, isNot(contains("label: 'الخدمات'")));
    expect(account, contains('الخدمات والدعم'));
    expect(account, isNot(contains("context.push('/services')")));
    expect(account, isNot(contains('الخدمات والأدوات')));
    expect(router, contains("path: '/services'"));

    expect(router, isNot(contains("path: '/developments'")));
    expect(router, isNot(contains("path: '/developments/:id'")));
    expect(router, isNot(contains("path: '/admin/developments'")));
  });
}
