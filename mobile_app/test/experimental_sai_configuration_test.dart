import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_sai_configuration_sheet.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final viewport in [
    (const Size(320, 915), 1.0),
    (const Size(320, 915), 2.4),
    (const Size(600, 280), 2.4),
  ]) {
    for (final owner in [true, false]) {
      testWidgets('Sai RTL $viewport owner=$owner preserves terms payload', (tester) async {
        final repository = _Repository(owner: owner, rate: owner ? null : 3);
        final key = GlobalKey();
        await _open(tester, repository, size: viewport.$1, scale: viewport.$2, captureKey: key);
        final rate = owner ? 1 : 3;
        await _tap(tester, find.text('السعي $rate% يتحملها المشتري'));
        await captureDesign(tester, key,
          'sai-${owner ? 'owner' : 'broker'}-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
        await _tap(tester, _button(owner ? 'تأكيد السعي والمتابعة' : 'قبول'));
        expect(repository.calls, 1);
        expect(repository.propertyId, 9);
        expect(repository.payer, 'buyer');
        expect(repository.rate, owner ? isNull : 3);
        expect(repository.decision, owner ? isNull : 'accept');
        expect(find.text('RESULT true'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('professional rejection is persisted and returns false', (tester) async {
    final repository = _Repository(owner: false, rate: 20);
    await _open(tester, repository, purpose: 'rent');
    await _tap(tester, find.text('السعي 20% يتحملها المستأجر'));
    await _tap(tester, _button('رفض'));
    expect(repository.payer, 'tenant');
    expect(repository.rate, 20);
    expect(repository.decision, 'reject');
    expect(find.text('RESULT false'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payer then rate validation and zero-rate fallback remain unchanged', (tester) async {
    final repository = _Repository(owner: false, rate: 6);
    await _open(tester, repository);
    await _tap(tester, _button('تأكيد السعي والمتابعة'));
    expect(find.text('يجب تحديد الطرف الذي يتحمل السعي.'), findsOneWidget);
    expect(repository.calls, 0);
    await _tap(tester, find.text('السعي 6% يتحملها البائع'));
    await _tap(tester, _button('تأكيد السعي والمتابعة'));
    expect(find.text('نسبة السعي في البيع يجب أن تكون بين 0% و5%.'), findsOneWidget);
    expect(repository.calls, 0);
    final field = find.byType(TextField);
    await _reveal(tester, field);
    await tester.enterText(field, '0');
    await tester.pumpAndSettle();
    expect(find.text('سيُفعّل تلقائياً السعي الثابت 1%، وليس صفقة بدون سعي.'), findsOneWidget);
    await _tap(tester, _button('تأكيد السعي والمتابعة'));
    expect(repository.payer, 'seller');
    expect(repository.rate, 0);
    expect(repository.decision, isNull);
    expect(find.text('RESULT true'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed Sai save keeps selection for retry and cancel never writes', (tester) async {
    final repository = _Repository(owner: true, failOnce: true);
    await _open(tester, repository, purpose: 'rent');
    await _tap(tester, find.text('السعي 20% يتحملها المؤجر'));
    await _tap(tester, _button('تأكيد السعي والمتابعة'));
    expect(repository.calls, 1);
    expect(find.byType(AppInlineMessage), findsNWidgets(2));
    await _tap(tester, _button('تأكيد السعي والمتابعة'));
    expect(repository.calls, 2);
    expect(repository.payer, 'landlord');
    expect(repository.rate, isNull);
    expect(find.text('RESULT true'), findsOneWidget);
    await tester.tap(find.text('RESULT true'));
    await tester.pumpAndSettle();
    await _tap(tester, _button('العودة بدون إرسال'));
    expect(repository.calls, 2);
    expect(find.text('RESULT false'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Repository extends PropertyRepository {
  _Repository({required this.owner, double? rate, this.failOnce = false})
      : initialRate = rate, super(Dio(), AuthRepository(Dio()));
  final bool owner;
  final double? initialRate;
  bool failOnce;
  int calls = 0;
  int? propertyId;
  String? payer;
  double? rate;
  String? decision;
  @override
  Future<PropertySaiEnvelope> sai(int propertyId) async => PropertySaiEnvelope(
    management: PropertySaiManagement(configured: false, advertiserType: owner ? 'owner' : 'broker', requestedBrokerRatePercent: initialRate),
  );
  @override
  Future<PropertySaiEnvelope> configureSai(int propertyId, {required String payer, double? brokerRatePercent, String? platformTermsDecision}) async {
    calls++;
    this.propertyId = propertyId;
    this.payer = payer;
    rate = brokerRatePercent;
    decision = platformTermsDecision;
    if (failOnce) { failOnce = false; throw StateError('test connection failure'); }
    return PropertySaiEnvelope(management: PropertySaiManagement(
      configured: true, advertiserType: owner ? 'owner' : 'broker',
      platformTermsStatus: platformTermsDecision == 'reject' ? 'rejected' : 'accepted',
    ));
  }
}
Finder _button(String label) => find.widgetWithText(AppButton, label);
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}
Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
Future<void> _open(WidgetTester tester, _Repository repository, {
  Size size = const Size(320, 915), double scale = 1, GlobalKey? captureKey, String purpose = 'sale',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  bool? result;
  await tester.pumpWidget(RepaintBoundary(key: captureKey, child: MaterialApp(
    theme: AppTheme.light, debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: StatefulBuilder(builder: (context, setState) => Scaffold(body: FilledButton(
      onPressed: () async {
        final value = await showPropertySaiConfigurationSheet(context, repository: repository, propertyId: 9, purpose: purpose);
        setState(() => result = value);
      }, child: Text(result == null ? 'OPEN' : 'RESULT $result'),
    ))),
  )));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}
