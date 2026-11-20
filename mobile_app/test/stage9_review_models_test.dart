import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/reviews/domain/listing_duplicate_candidate.dart';
import 'package:real_estate_mobile/features/reviews/domain/listing_review_models.dart';

void main() {
  test('Stage 9 review listing parses workflow fields', () {
    final item = ReviewListingItem.fromJson({
      'id': 9,
      'title': 'A',
      'purpose': 'sale',
      'type': 'house',
      'price': 12,
      'review_status': 'submitted',
      'owner': {'name': 'Owner'},
      'proof_documents': [
        {'id': 1}
      ]
    });
    expect(item.id, 9);
    expect(item.reviewStatus, 'submitted');
    expect(item.proofCount, 1);
    expect(item.duplicateDetection, isNull);
  });
  test('only a known published listing supplies a duplicate rejection target', () {
    final row = <String, dynamic>{
      'listing_id': 106,
      'duplicate_detection_source': 'algorithm',
      'duplicate_detection_reason': ' نفس الوحدة ',
    };
    final legacy = ListingDuplicateCandidate.fromJson({...row, 'status': 'published'});
    expect(legacy.canRejectAsDuplicate, isTrue);
    expect(legacy.detection?.source, ListingDuplicateSource.algorithm);
    expect(legacy.detection?.reason, 'نفس الوحدة');
    expect(ListingDuplicateCandidate.fromJson({
      ...row, 'status': 'published', 'published': false,
    }).canRejectAsDuplicate, isFalse);
    expect(ListingDuplicateCandidate.fromJson(row).canRejectAsDuplicate, isFalse);
    expect(ListingDuplicateCandidate.fromJson({'published': true}).canRejectAsDuplicate, isFalse);
  });
  test('publication block parses active state', () {
    final b = PublicationBlockItem.fromJson({
      'id': 4,
      'property_asset_id': 8,
      'purpose': 'sale',
      'is_active': true,
      'reason': 'x'
    });
    expect(b.isActive, isTrue);
    expect(b.propertyAssetId, 8);
  });
}
