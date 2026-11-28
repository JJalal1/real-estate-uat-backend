import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/category_property_facts.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';

import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot, finishWave6, pumpWave6;

class _ListingAuth extends AuthRepository {
  _ListingAuth(super.dio);

  @override
  Future<Options> requiredAuthOptions() async => Options();
}

void main() {
  test(
      'editing writes nullable multipart facts and suppresses other property types',
      () async {
    final dio = Dio();
    addTearDown(dio.close);
    Map<String, String>? parts;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      parts = Map.fromEntries((request.data as FormData).fields);
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': {
            'id': 42,
            'title': 'منزل عائلي',
            'type': 'house',
            'purpose': 'rent',
            'has_separate_majlis': false,
            'parking_spaces': 2,
            'land_use': 'residential',
          },
        },
      ));
    }));

    const input = PropertyListingInput(
      title: 'منزل عائلي',
      purpose: 'rent',
      type: 'house',
      price: 150000,
      latitude: 15,
      longitude: 44,
      hasParking: true,
      clearUnsetCategoryFacts: true,
      categoryFacts: CategoryPropertyFacts(
        parkingSpaces: 2,
        hasSeparateMajlis: false,
        hasMajlisBathroom: true,
        landUse: 'residential',
      ),
    );
    final saved = await PropertyRepository(dio, _ListingAuth(dio))
        .updateListing(42, input);

    expect(parts, containsPair('parking_spaces', '2'));
    expect(parts, containsPair('has_separate_majlis', '0'));
    expect(parts, containsPair('has_majlis_bathroom', ''));
    expect(parts, isNot(contains('land_use')));
    expect(saved.categoryFacts.parkingSpaces, 2);
    expect(saved.categoryFacts.hasSeparateMajlis, isFalse);
    expect(saved.categoryFacts.hasMajlisBathroom, isNull);
    expect(saved.categoryFacts.landUse, isNull);
  });

  testWidgets(
      'optional home facts survive draft recovery and depend on the separate majlis choice',
      (tester) async {
    final snapshot = editorSnapshot()..['parking'] = 'yes';
    final fields = snapshot['fields'] as Map;
    fields['parking_spaces'] = '2';
    fields['has_separate_majlis'] = 'yes';
    fields['has_majlis_bathroom'] = 'yes';
    final recovery = Wave6Recovery(snapshot);
    const key = ValueKey('listing-category-facts');
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery);

    final heading = find.byKey(key);
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pumpAndSettle();
    final count = find.descendant(
      of: find.byKey(const ValueKey('listing-category-parking_spaces')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(count).controller!.text, '2');
    final privateBath =
        find.byKey(const ValueKey('listing-category-has_majlis_bathroom'));
    expect(privateBath, findsOneWidget);
    expect(
        find.byKey(const ValueKey('listing-category-land_use')), findsNothing);

    final majlis =
        find.byKey(const ValueKey('listing-category-has_separate_majlis'));
    await tester.ensureVisible(majlis);
    await tester.tap(majlis);
    await tester.pumpAndSettle();
    await tester.tap(find.text('لا يوجد').last);
    await tester.pumpAndSettle();
    expect(privateBath, findsNothing);
    await tester.pump(const Duration(seconds: 1));

    final saved = recovery.snapshot!['fields'] as Map;
    expect(saved['parking_spaces'], '2');
    expect(saved['has_separate_majlis'], 'no');
    expect(saved['has_majlis_bathroom'], isEmpty);
    expect(tester.takeException(), isNull);
    await finishWave6(tester);
  });
}
