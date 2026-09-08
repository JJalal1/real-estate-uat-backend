import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';
import 'package:real_estate_mobile/features/messages/domain/notification_destination.dart';

void main() {
  test('viewing notification prefers the exact booking over its conversation', () {
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

    expect(notificationDestination(item), '/bookings?booking=44');
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

  test('direct viewing entity falls back to the exact booking route', () {
    final item = AppNotificationItem(
      id: 3,
      type: 'viewing_requested',
      title: 'viewing',
      isRead: true,
      entityType: 'viewing_booking',
      entityId: 44,
    );

    expect(notificationDestination(item), '/bookings?booking=44');
  });
}
