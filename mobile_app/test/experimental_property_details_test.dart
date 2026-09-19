import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/property_market_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_details_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_market_context_card.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_sai_public_line.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);

  for (final viewport in [
    for (final width in [320.0, 412.0, 600.0])
      for (final scale in [1.0, 2.4]) (Size(width, 915), scale),
    (const Size(600, 280), 2.4),
  ]) {
    testWidgets('details RTL ${viewport.$1} / ${viewport.$2} preserves real sections', (tester) async {
      final key = GlobalKey();
      await _open(tester, size: viewport.$1, scale: viewport.$2, captureKey: key);
      expect(tester.takeException(), isNull);
      expect(find.byType(AppActionDock), findsOneWidget);
      expect(find.byTooltip('إدارة الإعلان'), findsNothing);
      await _reveal(tester, find.text(_title));
      final title = tester.widget<Text>(find.text(_title));
      expect(title.maxLines, isNull);
      await captureDesign(tester, key,
          'property-details-summary-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      await _reveal(tester, find.text(_saiText));
      expect(find.text(_saiText), findsOneWidget);
      for (final text in ['الموقع', 'مواصفات العقار', 'وصف العقار', 'هوية المعلن متحققة', 'موقع المكتب مسجل']) {
        await _reveal(tester, find.text(text));
        expect(tester.takeException(), isNull, reason: text);
      }
      expect(find.text('السجل التجاري متحقق'), findsNothing);
      expect(find.text('بيانات مهنية متحققة'), findsNothing);
      await _reveal(tester, find.text('التعليقات والتقييم والبلاغات'));
      await captureDesign(tester, key,
          'property-details-advertiser-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      await _reveal(tester, find.text('الهاتف'));
      expect(find.text('777123456'), findsOneWidget);
      await _reveal(tester, find.text('واتساب'));
      expect(find.text('777654321'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final record in [(true, 'published'), (true, 'draft'), (false, 'archived')]) {
    testWidgets('details retains owner/status visibility $record', (tester) async {
      await _open(tester, property: _property(owner: record.$1, status: record.$2));
      expect(find.byType(AppActionDock), findsNothing);
      expect(find.byTooltip('حفظ في المفضلة'), findsNothing);
      await _reveal(tester, find.text(_title));
      expect(find.byTooltip('إدارة الإعلان'), record.$1 ? findsOneWidget : findsNothing);
      if (record.$1) {
        await tester.tap(find.byTooltip('إدارة الإعلان'));
        await tester.pumpAndSettle();
        expect(find.text('تعديل الإعلان'), findsOneWidget);
        expect(find.text('إعلاناتي'), findsOneWidget);
      } else {
        await _reveal(tester, find.byType(AppUnavailableState));
        expect(find.byType(AppUnavailableState), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('public message and viewing keep their original auth route', (tester) async {
    final router = await _open(tester, size: const Size(320, 568), scale: 2.4);
    for (final label in ['مراسلة', 'طلب معاينة']) {
      final button = find.widgetWithText(AppButton, label);
      await Scrollable.ensureVisible(tester.element(button));
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('AUTH GATE'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('details loading and failure retain successful retry', (tester) async {
    final response = Completer<PropertyDetails>();
    var calls = 0;
    await _open(tester, settle: false, load: () {
      calls++;
      return calls == 1 ? response.future : Future.value(_property());
    });
    expect(find.byType(AppSkeleton), findsWidgets);
    response.completeError(StateError('test unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorState), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(AppActionDock), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const _title = 'منزل واسع في صنعاء شارع حدة بالقرب من الخدمات ABC-123';
const _saiText = 'نص السعي المعتمد من الخادم كما هو دون إعادة احتساب';

PropertyDetails _property({bool owner = false, String status = 'published'}) => PropertyDetails(
  id: 77, title: _title, purpose: 'sale', type: 'house', price: 12500000,
  currency: 'YER', latitude: 15.3, longitude: 44.2, images: const [],
  status: status, isOwner: owner, areaValue: 250, areaUnit: 'sqm', bedrooms: 4,
  bathrooms: 2, hasParking: true, tenureType: 'freehold', buildingFacade: 'north',
  description: 'وصف العقار الحقيقي القادم من نموذج البيانات مع مساحة كافية للنص الطويل.',
  address: 'صنعاء، مديرية السبعين، شارع حدة ABC-123',
  contactPhone: '777123456', contactWhatsapp: '777654321', commentsCount: 8,
  advertiser: const AdvertiserCommunitySummary(
    id: 9, name: 'مكتب المعلن ذو الاسم العربي الطويل للعقارات',
    ratingAverage: 4.2, ratingCount: 12, verificationStatus: 'approved',
    verificationLabel: 'مكتب عقاري', verificationFlags: {
      'identity_reviewed': true, 'office_location_registered': true,
      'commercial_register_reviewed': false,
    },
  ),
);

class _AnonymousAuth extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}

Future<GoRouter> _open(WidgetTester tester, {
  Size size = const Size(412, 915), double scale = 1,
  GlobalKey? captureKey, PropertyDetails? property,
  Future<PropertyDetails> Function()? load, bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/properties/77', routes: [
    GoRoute(path: '/properties/:id', builder: (_, __) => const PropertyDetailsScreen(propertyId: 77)),
    GoRoute(path: '/auth', builder: (_, __) => const Scaffold(body: Text('AUTH GATE'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_AnonymousAuth.new),
      propertyDetailsProvider(77).overrideWith((ref) => load?.call() ?? Future.value(property ?? _property())),
      propertySaiPublicProvider(77).overrideWith((ref) async => const PropertySaiEnvelope(
        sai: PropertySai(ratePercent: 0, payer: 'owner', payerLabel: 'المالك', calculationBasis: 'server', displayText: _saiText),
      )),
      propertyMarketContextProvider(77).overrideWith((ref) async => const PropertyMarketContext(sufficientData: false, sampleCount: 0)),
    ],
    child: RepaintBoundary(key: captureKey, child: MaterialApp.router(
      theme: AppTheme.light, routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    )),
  ));
  if (settle) await tester.pumpAndSettle();
  return router;
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scrollable = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(target, 250, scrollable: scrollable, maxScrolls: 150);
  await tester.pumpAndSettle();
}
