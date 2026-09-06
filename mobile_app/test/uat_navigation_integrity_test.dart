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
    final support = File(
      'lib/features/support/presentation/support_center_screen.dart',
    ).readAsStringSync();

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
        notifications,
        contains("'$entityType'"),
        reason: 'Missing notification destination for $entityType',
      );
    }

    expect(notifications, contains("'/support?case=\${item.entityId}'"));
    expect(support, contains('final int? initialCaseId;'));
    expect(support, contains('await _showDetails(initialCaseId);'));
  });
}
