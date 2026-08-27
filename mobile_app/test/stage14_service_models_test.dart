import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/services/domain/service_models.dart';

void main() {
  test('Stage 14 offering model preserves exact price text and target label',
      () {
    final item = ServiceOfferingModel.fromJson({
      'id': 4,
      'code': 'listing_featured_7d',
      'name_ar': 'إبراز الإعلان',
      'target_type': 'property',
      'duration_days': 7,
      'price_amount': '1250.00',
      'currency': 'YER',
      'is_active': true
    });
    expect(item.priceAmount, '1250.00');
    expect(item.targetLabel, 'إعلان');
    expect(item.durationDays, 7);
  });

  test('Stage 14 order and entitlement status helpers are stable', () {
    final order = ServiceOrderModel.fromJson({
      'id': 9,
      'reference': 'S1401',
      'service_name': 'خدمة',
      'target_type': 'account',
      'amount': '500.00',
      'currency': 'YER',
      'status': 'paid',
      'can_cancel': false,
      'can_settle': false,
      'can_refund': true
    });
    final entitlement = ServiceEntitlementModel.fromJson({
      'id': 1,
      'service_name': 'خدمة',
      'target_type': 'account',
      'starts_at': '2026-08-21T00:00:00Z',
      'ends_at': '2026-09-20T00:00:00Z',
      'status': 'active',
      'is_active': true
    });
    expect(order.statusLabel, 'مدفوع ومفعّل');
    expect(entitlement.isActive, isTrue);
  });
}
