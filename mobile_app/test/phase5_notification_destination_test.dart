import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/domain/notification_destination.dart';

void main() {
  test('agreement notification beats conversation fallback and opens agreement', () {
    final item = AppNotificationItem(
      id: 1,
      type: 'agreement_revised',
      title: 'agreement',
      isRead: false,
      entityType: 'property_agreement',
      entityId: 12,
      data: const <String, dynamic>{
        'agreement_id': 12,
        'message_thread_id': 91,
      },
    );

    expect(item.agreementId, 12);
    expect(notificationDestination(item), '/agreements/12');
  });

  test('rental contract notification beats conversation fallback and opens contract', () {
    final item = AppNotificationItem(
      id: 2,
      type: 'rental_contract_active',
      title: 'contract',
      isRead: false,
      entityType: 'rental_contract',
      entityId: 31,
      data: const <String, dynamic>{
        'rental_contract_id': 31,
        'agreement_id': 12,
        'message_thread_id': 91,
      },
    );

    expect(item.rentalContractId, 31);
    expect(notificationDestination(item), '/rental-contracts/31');
  });

  test('existing message routing remains a message route', () {
    final item = AppNotificationItem(
      id: 3,
      type: 'message_received',
      title: 'message',
      isRead: false,
      entityType: 'message_thread',
      entityId: 91,
      data: const <String, dynamic>{'message_thread_id': 91},
    );

    expect(notificationDestination(item), '/messages/91');
  });
}
