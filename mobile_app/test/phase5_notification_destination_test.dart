import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/domain/notification_destination.dart';

void main() {
  test('agreement notice opens its own conversation', () {
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
    expect(notificationDestination(item), '/messages/91');
  });

  test('contract notice opens its own conversation', () {
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
    expect(notificationDestination(item), '/messages/91');
  });

  test('archived notices retain a transaction or property destination without an overview', () {
    AppNotificationItem notice(String type, {Map<String, dynamic> data = const {}}) =>
        AppNotificationItem(id: 4, type: type, title: type, isRead: true, data: data);
    expect(notificationDestination(notice('agreement_revised', data: {'agreement_id': 12})), '/agreements/12');
    expect(notificationDestination(notice('rental_contract_active', data: {
      'agreement_id': 12, 'rental_contract_id': 31,
    })), '/rental-contracts/31');
    expect(notificationDestination(notice('agreement_closed')), '/messages');
    expect(notificationDestination(notice('saved_search_match', data: {'property_id': '8'})), '/properties/8');
    expect(notificationDestination(notice('saved_search_digest')), '/marketplace-search');
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

  test('support deal reminder opens the exact task before its thread', () {
    const item = AppNotificationItem(
      id: 3,
      type: 'support_deal_confirmation_reminder',
      title: 'confirmation reminder',
      isRead: false,
      entityType: 'support_task',
      entityId: 51,
      data: {'deal_id': 20, 'message_thread_id': 91},
    );

    expect(notificationDestination(item), '/support/workspace/tasks/51');
  });

  test('external closing notice can restore its task from payload data', () {
    const item = AppNotificationItem(
      id: 4,
      type: 'support_external_listing_closure',
      title: 'external listing closure',
      isRead: false,
      entityType: 'support_task',
      data: {'task_id': '52'},
    );

    expect(notificationDestination(item), '/support/workspace/tasks/52');
  });
}
