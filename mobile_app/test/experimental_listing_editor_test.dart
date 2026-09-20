import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/domain/property_identity.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final viewport in [
    (const Size(320, 915), 1.0),
    (const Size(320, 915), 2.4),
    (const Size(412, 915), 2.4),
    (const Size(600, 280), 2.4),
  ]) {
    testWidgets('editor five RTL steps and draft payload $viewport', (tester) async {
      final repository = _Repository();
      final key = GlobalKey();
      await _open(tester, repository, size: viewport.$1, scale: viewport.$2, captureKey: key);
      expect(find.text('مطلوب تصحيح قبل إعادة الإرسال'), findsOneWidget);
      for (var step = 0; step < 5; step++) {
        expect(find.text('الخطوة ${step + 1} من 5'), findsOneWidget);
        await _reveal(tester, find.text(_headings[step]));
        expect(tester.takeException(), isNull, reason: 'step $step');
        if (step == 0 || step == 2 || step == 4) {
          await captureDesign(tester, key,
            'listing-editor-$step-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
        }
        if (step < 4) await _tap(tester, _button('التالي'));
      }
      await _tap(tester, _button('السابق'));
      expect(_field('الإيجار الشهري بالريال اليمني *'), findsOneWidget);
      expect(tester.widget<TextField>(_field('الإيجار الشهري بالريال اليمني *')).controller!.text, '50000');
      await _tap(tester, _button('التالي'));
      await _tap(tester, _button('حفظ مسودة'), settle: false);
      expect(repository.input, isNotNull);
      expect(repository.id, 9);
      expect(repository.submitForReview, isFalse);
      expect(repository.replaceImages, isFalse);
      expect(repository.input!.price, 150000);
      expect(repository.input!.monthlyRent, 50000);
      expect(repository.input!.rentalTermMonths, 12);
      expect(repository.input!.advanceMonths, 3);
      expect(repository.input!.title, _property.title);
      expect(repository.input!.buildingReference, 'عمارة النور 12');
      expect(repository.input!.unitNumber, 'A-2');
      expect(repository.input!.floorNumber, '3');
      expect(repository.input!.hasParking, isFalse);
      expect(repository.input!.areaValue, 4);
      expect(repository.input!.areaUnit, 'libna_sanaani');
      expect(repository.input!.address, 'صنعاء - حدة - شارع الزبيري');
      expect(repository.input!.latitude, 15.3);
      expect(repository.input!.longitude, 44.2);
      expect(repository.input!.priceDisplayMode, 'excludes_sai');
      for (final label in ['السابق', 'معاينة', 'حفظ مسودة', 'إرسال للمراجعة']) {
        expect(tester.widget<AppButton>(_button(label)).onPressed, isNull);
      }
      repository.saved.complete(_property);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('SAVED 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 568), const Size(600, 280)]) {
    testWidgets('listing preview closes without saving at $size / 2.4', (tester) async {
      final repository = _Repository();
      final key = GlobalKey();
      await _open(tester, repository, size: size, scale: 2.4, captureKey: key);
      for (var step = 0; step < 4; step++) { await _tap(tester, _button('التالي')); }
      await _tap(tester, _button('معاينة'));
      expect(find.text('هذه المعاينة لا تحفظ ولا تغيّر حالة الإعلان.'), findsOneWidget);
      expect(repository.input, isNull);
      await _reveal(tester, find.text(_property.title).last);
      await captureDesign(tester, key, 'listing-preview-${size.width.toInt()}-${size.height.toInt()}-2.4');
      await _tap(tester, _button('إغلاق المعاينة'));
      expect(find.text('معاينة قبل الإرسال'), findsNothing);
      expect(find.text('الخطوة 5 من 5'), findsOneWidget);
      expect(repository.input, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final selfVerification in [false, true]) {
    testWidgets('server duplicate blocks publish after draft save (self=$selfVerification)', (tester) async {
      final repository = _Repository(ready: true, selfVerification: selfVerification);
      repository.saved.complete(_submissionProperty);
      await _open(tester, repository, existing: _submissionProperty,
        size: const Size(600, 280), scale: 2.4);
      for (var step = 0; step < 4; step++) { await _tap(tester, _button('التالي')); }
      await _tap(tester, _button('إرسال للمراجعة'));
      expect(repository.input, isNull);
      await _tapWhileSaving(tester, find.text('حفظ وإرسال'));
      expect(repository.input, isNotNull);
      expect(repository.submitForReview, isFalse);
      expect(repository.identityCalls, 1);
      if (selfVerification) {
        expect(find.text('وجدنا عقاراً مشابهاً'), findsOneWidget);
        await _tapWhileSaving(tester, find.text('أؤكد أنه عقار مختلف'));
        expect(find.text('اكتب توضيحاً من 10 أحرف على الأقل.'), findsOneWidget);
        expect(repository.differenceNote, isNull);
        final field = _field('وضح الفرق *');
        await Scrollable.ensureVisible(tester.element(field), alignment: .5);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(field, 'وحدة مختلفة في نفس المبنى ABC-12');
        await tester.pump();
        await _tapWhileSaving(tester, find.text('أؤكد أنه عقار مختلف'));
        expect(repository.differenceType, 'different_address');
        expect(repository.differenceNote, 'وحدة مختلفة في نفس المبنى ABC-12');
      }
      await tester.pumpAndSettle();
      expect(repository.submitCalls, 0);
      expect(find.text('SAVED 9'), findsNothing);
      expect(find.text('الخطوة 5 من 5'), findsOneWidget);
      expect(find.text(selfVerification
        ? 'بعد التحقق ما زال هذا العقار مطابقاً لعقار مسجل، لذلك لا يمكن إرساله.'
        : 'هذا العقار أو هذه الوحدة مسجلة بالفعل على المنصة ولا يمكن إنشاء إعلان آخر لها.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('new listing keeps title, tenure then location validation', (tester) async {
    final repository = _Repository();
    await _open(tester, repository, existing: null);
    await _tap(tester, _button('التالي'));
    expect(find.text('اكتب عنواناً واضحاً من 4 أحرف على الأقل.'), findsOneWidget);
    await _enter(tester, 'عنوان الإعلان *', 'شقة للاختبار');
    _dismissMessage(tester);
    await _tap(tester, _button('التالي'));
    expect(find.text('حدد نوع الملكية: حر أو وقف.'), findsOneWidget);
    _dismissMessage(tester);
    // Renting removes sale tenure but does not allow an empty purpose.
    await _tap(tester, find.widgetWithText(ChoiceChip, 'للإيجار'));
    await _tap(tester, find.widgetWithText(ChoiceChip, 'للإيجار'));
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'للإيجار')).selected, isTrue);
    await _tap(tester, _button('التالي'));
    expect(find.text('الخطوة 2 من 5'), findsOneWidget);
    await _tap(tester, _button('التالي'));
    expect(find.text('حدد موقع العقار على الخريطة أو باستخدام موقعك الحالي.'), findsOneWidget);
    expect(repository.input, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor retains unit identity validation order', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _tap(tester, _button('التالي'));
    await _tap(tester, _button('التالي'));
    for (final label in ['عدد اللبن *', 'اسم أو رقم المبنى *', 'رقم الوحدة *', 'الدور *', 'غرف النوم *', 'الحمامات *']) {
      await _enter(tester, label, '');
    }
    for (final correction in [
      ('عدد اللبن *', '4', 'أدخل عدداً صحيحاً للبن.'),
      ('اسم أو رقم المبنى *', 'عمارة النور 12', 'أدخل اسم أو رقم المبنى.'),
      ('رقم الوحدة *', 'A-2', 'أدخل رقم الوحدة.'),
      ('الدور *', '3', 'أدخل رقم الدور.'),
      ('غرف النوم *', '2', 'أدخل عدد غرف النوم.'),
      ('الحمامات *', '1', 'أدخل عدد الحمامات.'),
    ]) {
      await _tap(tester, _button('التالي'));
      expect(find.text(correction.$3), findsOneWidget);
      expect(find.text('الخطوة 3 من 5'), findsOneWidget);
      _dismissMessage(tester);
      await _enter(tester, correction.$1, correction.$2);
    }
    await _tap(tester, _button('التالي'));
    expect(find.text('الخطوة 4 من 5'), findsOneWidget);
    expect(repository.input, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor keeps monthly rent, term and advance validation', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    for (var i = 0; i < 3; i++) { await _tap(tester, _button('التالي')); }
    await _enter(tester, 'الإيجار الشهري بالريال اليمني *', '0');
    await _enter(tester, 'مدة التأجير بالأشهر *', '25');
    await _enter(tester, 'أشهر المقدم *', '13');
    for (final correction in [
      ('الإيجار الشهري بالريال اليمني *', '50000', 'أدخل الإيجار الشهري بشكل صحيح.'),
      ('مدة التأجير بالأشهر *', '12', 'مدة التأجير يجب أن تكون من شهر إلى 24 شهراً.'),
      ('أشهر المقدم *', '3', 'أشهر المقدم يجب أن تكون من شهر وحتى مدة التأجير.'),
    ]) {
      await _tap(tester, _button('التالي'));
      expect(find.text(correction.$3), findsOneWidget);
      _dismissMessage(tester);
      await _enter(tester, correction.$1, correction.$2);
    }
    await _tap(tester, _button('التالي'));
    expect(find.text('الخطوة 5 من 5'), findsOneWidget);
    // Missing server Sai configuration still blocks submit before image evidence.
    await _tap(tester, _button('إرسال للمراجعة'));
    expect(find.descendant(of: find.byType(SnackBar),
      matching: find.text('حدد السعي والطرف الذي يتحمله قبل إرسال الإعلان للمراجعة.')), findsOneWidget);
    expect(repository.input, isNull);
    expect(tester.takeException(), isNull);
  });
}

const _headings = ['نوع الإعلان والعقار', 'موقع العقار', 'المواصفات', 'الإيجار والتواصل', 'الصور والإثبات والمراجعة'];
const _property = PropertyDetails(
  id: 9, title: 'شقة واسعة في صنعاء بعنوان عربي طويل ABC-12', purpose: 'rent', type: 'apartment',
  price: 151500, basePrice: 150000, monthlyRent: 50000, rentalTermMonths: 12, advanceMonths: 3,
  currency: 'YER', latitude: 15.3, longitude: 44.2, images: [],
  areaValue: 4, areaUnit: 'libna_sanaani', bedrooms: 2, bathrooms: 1,
  hasParking: false, buildingFacade: 'north', buildingReference: 'عمارة النور 12', unitNumber: 'A-2', floorNumber: '3',
  address: 'صنعاء - حدة - شارع الزبيري', status: 'draft', reviewStatus: 'returned_for_correction',
  lastReviewReason: 'يرجى توضيح المعلومات وإكمال مستند العلاقة بالعقار حتى يتمكن فريق الدعم من مراجعة الإعلان.',
);
final _submissionProperty = PropertyDetails.fromJson({
  'id': 9, 'title': 'شقة للاختبار', 'purpose': 'rent', 'type': 'apartment',
  'price': 150000, 'monthly_rent': 50000, 'rental_term_months': 12, 'advance_months': 3,
  'currency': 'YER', 'latitude': 15.3, 'longitude': 44.2,
  'images': [{'id': 1, 'url': 'https://example.invalid/fixture.jpg', 'is_primary': true}],
  'area_value': 4, 'area_unit': 'libna_sanaani', 'bedrooms': 2, 'bathrooms': 1,
  'has_parking': false, 'building_facade': 'north', 'building_reference': 'عمارة النور 12',
  'unit_number': 'A-2', 'floor_number': '3', 'address': 'صنعاء - حدة - شارع الزبيري',
  'status': 'draft', 'ownership_document_type': 'purchase_deed',
  'document_owner_name': 'مالك الاختبار', 'owner_relationship_type': 'owner', 'ownership_proof_present': true,
});

class _Repository extends PropertyRepository {
  _Repository({this.ready = false, this.selfVerification = false}) : super(Dio(), AuthRepository(Dio()));
  final bool ready;
  final bool selfVerification;
  int identityCalls = 0;
  int submitCalls = 0;
  String? differenceType;
  String? differenceNote;
  final saved = Completer<PropertyDetails>();
  PropertyListingInput? input;
  int? id;
  bool? submitForReview;
  bool? replaceImages;
  @override
  Future<PropertySaiEnvelope> sai(int propertyId) async => ready
      ? const PropertySaiEnvelope(management: PropertySaiManagement(configured: true, advertiserType: 'owner'))
      : const PropertySaiEnvelope();
  @override
  Future<PropertyIdentityResult> checkPropertyIdentity(int propertyId) async {
    identityCalls++;
    return PropertyIdentityResult(decision: selfVerification ? 'self_verification' : 'confirmed_duplicate',
      status: selfVerification ? 'self_verification_required' : 'confirmed_duplicate',
      score: 90, signals: const [], message: 'fixture server decision');
  }
  @override
  Future<PropertyIdentityResult> selfVerifyPropertyIdentity(int propertyId, {required String differenceType, required String differenceNote}) async {
    this.differenceType = differenceType;
    this.differenceNote = differenceNote;
    return const PropertyIdentityResult(decision: 'confirmed_duplicate', status: 'confirmed_duplicate', score: 95, signals: [], message: 'fixture server decision');
  }
  @override
  Future<PropertyDetails> submitListing(int propertyId) async {
    submitCalls++;
    return _submissionProperty;
  }
  @override
  Future<PropertyDetails> updateListing(int propertyId, PropertyListingInput input, {
    List<String> imagePaths = const [], bool replaceImages = false, bool submitForReview = false,
    List<String> proofPaths = const [], String? ownerIdFrontPath, String? ownerIdBackPath,
    String? ownerSelfiePath, String? ownershipProofPath,
  }) {
    id = propertyId;
    this.input = input;
    this.replaceImages = replaceImages;
    this.submitForReview = submitForReview;
    return saved.future;
  }
}
class _Auth extends AuthController {
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({
    'id': 1, 'name': 'مالك الاختبار', 'account_type': 'regular',
    'verification_profile': {'type': 'owner', 'status': 'approved'},
  });
}
Finder _field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
Finder _button(String label) => find.widgetWithText(AppButton, label);
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}
Future<void> _tap(WidgetTester tester, Finder target, {bool settle = true}) async {
  await _reveal(tester, target);
  await tester.tap(target);
  if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(); }
}
// The editor intentionally stays busy while a server-identity dialog is open.
// Advance frames instead of settling its continuously animated busy indicator.
Future<void> _tapWhileSaving(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 300));
}
Future<void> _enter(WidgetTester tester, String label, String value) async {
  await _reveal(tester, _field(label));
  await tester.enterText(_field(label), value);
  await tester.pumpAndSettle();
}
void _dismissMessage(WidgetTester tester) => ScaffoldMessenger.of(tester.element(find.byType(ListingEditorScreen))).removeCurrentSnackBar();
Future<void> _open(WidgetTester tester, _Repository repository, {
  Size size = const Size(320, 915), double scale = 1, GlobalKey? captureKey,
  PropertyDetails? existing = _property,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  PropertyDetails? saved;
  await tester.pumpWidget(ProviderScope(overrides: [
    propertyRepositoryProvider.overrideWithValue(repository),
    authControllerProvider.overrideWith(_Auth.new),
  ], child: RepaintBoundary(key: captureKey, child: MaterialApp(
    theme: AppTheme.light, debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: StatefulBuilder(builder: (context, setState) => Scaffold(body: FilledButton(
      onPressed: () async {
        final result = await Navigator.of(context).push<PropertyDetails>(MaterialPageRoute(builder: (_) => ListingEditorScreen(existingProperty: existing)));
        setState(() => saved = result);
      }, child: Text(saved == null ? 'OPEN' : 'SAVED ${saved!.id}'),
    ))),
  ))));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}
