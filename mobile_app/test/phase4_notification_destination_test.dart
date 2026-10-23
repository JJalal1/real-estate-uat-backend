import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/domain/notification_destination.dart';

void main() {
  test('legacy viewing notification keeps its ordinary conversation', () {
    final item = AppNotificationItem(
      id: 1,
      type: 'booking_confirmed',
      title: 'confirmed',
      isRead: false,
      entityType: 'message_thread',
      entityId: 91,
      data: const <String, dynamic>{
        'booking_id': 44,
        'message_thread_id': 91,
      },
    );

    expect(notificationDestination(item), '/messages/91');
  });

  test('message notification opens the exact conversation', () {
    final item = AppNotificationItem(
      id: 2,
      type: 'message_received',
      title: 'message',
      isRead: false,
      entityType: 'message_thread',
      entityId: 91,
      data: const <String, dynamic>{'message_thread_id': 91},
    );

    expect(notificationDestination(item), '/messages/91');
  });

  test('legacy viewing entity without a thread falls back to messages', () {
    final item = AppNotificationItem(
      id: 3,
      type: 'viewing_requested',
      title: 'viewing',
      isRead: true,
      entityType: 'viewing_booking',
      entityId: 44,
    );

    expect(notificationDestination(item), '/messages');
  });
}
