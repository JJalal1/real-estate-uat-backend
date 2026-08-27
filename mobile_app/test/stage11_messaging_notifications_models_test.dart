import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/messages/domain/message_models.dart';

void main() {
  test('message thread summary parses privacy-safe list payload', () {
    final item = MessageThreadSummary.fromJson({
      'id': 7,
      'property_id': 3,
      'property_title': 'Apartment',
      'other_user': {'id': 9, 'name': 'Advertiser'},
      'unread_count': 2,
      'last_message_preview': 'Hello',
    });
    expect(item.id, 7);
    expect(item.otherUserName, 'Advertiser');
    expect(item.unreadCount, 2);
  });

  test('notification parser detects unread state', () {
    final item = AppNotificationItem.fromJson({
      'id': 2,
      'type': 'message_received',
      'title': 'New message',
      'read_at': null,
    });
    expect(item.isRead, isFalse);
    expect(item.type, 'message_received');
  });

  test('conversation report summary does not require private message content',
      () {
    final report = ConversationReportSummary.fromJson({
      'id': 4,
      'thread_id': 8,
      'reporter_name': 'Reporter',
      'reason_code': 'abuse',
      'status': 'open',
    });
    expect(report.threadId, 8);
    expect(report.status, 'open');
  });
}
