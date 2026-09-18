import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P02 routes regular users through the cumulative discovery shell', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();
    expect(router, contains('P02AppShellScreen'));
    expect(router, contains("path: '/property-market'"));
    expect(router, contains("path: '/property-requests'"));
    expect(router, contains("path: '/favorites'"));
  });

  test('P02 shell stays simple and does not surface later-package workspaces', () {
    final shell = File(
      'lib/features/app_shell/presentation/p02_app_shell_screen.dart',
    ).readAsStringSync();

    expect(shell, contains("label: 'الرئيسية'"));
    expect(shell, contains("label: 'العقارات'"));
    expect(shell, contains("label: 'حسابي'"));
    expect(shell, isNot(contains("label: 'الرسائل'")));
    expect(shell, isNot(contains("label: 'المعاينات'")));
    expect(shell, contains('MapScreen(enableListingCreation: false)'));
  });

  test('P02 discovery supports private request action and no listing CTA', () {
    final map = File(
      'lib/features/map/presentation/map_screen.dart',
    ).readAsStringSync();

    expect(map, contains("buttonLabel: 'إنشاء طلب عقار خاص'"));
    expect(map, contains("actionLabel: widget.enableListingCreation ? 'إضافة' : 'طلب عقار'"));
    expect(map, contains('YER_NORTH'));
    expect(map, contains('YER_SOUTH'));
    expect(map, contains('propertyAreaUnitLabel'));
  });

  test('P02 private requests state privacy and keep original units', () {
    final builder = File(
      'lib/features/properties/presentation/saved_search_builder_screen.dart',
    ).readAsStringSync();

    expect(builder, contains('لا يظهر للدلالين أو المكاتب'));
    expect(builder, contains("'currency'"));
    expect(builder, contains("'area_unit'"));
    expect(builder, contains("'min_area_value'"));
    expect(builder, contains("'max_area_value'"));
    expect(builder, contains('لا يوجد تحويل تلقائي بين العملات'));
  });

  test('P02 package identity is explicit', () {
    final package = File('lib/core/config/v2_package.dart').readAsStringSync();
    expect(package, contains("defaultValue: 'P02'"));
    expect(package, contains("title = 'السوق والبحث'"));
  });
}
