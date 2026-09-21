import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deep links fail safely and legacy placeholder chat is unreachable', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();

    expect(router, contains('errorBuilder:'));
    expect(router, contains("int.tryParse(state.pathParameters['id'] ?? '')"));
    expect(router, isNot(contains('int.parse(state.pathParameters')));
    expect(router, isNot(contains("path: '/chats/:id'")));
    expect(router, isNot(contains('ChatConversationScreen')));
  });

  test('current notification entity types have working destinations', () {
    final notifications = File(
      'lib/features/messages/presentation/notifications_screen.dart',
    ).readAsStringSync();
    final destinations = File(
      'lib/features/messages/domain/notification_destination.dart',
    ).readAsStringSync();
    final support = File(
      'lib/features/support/presentation/support_center_screen.dart',
    ).readAsStringSync();

    expect(
      notifications,
      contains("import '../domain/notification_destination.dart';"),
    );
    expect(notifications, contains('notificationDestination(item)'));

    for (final entityType in <String>[
      'message_thread',
      'account_verification_profile',
      'account_verification',
      'support_case',
      'support_task',
      'viewing_booking',
      'property',
      'service_order',
    ]) {
      expect(
        destinations,
        contains("'$entityType'"),
        reason: 'Missing notification destination for $entityType',
      );
    }

    expect(destinations, contains("'/support?case=\${item.entityId}'"));
    expect(support, contains('final int? initialCaseId;'));
    expect(support, contains('await _showDetails(initialCaseId);'));
  });
  test('property contact starts in conversation and external call is tracked', () {
    final details = File(
      'lib/features/properties/presentation/property_details_screen.dart',
    ).readAsStringSync();
    final conversation = File(
      'lib/features/messages/presentation/conversation_screen.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/messages/data/message_repository.dart',
    ).readAsStringSync();

    expect(details, contains("'تواصل مع المعلن'"));
    expect(details, isNot(contains("title: 'الهاتف'")));
    expect(details, isNot(contains("title: 'واتساب'")));
    expect(details, isNot(contains("label: 'طلب معاينة'")));
    expect(conversation, contains("tooltip: 'اتصال بالمعلن'"));
    expect(conversation, contains('item.isCallStarted'));
    expect(repository, contains('startExternalCall'));
  });

}
