import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/bookings/domain/booking_models.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';

void main() {
  test('Phase 4 conversation parses listing status and pagination', () {
    final details = MessageThreadDetails.fromJson({
      'thread': {
        'id': 8,
        'property_id': 12,
        'property_title': 'Apartment',
        'property_status': 'draft',
        'other_user': {'id': 2, 'name': 'Owner'},
        'unread_count': 0,
      },
      'messages': [
        {
          'id': 101,
          'sender_user_id': 3,
          'sender_name': 'Buyer',
          'client_message_id': 'm-8-10100000',
          'body': 'مرحبا',
          'is_mine': true,
          'created_at': '2026-09-08T12:00:00Z',
        }
      ],
      'pagination': {'has_more': true, 'next_before_id': 101},
    });

    expect(details.thread.isPropertyUnavailable, isTrue);
    expect(details.messages.single.clientMessageId, 'm-8-10100000');
    expect(details.hasMore, isTrue);
    expect(details.nextBeforeId, 101);
  });

  test('Phase 4 notification exposes exact booking and thread targets', () {
    final item = AppNotificationItem.fromJson({
      'id': 5,
      'type': 'booking_rescheduled',
      'title': 'موعد جديد',
      'entity_type': 'message_thread',
      'entity_id': 91,
      'data': {
        'booking_id': 44,
        'message_thread_id': 91,
      },
      'read_at': null,
    });

    expect(item.bookingId, 44);
    expect(item.messageThreadId, 91);
    expect(item.isRead, isFalse);
  });

  test('Phase 4 host reschedule is requester-acceptance aware', () {
    final booking = ViewingBooking.fromJson({
      'id': 44,
      'reference': 'VPHASE4',
      'requester_user_id': 2,
      'requester_name': 'Buyer',
      'host_user_id': 1,
      'host_name': 'Owner',
      'message_thread_id': 91,
      'target_type': 'property',
      'target_id': 7,
      'target_title': 'Apartment',
      'starts_at': '2026-09-18T10:00:00Z',
      'ends_at': '2026-09-18T11:00:00Z',
      'status': 'requested',
      'is_requester': true,
      'can_manage': false,
      'can_cancel': true,
      'can_reschedule': true,
      'can_confirm': true,
      'can_decline': false,
      'can_accept_reschedule': true,
      'awaiting_requester_confirmation': true,
    });

    expect(booking.canAcceptReschedule, isTrue);
    expect(booking.canConfirm, isTrue);
    expect(booking.statusLabel, 'بانتظار موافقتك');
  });

  test('Phase 4 host sees that requester approval is pending', () {
    final booking = ViewingBooking.fromJson({
      'id': 46,
      'reference': 'VHOSTWAIT',
      'requester_user_id': 2,
      'requester_name': 'Buyer',
      'host_user_id': 1,
      'host_name': 'Owner',
      'message_thread_id': 91,
      'target_type': 'property',
      'target_id': 7,
      'target_title': 'Apartment',
      'starts_at': '2026-09-18T10:00:00Z',
      'ends_at': '2026-09-18T11:00:00Z',
      'status': 'requested',
      'is_requester': false,
      'can_manage': true,
      'can_cancel': true,
      'can_reschedule': true,
      'can_confirm': false,
      'can_decline': false,
      'can_accept_reschedule': false,
      'awaiting_requester_confirmation': true,
    });

    expect(booking.canConfirm, isFalse);
    expect(booking.canDecline, isFalse);
    expect(booking.statusLabel, 'بانتظار موافقة طالب المعاينة');
  });

  test('Phase 4 completed action only appears after confirmed viewing ends', () {
    final booking = ViewingBooking.fromJson({
      'id': 45,
      'reference': 'VCOMPLETE',
      'requester_user_id': 2,
      'requester_name': 'Buyer',
      'host_user_id': 1,
      'host_name': 'Owner',
      'target_type': 'property',
      'target_id': 7,
      'target_title': 'Apartment',
      'starts_at': '2020-01-01T10:00:00Z',
      'ends_at': '2020-01-01T11:00:00Z',
      'status': 'confirmed',
      'is_requester': false,
      'can_manage': true,
      'can_cancel': true,
      'can_reschedule': true,
      'can_confirm': false,
      'can_decline': false,
      'can_accept_reschedule': false,
      'awaiting_requester_confirmation': false,
    });

    expect(booking.canComplete, isTrue);
  });
}
