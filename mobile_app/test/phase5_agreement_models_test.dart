import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/agreements/domain/agreement_models.dart';

void main() {
  test('Phase 5 agreement model exposes same-revision acceptance state', () {
    final agreement = PropertyAgreement.fromJson({
      'id': 12,
      'reference': 'AGR-TEST',
      'property_id': 7,
      'message_thread_id': 91,
      'requester_user_id': 2,
      'advertiser_user_id': 1,
      'transaction_type': 'rent',
      'status': 'draft',
      'requester_accepted': true,
      'advertiser_accepted': false,
      'my_accepted': true,
      'can_revise': true,
      'can_accept': false,
      'can_cancel': true,
      'current_revision': {
        'id': 120,
        'revision_number': 3,
        'agreed_amount': 150000,
        'currency': 'YER',
        'rent_cadence': 'monthly',
        'security_deposit_amount': 150000,
        'rental_start_date': '2026-10-01',
        'rental_end_date': '2027-10-01',
        'created_by_user_id': 2,
        'created_by_name': 'طالب العقار',
      },
    });

    expect(agreement.isRental, isTrue);
    expect(agreement.isAccepted, isFalse);
    expect(agreement.requesterAccepted, isTrue);
    expect(agreement.advertiserAccepted, isFalse);
    expect(agreement.currentRevision.revisionNumber, 3);
    expect(agreement.currentRevision.cadenceLabel, 'شهري');
    expect(moneyLabel(150000, 'YER'), '150000 YER');
  });

  test('Phase 5 rental contract explicitly stays an in-app record', () {
    final contract = RentalContract.fromJson({
      'id': 31,
      'reference': 'RNT-TEST',
      'property_agreement_id': 12,
      'property_id': 7,
      'message_thread_id': 91,
      'tenant_user_id': 2,
      'advertiser_user_id': 1,
      'property_title': 'شقة للاختبار',
      'tenant_name': 'المستأجر',
      'advertiser_name': 'المعلن',
      'status': 'active',
      'tenant_accepted': true,
      'advertiser_accepted': true,
      'my_accepted': true,
      'can_revise': false,
      'can_accept': false,
      'can_cancel': false,
      'can_terminate': true,
      'in_app_only': true,
      'official_registration': false,
      'current_revision': {
        'id': 310,
        'revision_number': 2,
        'rent_amount': 150000,
        'currency': 'YER',
        'rent_cadence': 'monthly',
        'start_date': '2026-10-01',
        'end_date': '2027-10-01',
        'payment_due_day': 5,
        'created_by_user_id': 1,
        'created_by_name': 'المعلن',
      },
    });

    expect(contract.isActive, isTrue);
    expect(contract.inAppOnly, isTrue);
    expect(contract.officialRegistration, isFalse);
    expect(contract.tenantAccepted, isTrue);
    expect(contract.advertiserAccepted, isTrue);
    expect(contract.currentRevision.paymentDueDay, 5);
    expect(contract.statusLabel, 'مقبول داخل التطبيق');
  });
}
