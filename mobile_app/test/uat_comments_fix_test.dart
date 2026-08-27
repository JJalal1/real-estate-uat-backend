import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/community/data/community_repository.dart';
import 'package:real_estate_mobile/features/community/domain/community_models.dart';
import 'package:real_estate_mobile/features/community/presentation/community_dialogs.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';

void main() {
  testWidgets('comment dialog closes without lifecycle exceptions',
      (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showCommunityTextDialog(
                  context,
                  title: 'إضافة تعليق',
                  hint: 'التعليق',
                );
              },
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'تعليق اختبار');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(result, 'تعليق اختبار');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rating and report dialogs own their controllers safely',
      (tester) async {
    CommunityRatingDialogResult? rating;
    CommunityReportDialogResult? report;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                FilledButton(
                  onPressed: () async {
                    rating = await showAdvertiserRatingDialog(
                      context,
                      initialRating: 4,
                      initialComment: 'جيد',
                    );
                  },
                  child: const Text('تقييم'),
                ),
                FilledButton(
                  onPressed: () async {
                    report = await showCommunityReportDialog(
                      context,
                      label: 'الإعلان',
                    );
                  },
                  child: const Text('بلاغ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('تقييم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(rating?.rating, 4);
    expect(rating?.comment, 'جيد');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('بلاغ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'تفاصيل بلاغ اختبار');
    await tester.tap(find.text('إرسال البلاغ'));
    await tester.pumpAndSettle();
    expect(report?.reason, 'misleading');
    expect(report?.details, 'تفاصيل بلاغ اختبار');
    expect(tester.takeException(), isNull);
  });

  testWidgets('property details refreshes comment count after community return',
      (tester) async {
    final propertyRepository = _FakePropertyRepository();
    final communityRepository = _FakeCommunityRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyRepositoryProvider.overrideWithValue(propertyRepository),
          communityRepositoryProvider.overrideWithValue(communityRepository),
        ],
        child: const MaterialApp(
          home: PropertyDetailsScreen(propertyId: 77),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The community section is below the initial ListView viewport. Scroll to
    // it first so the lazily-built children exist before checking the count.
    final communityButton = find.text('التعليقات وتقييم المعلن والبلاغات');
    await tester.scrollUntilVisible(communityButton, 300);
    expect(find.text('0 تعليق ظاهر'), findsOneWidget);
    await tester.tap(communityButton);
    await tester.pumpAndSettle();
    expect(find.text('التعليقات (3)'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(propertyRepository.detailsCalls, greaterThanOrEqualTo(2));
    await tester.scrollUntilVisible(communityButton, 300);
    expect(find.text('3 تعليق ظاهر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakePropertyRepository extends PropertyRepository {
  _FakePropertyRepository() : super(Dio(), AuthRepository(Dio()));

  int detailsCalls = 0;

  @override
  Future<PropertyDetails> details(int propertyId) async {
    detailsCalls++;
    return PropertyDetails(
      id: propertyId,
      title: 'عقار اختبار',
      purpose: 'sale',
      type: 'house',
      price: 100000,
      currency: 'YER',
      latitude: 15.3,
      longitude: 44.2,
      images: const [],
      status: 'published',
      isOwner: true,
      commentsCount: detailsCalls == 1 ? 0 : 3,
      advertiser: const AdvertiserCommunitySummary(
        id: 9,
        name: 'معلن اختبار',
        ratingAverage: 4.0,
        ratingCount: 1,
      ),
    );
  }
}

class _FakeCommunityRepository extends CommunityRepository {
  _FakeCommunityRepository() : super(Dio(), AuthRepository(Dio()));

  @override
  Future<List<ListingCommentItem>> comments(int propertyId) async {
    return List.generate(
      3,
      (index) => ListingCommentItem(
        id: index + 1,
        propertyId: propertyId,
        authorName: 'مستخدم ${index + 1}',
        body: 'تعليق ${index + 1}',
        status: 'visible',
        isOwner: false,
      ),
    );
  }

  @override
  Future<AdvertiserRatingSummary> ratingSummary(int advertiserId) async {
    return AdvertiserRatingSummary(
      advertiserId: advertiserId,
      advertiserName: 'معلن اختبار',
      average: 4,
      count: 1,
      distribution: const {4: 1},
    );
  }
}
