import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Listing publish and viewing flow source guards', () {
    test('parking selection cannot be cleared and false is serialized explicitly',
        () async {
      final wizard = await File(
              'lib/features/properties/presentation/add_property_wizard_screen.dart')
          .readAsString();
      final repository =
          await File('lib/features/properties/data/property_repository.dart')
              .readAsString();

      expect(wizard.contains('String? _parkingChoice;'), isTrue);
      expect(wizard.contains("return _parkingChoice == 'yes';"), isTrue);
      expect(wizard.contains('if (value.isNotEmpty)'), isTrue);
      expect(repository.contains("fields['has_parking'] = parking ? 1 : 0;"),
          isTrue);
    });

    test('sale tenure and direct review submission are wired in the wizard',
        () async {
      final wizard = await File(
              'lib/features/properties/presentation/add_property_wizard_screen.dart')
          .readAsString();

      expect(
          wizard.contains(
              "const {'apartment', 'house', 'villa', 'land', 'farm'}.contains(_type)"),
          isTrue);
      expect(wizard.contains("ButtonSegment<String>(value: 'freehold', label: Text('حر'))"),
          isTrue);
      expect(wizard.contains("ButtonSegment<String>(value: 'waqf', label: Text('وقف'))"),
          isTrue);
      expect(wizard.contains('submitForReview: true'), isTrue);
      expect(wizard.contains('حالة الإعلان: قيد المراجعة'), isTrue);
      expect(wizard.contains('arabicRiyalAmountInWords(_priceController.text)'),
          isTrue);
    });

    test('viewing request opens its linked conversation after creation', () async {
      final details = await File(
              'lib/features/properties/presentation/property_details_screen.dart')
          .readAsString();
      final conversation = await File(
              'lib/features/messages/presentation/conversation_screen.dart')
          .readAsString();

      expect(details.contains('booking.messageThreadId'), isTrue);
      expect(details.contains("context.push('/messages/\$threadId')"), isTrue);
      expect(conversation.contains('طلب معاينة مرتبط بهذه المحادثة'), isTrue);
      expect(conversation.contains("_bookingAction('confirm')"), isTrue);
      expect(conversation.contains("_bookingAction('reschedule')"), isTrue);
    });
  });
}
