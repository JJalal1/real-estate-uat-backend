import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account keeps launch-critical marketplace actions', () {
    final source = File(
      'lib/features/account/presentation/account_screen.dart',
    ).readAsStringSync();

    for (final label in <String>[
      'الخدمات والأدوات',
      'المساعدة والدعم',
      'إدارة عقاراتي',
      'إعلاناتي',
      'إضافة عقار',
      'نشاطي',
      'المعاينات',
      'المفضلة',
    ]) {
      expect(source, contains(label), reason: 'Missing account label: $label');
    }

    expect(source, contains("context.push('/services')"));
    expect(source, contains("context.push('/bookings')"));
    expect(source, contains('user.hasVerifiedPublishingProfile'));
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
