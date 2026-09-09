import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/data/property_market_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_market_context_card.dart';

void main() {
  testWidgets('market context shows trustworthy insufficient-data state',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMarketRepositoryProvider.overrideWithValue(
            _FakeMarketRepository(
              const PropertyMarketContext(
                sufficientData: false,
                sampleCount: 3,
                minimumSampleSize: 5,
                message:
                    'البيانات الحالية غير كافية لتقديم مؤشر سعري موثوق لهذا العقار.',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PropertyMarketContextCard(
              propertyId: 77,
              currency: 'YER',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('مؤشر السوق'), findsOneWidget);
    expect(find.textContaining('البيانات الحالية غير كافية'), findsOneWidget);
    expect(find.text('3 من 5 عقارات مقارنة'), findsOneWidget);
    expect(find.textContaining('وسيط السعر'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('market context renders platform comparables without valuation claim',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyMarketRepositoryProvider.overrideWithValue(
            _FakeMarketRepository(
              const PropertyMarketContext(
                sufficientData: true,
                sampleCount: 8,
                medianPrice: 95000000,
                medianPricePerM2: 475000,
                deltaFromMedianPercent: -5.3,
                position: 'near_comparable_median',
                disclaimer:
                    'مؤشر استرشادي من عقارات منشورة ومعتمدة داخل المنصة، وليس تقييماً رسمياً أو ضماناً لسعر الصفقة.',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PropertyMarketContextCard(
              propertyId: 88,
              currency: 'YER',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('قريب من وسيط العقارات المقارنة'), findsOneWidget);
    expect(find.text('8 مقارنة'), findsOneWidget);
    expect(find.textContaining('95,000,000 YER'), findsOneWidget);
    expect(find.textContaining('5.3% أقل من الوسيط'), findsOneWidget);
    expect(find.textContaining('ليس تقييماً رسمياً'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeMarketRepository extends PropertyMarketRepository {
  _FakeMarketRepository(this.value) : super(Dio());

  final PropertyMarketContext value;

  @override
  Future<PropertyMarketContext> context(int propertyId) async => value;
}
