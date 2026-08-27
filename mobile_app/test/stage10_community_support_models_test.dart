import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/community/domain/community_models.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/support/domain/support_models.dart';

void main() {
  test('Stage 10 listing comment parses ownership and moderation state', () {
    final item = ListingCommentItem.fromJson({
      'id': 7,
      'property_id': 11,
      'author_user_id': 4,
      'author_name': 'Tester',
      'body': 'Visible comment',
      'status': 'visible',
      'is_owner': true,
      'created_at': '2026-08-20T10:00:00Z',
    });
    expect(item.id, 7);
    expect(item.authorName, 'Tester');
    expect(item.isOwner, isTrue);
    expect(item.status, 'visible');
  });

  test('Stage 10 advertiser rating summary parses aggregate and my rating', () {
    final summary = AdvertiserRatingSummary.fromJson({
      'advertiser_id': 9,
      'average': 4.5,
      'count': 2,
      'distribution': {'5': 1, '4': 1},
      'my_rating': {
        'id': 3,
        'rating': 5,
        'comment': 'Great',
        'status': 'visible',
      },
    });
    expect(summary.average, 4.5);
    expect(summary.count, 2);
    expect(summary.myRating?.rating, 5);
    expect(summary.distribution[5], 1);
  });

  test('Stage 10 support summary and private message models parse SLA state',
      () {
    final details = SupportCaseDetails.fromJson({
      'id': 21,
      'reference': 'SUP-TEST',
      'kind': 'report',
      'subject': 'Report',
      'description': 'Private report body',
      'status': 'in_progress',
      'priority': 'high',
      'escalation_level': 1,
      'escalated_at': '2026-08-20T12:00:00Z',
      'requester': {'id': 2, 'name': 'Requester', 'email': 'r@example.test'},
      'messages': [
        {
          'id': 1,
          'actor_name': 'Support',
          'actor_role': 'support',
          'is_internal': true,
          'body': 'Internal note',
        }
      ],
    });
    expect(details.summary.isEscalated, isTrue);
    expect(details.requesterName, 'Requester');
    expect(details.messages.single.isInternal, isTrue);
  });

  test('property details exposes Stage 10 advertiser and comment summary', () {
    final item = PropertyDetails.fromJson({
      'id': 5,
      'title': 'Home',
      'purpose': 'sale',
      'type': 'house',
      'price': 100,
      'currency': 'YER',
      'latitude': 15.3,
      'longitude': 44.2,
      'status': 'published',
      'images': [],
      'advertiser': {
        'id': 8,
        'name': 'Advertiser',
        'rating_average': 4.2,
        'rating_count': 6,
      },
      'community': {'comments_count': 3},
      'similar': [],
    });
    expect(item.advertiser?.id, 8);
    expect(item.advertiser?.ratingAverage, 4.2);
    expect(item.commentsCount, 3);
  });
}
