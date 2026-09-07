import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('free services hub contains the approved sections and actions', () {
    final source = File(
      'lib/features/services/presentation/services_screen.dart',
    ).readAsStringSync();

    for (final label in <String>[
      'الخدمات السريعة',
      'أضف عقار',
      'اطلب عقار',
      'إعلاناتي',
      'قيّم عقارك',
      'الخدمات العقارية',
      'طلبات العقار',
      'عقود الإيجار',
      'مؤشرات الأسعار',
      'تقييم العقار',
      'طلبات الباحثين',
      'معلومات وأدوات',
      'الدليل العقاري',
      'المستندات القانونية',
      'مجانية بالكامل',
    ]) {
      expect(source, contains(label), reason: 'Missing services label: $label');
    }

    for (final removed in <String>[
      'خدمات التسويق الحصري',
      'إعلانات اليوم',
      'الصفقات العقارية',
      'احجز معاينة',
      'حساب الخدمات',
      'إدارة الخدمات والترقيات',
      'المدفوعات والتسويات',
      "title: 'المدونة'",
    ]) {
      expect(source, isNot(contains(removed)), reason: 'Removed service leaked: $removed');
    }

    expect(source, contains("context.push('/add-property')"));
    expect(source, contains("context.push('/my-listings')"));
    expect(source, contains("model.can('view_researcher_requests')"));
    expect(source, contains('constraints: const BoxConstraints(minHeight: 74)'));
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

  test('projects stay removed and services move under account in accepted IA', () {
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
    expect(shell, contains("label: 'المعاينات'"));
    expect(shell, contains("label: 'حسابي'"));
    expect(shell, isNot(contains("label: 'الخدمات'")));
    expect(account, contains("context.push('/services')"));
    expect(account, contains('الخدمات والأدوات'));

    expect(router, isNot(contains("path: '/developments'")));
    expect(router, isNot(contains("path: '/developments/:id'")));
    expect(router, isNot(contains("path: '/admin/developments'")));
  });
}
