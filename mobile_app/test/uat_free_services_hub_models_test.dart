import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/services/domain/service_models.dart';

void main() {
  test('free services hub parses backend capabilities and availability', () {
    final hub = FreeServicesHubModel.fromJson({
      'ui_version': 'free_services_v1',
      'pricing_model': 'free',
      'paid_features_enabled': false,
      'account_type': 'broker',
      'verification_status': 'approved',
      'verified_professional': true,
      'capabilities': {
        'create_listing': true,
        'view_researcher_requests': true,
      },
      'availability': {
        'create_listing': 'available',
        'researcher_requests': 'planned',
      },
    });

    expect(hub.pricingModel, 'free');
    expect(hub.paidFeaturesEnabled, isFalse);
    expect(hub.accountTypeLabel, 'دلال');
    expect(hub.can('create_listing'), isTrue);
    expect(hub.can('view_researcher_requests'), isTrue);
    expect(hub.isAvailable('create_listing'), isTrue);
    expect(hub.isAvailable('researcher_requests'), isFalse);
  });
}
