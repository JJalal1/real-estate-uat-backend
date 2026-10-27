import 'package:flutter_test/flutter_test.dart';
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
  });
  test('reviewer receives ready video without private original paths', () {
    final detail = ReviewListingDetail.fromJson({
      'id': 7, 'video': {
        'id': 13, 'status': 'ready', 'moderation_status': 'pending',
        'poster_url': 'https://video.example.test/api/property-videos/13/poster',
        'stream_url': 'https://video.example.test/api/property-videos/13/stream',
        'original_path': 'private/secret.mp4',
      },
    });
    expect(detail.videoStatus, 'ready');
    expect(detail.video?.id, 13);
    expect(detail.video?.streamUrl, endsWith('/stream'));
    final pending = ReviewListingDetail.fromJson({
      'id': 7, 'video': {'id': 13, 'status': 'processing'}
    });
    expect(pending.videoStatus, 'processing');
    expect(pending.video, isNull);
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
