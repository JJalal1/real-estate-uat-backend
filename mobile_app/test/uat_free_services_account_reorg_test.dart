import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account page separates own-property management from activity', () {
    final source = File(
      'lib/features/account/presentation/account_screen.dart',
    ).readAsStringSync();

    for (final label in <String>[
      'إدارة عقاراتي',
      'إضافة إعلان جديد',
      'إعلاناتي',
      'طلبات المعاينة على عقاراتي',
      'عقود الإيجار',
      'نشاطي',
      'المفضلة',
      'طلبات العقار',
      'حجوزاتي',
      'طلبات الباحثين',
    ]) {
      expect(source, contains(label), reason: 'Missing account label: $label');
    }

    expect(source, isNot(contains('المشاريع والتطويرات العقارية')));
    expect(source, isNot(contains('الخدمات والترقيات والمدفوعات')));
    expect(source, contains("servicesHub?.can('view_researcher_requests')"));
    expect(source, contains("context.push('/bookings')"));
  });

  test('backend hub explicitly disables paid feature mode', () {
    final controller = File(
      '../backend-api-runtime/app/Http/Controllers/Api/FreeServicesHubController.php',
    ).readAsStringSync();
    final routes = File('../backend-api-runtime/routes/api.php').readAsStringSync();

    expect(controller, contains("'pricing_model' => 'free'"));
    expect(controller, contains("'paid_features_enabled' => false"));
    expect(controller, contains("'view_researcher_requests' => \$verifiedBrokerOrOffice"));
    expect(routes, contains("Route::get('/services/hub'"));
  });
}
