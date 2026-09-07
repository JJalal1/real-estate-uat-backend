import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Listing publish and viewing flow source guards', () {
    test('Phase 2 editor preserves explicit parking serialization', () async {
      final editor = await File(
        'lib/features/properties/presentation/listing_editor_screen.dart',
      ).readAsString();
      final repository = await File(
        'lib/features/properties/data/property_repository.dart',
      ).readAsString();

      expect(editor, contains('String? _parkingChoice;'));
      expect(editor, contains("_parkingChoice == 'yes'"));
      expect(repository, contains("fields['has_parking'] = parking ? 1 : 0;"));
    });

    test('listing editor separates draft preview and submit actions', () async {
      final legacyEntry = await File(
        'lib/features/properties/presentation/add_property_wizard_screen.dart',
      ).readAsString();
      final editor = await File(
        'lib/features/properties/presentation/listing_editor_screen.dart',
      ).readAsString();

      expect(legacyEntry, contains('ListingEditorScreen'));
      expect(editor, contains("value: 'freehold'"));
      expect(editor, contains("value: 'waqf'"));
      expect(editor, contains("label: 'حفظ مسودة'"));
      expect(editor, contains("label: 'معاينة'"));
      expect(editor, contains("label: 'إرسال للمراجعة'"));
      expect(editor, contains('submitForReview: false'));
      expect(editor, contains('submitListing(draft.id)'));
      expect(editor, isNot(contains('submitForReview: true')));
      expect(editor, contains('هذه المعاينة لا تحفظ ولا تغيّر حالة الإعلان'));
    });

    test('property-specific owner evidence only uses canonical editor', () async {
      final editor = await File(
        'lib/features/properties/presentation/listing_editor_screen.dart',
      ).readAsString();
      final listings = await File(
        'lib/features/properties/presentation/my_listings_screen.dart',
      ).readAsString();

      expect(editor, contains('إثبات علاقتك بهذا العقار'));
      expect(editor, contains('ownershipProofPath'));
      expect(editor, contains('ownerRelationshipType'));
      expect(editor, contains('documentOwnerName'));
      expect(listings, isNot(contains('إضافة إثبات')));
      expect(listings, isNot(contains('uploadProofDocuments')));
    });

    test('viewing request opens its linked conversation after creation', () async {
      final details = await File(
        'lib/features/properties/presentation/property_details_screen.dart',
      ).readAsString();
      final conversation = await File(
        'lib/features/messages/presentation/conversation_screen.dart',
      ).readAsString();

      expect(details, contains('booking.messageThreadId'));
      expect(details, contains("context.push('/messages/\$threadId')"));
      expect(conversation, contains('طلب معاينة مرتبط بهذه المحادثة'));
      expect(conversation, contains("_bookingAction('confirm')"));
      expect(conversation, contains("_bookingAction('reschedule')"));
    });
  });
}
