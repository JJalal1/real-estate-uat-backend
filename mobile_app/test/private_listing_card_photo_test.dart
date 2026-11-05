import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_client.dart';
import 'package:real_estate_mobile/core/widgets/property_card_gallery.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';

import 'support/owner_ux_fixtures.dart';

const _origin = 'https://real-estate-uat-api-frankfurt.onrender.com';
const _foreignOrigin = 'https://foreign-image.example';

PropertyDetails _listing({int images = 1, String origin = _origin, String status = 'draft'}) =>
    PropertyDetails.fromJson({
      'id': 97, 'title': 'إعلان اختبار الصورة الخاصة', 'type': 'apartment',
      'purpose': 'rent', 'status': status, 'review_status': status == 'published' ? 'approved' : 'draft',
      'price': 50000, 'currency': 'YER', 'address': 'عنوان اختبار',
      'bedrooms': 3, 'bathrooms': 2,
      'images': [for (var index = 0; index < images; index++) {
        'id': 801 + index, 'url': '$origin/api/property-media/${801 + index}',
        'is_primary': index == 0, 'sort_order': index,
      }],
    });

Dio _images(List<RequestOptions> calls, {required bool private}) {
  final dio = Dio(BaseOptions(baseUrl: '$_origin/api'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    calls.add(request);
    if (private && request.headers['Authorization'] != 'Bearer synthetic-ux-only') {
      handler.reject(DioException.badResponse(statusCode: 404, requestOptions: request,
        response: Response(requestOptions: request, statusCode: 404)));
      return;
    }
    handler.resolve(Response<List<int>>(requestOptions: request, statusCode: 200, data: uxImage,
      headers: Headers.fromMap({'content-type': ['image/png'],
        'cache-control': [private ? 'private, no-store' : 'public, max-age=86400']})));
  }));
  addTearDown(() => dio.close(force: true));
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);

  for (final count in [1, 2]) {
    testWidgets('own draft card authenticates every visible photo ($count images)', (tester) async {
      final calls = <RequestOptions>[];
      final dio = _images(calls, private: true);
      final scope = uxContainer(user: uxUser(type: 'broker'), extra: [
        dioProvider.overrideWithValue(dio),
        myListingsProvider.overrideWith((ref) async => [_listing(images: count)]),
      ]);
      await pumpUx(tester, scope, const MyListingsScreen());
      expect(calls, isNotEmpty);
      expect(calls.map((request) => request.uri.path), contains('/api/property-media/801'));
      if (count == 2) {
        final gallery = find.byKey(const ValueKey('property-card-gallery'));
        tester.widget<PageView>(gallery).controller!.jumpToPage(1);
        await uxFrames(tester);
        expect(calls.map((request) => request.uri.path), contains('/api/property-media/802'));
      }
      for (final request in calls) {
        expect(request.uri.origin, _origin);
        expect(request.headers['Authorization'], 'Bearer synthetic-ux-only');
      }
      expect(find.descendant(of: find.byType(PropertyCardGallery), matching: find.byType(Image)), findsWidgets);
      expect(find.text('إعادة تحميل الصورة'), findsNothing);
      expect(tester.takeException(), isNull);
      await closeUx(tester);
    });
  }

  testWidgets('published marketplace cards remain unauthenticated', (tester) async {
    final calls = <RequestOptions>[];
    final dio = _images(calls, private: false);
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [dioProvider.overrideWithValue(dio)]);
    await pumpUx(tester, scope, Scaffold(body: PropertySummaryCard(
      property: _listing(status: 'published').toSummary(), onTap: () {})));
    expect(calls, isNotEmpty);
    for (final request in calls) {
      expect(request.headers.containsKey('Authorization'), isFalse);
    }
    expect(find.descendant(of: find.byType(PropertyCardGallery), matching: find.byType(Image)), findsWidgets);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });

  testWidgets('private card refuses a foreign media origin before sending credentials', (tester) async {
    final calls = <RequestOptions>[];
    final dio = _images(calls, private: true);
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [
      dioProvider.overrideWithValue(dio),
      myListingsProvider.overrideWith((ref) async => [_listing(origin: _foreignOrigin)]),
    ]);
    await pumpUx(tester, scope, const MyListingsScreen());
    expect(calls, isEmpty);
    expect(find.text('إعادة تحميل الصورة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeUx(tester);
  });
}
