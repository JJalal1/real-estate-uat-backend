import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_market_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_screen.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final viewport in [(const Size(320, 915), 1.0), (const Size(320, 915), 2.4),
    (const Size(412, 915), 2.4), (const Size(600, 280), 2.4)]) {
    testWidgets('comparison aligns real criteria and opens fourth property $viewport', (tester) async {
      final repo = _Properties();
      final key = GlobalKey();
      await _open(tester, repo, size: viewport.$1, scale: viewport.$2, captureKey: key);
      expect(repo.detailIds, [2, 4, 6, 8]);
      expect(repo.saiIds, [2, 4, 6, 8]);
      expect(find.text('4 عقارات للمقارنة'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('تعذر تحميل المؤشر الآن'), findsOneWidget);
      expect(find.text('البيانات غير كافية (2/5)'), findsOneWidget);
      expect(find.textContaining('وسيط المقارنات: 150,000 YER'), findsNWidgets(2));
      expect(find.text('السعي المعتمد 8'), findsOneWidget);
      final title = tester.widget<Text>(find.text(_title(8)));
      expect(title.maxLines, isNull);
      final y2 = tester.getCenter(find.text('موقع 2')).dy;
      final y8 = tester.getCenter(find.text('موقع 8')).dy;
      expect(y2, closeTo(y8, .01), reason: 'The same criterion stays on one comparison row.');
      await Scrollable.ensureVisible(tester.element(find.text(_title(2))), alignment: .5);
      await tester.pumpAndSettle();
      await captureDesign(tester, key, 'property-compare-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      final buttons = find.widgetWithText(AppButton, 'فتح العقار');
      expect(buttons, findsNWidgets(4));
      await Scrollable.ensureVisible(tester.element(buttons.at(3)), alignment: .5);
      await tester.pumpAndSettle();
      expect(buttons.at(3).hitTestable(), findsOneWidget);
      await tester.tap(buttons.at(3));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('comparison keeps minimum selection and full load retry', (tester) async {
    final repo = _Properties()..fail = true;
    await _open(tester, repo, ids: const [2, 4]);
    expect(find.byType(AppErrorState), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget);
    expect(repo.detailIds, [2, 2, 4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison with one unique valid id retains empty guidance', (tester) async {
    final repo = _Properties();
    await _open(tester, repo, ids: const [0, -1, 2, 2]);
    expect(repo.detailIds, [2]);
    expect(find.text('اختر عقارين على الأقل'), findsOneWidget);
    expect(find.byType(Table), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String _title(int id) => 'عقار $id في صنعاء بالقرب من الخدمات عنوان عربي طويل ABC-$id';
class _Properties extends PropertyRepository {
  _Properties() : super(Dio(), AuthRepository(Dio()));
  final detailIds = <int>[];
  final saiIds = <int>[];
  bool fail = false;
  @override
  Future<PropertyDetails> details(int propertyId) async {
    detailIds.add(propertyId);
    if (fail) throw StateError('details unavailable');
    return PropertyDetails(id: propertyId, title: _title(propertyId), purpose: 'sale',
      type: 'house', price: (propertyId * 100000).toDouble(), currency: 'YER', latitude: 15.3,
      longitude: 44.2, images: const [], areaValue: (propertyId * 50).toDouble(),
      areaUnit: 'sqm', bedrooms: propertyId, bathrooms: 2, address: 'موقع $propertyId');
  }
  @override
  Future<PropertySaiEnvelope> sai(int propertyId) async {
    saiIds.add(propertyId);
    return PropertySaiEnvelope(sai: PropertySai(ratePercent: 0, payer: 'buyer',
      payerLabel: 'المشتري', calculationBasis: 'server', displayText: 'السعي المعتمد $propertyId'));
  }
}
class _Market extends PropertyMarketRepository {
  _Market() : super(Dio());
  @override
  Future<PropertyMarketContext> context(int propertyId) async {
    if (propertyId == 6) throw StateError('market unavailable');
    return PropertyMarketContext(sufficientData: propertyId != 4, sampleCount: propertyId == 4 ? 2 : 8,
      minimumSampleSize: 5, medianPrice: 150000, position: 'near_comparable_median');
  }
}
Future<void> _open(WidgetTester tester, _Properties repo, {
  Size size = const Size(320, 915), double scale = 1, GlobalKey? captureKey,
  List<int> ids = const [0, -1, 2, 2, 4, 6, 8, 10],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/compare', routes: [
    GoRoute(path: '/compare', builder: (_, __) => PropertyCompareScreen(propertyIds: ids)),
    GoRoute(path: '/properties/:id', builder: (_, state) => Scaffold(body: Text('DETAIL ${state.pathParameters['id']}'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    propertyRepositoryProvider.overrideWithValue(repo), propertyMarketRepositoryProvider.overrideWithValue(_Market()),
  ], child: RepaintBoundary(key: captureKey, child: MaterialApp.router(
    theme: AppTheme.light, routerConfig: router, debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
  ))));
  await tester.pumpAndSettle();
}
