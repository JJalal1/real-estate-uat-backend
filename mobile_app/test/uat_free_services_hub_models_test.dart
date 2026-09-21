import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/services/domain/service_models.dart';

void main() {
  test('free services hub parses the cleaned backend contract', () {
    final hub = FreeServicesHubModel.fromJson({
      'ui_version': 'free_services_v2',
      'pricing_model': 'free',
      'paid_features_enabled': false,
      'account_type': 'broker',
      'verification_status': 'approved',
      'verified_professional': true,
      'capabilities': {
        'create_listing': true,
        'rental_contracts': true,
        'price_indicators': true,
      },
      'availability': {
        'create_listing': 'available',
        'rental_contracts': 'planned',
        'price_indicators': 'planned',
      },
    });

    expect(hub.uiVersion, 'free_services_v2');
    expect(hub.pricingModel, 'free');
    expect(hub.paidFeaturesEnabled, isFalse);
    expect(hub.accountTypeLabel, 'دلال');
    expect(hub.can('create_listing'), isTrue);
    expect(hub.can('rental_contracts'), isTrue);
    expect(hub.can('view_researcher_requests'), isFalse);
    expect(hub.isAvailable('create_listing'), isTrue);
    expect(hub.isAvailable('rental_contracts'), isFalse);
  });
}
