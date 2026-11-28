import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';

import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot, finishWave6, pumpWave6;

Finder _key(String name) => find.byKey(ValueKey(name));

class _RentalWorkspace extends Wave6Properties {
  _RentalWorkspace(this.listing);
  final PropertyDetails listing;
  @override
  Future<List<PropertyDetails>> myListings() async => [listing];
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.descendant(
    of: _key(key),
    matching: find.byType(EditableText),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _preview(WidgetTester tester) async {
  await tester.tap(find.byTooltip('خيارات المسودة'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('معاينة'));
  await tester.pumpAndSettle();
}

void main() {
  test(
      'the owner workspace can infer monthly rent only for an explicitly legacy single-month price',
      () {
    PropertyDetails listing(Map<String, dynamic> fields) =>
        PropertyDetails.fromJson({
          'purpose': 'rent',
          'type': 'house',
          'price': 120000,
          ...fields,
        });
    expect(listing({'listing_input_version': 5}).saiCalculationBasis, 120000);
    expect(
        listing({'listing_input_version': 5, 'advance_months': 1})
            .saiCalculationBasis,
        120000);
    expect(
        listing({'listing_input_version': 5, 'advance_months': 3})
            .saiCalculationBasis,
        isNull);
    expect(listing({'listing_input_version': 6}).saiCalculationBasis, isNull);
    expect(listing({}).saiCalculationBasis, isNull);
    expect(
        listing({'monthly_rent': 40000, 'advance_months': 3})
            .saiCalculationBasis,
        40000);
    expect(
        listing({'purpose': 'sale', 'base_price': 100000}).saiCalculationBasis,
        100000);
  });

  testWidgets(
      'My Listings asks for monthly rent before resubmitting a three-month advance with no monthly amount',
      (tester) async {
    final listing = PropertyDetails.fromJson({
      'id': 44,
      'title': 'عقار للإيجار',
      'type': 'house',
      'purpose': 'rent',
      'price': 120000,
      'currency': 'YER',
      'advance_months': 3,
      'listing_input_version': 5,
      'review_status': 'returned_for_correction',
      'status': 'draft',
      'can_submit': true,
      'can_edit': true,
    });
    await pumpWave6(tester, const MyListingsScreen(),
        properties: _RentalWorkspace(listing));
    await tester.tap(find.byTooltip('خيارات البطاقة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة الإرسال'));
    await tester.pumpAndSettle();
    expect(find.text('أكمل الإيجار الشهري في الإعلان قبل تأكيد السعي.'),
        findsOneWidget);
    expect(find.text('إعادة إرسال الإعلان؟'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'تعديل'), findsOneWidget);
    await finishWave6(tester);
  });

  testWidgets(
      'the sale cap uses the entered currency and a price cut invalidates a previously copyable fee',
      (tester) async {
    final snapshot = editorSnapshot()
      ..['step'] = 3
      ..['currency'] = 'SAR';
    (snapshot['fields'] as Map)['price'] = '1000000';
    String? copiedText;
    final messenger = tester.binding.defaultBinaryMessenger;
    const navigation = MethodChannel('real_estate/listing_preview_navigation');
    final navigationVisibility = <bool>[];
    messenger.setMockMethodCallHandler(navigation, (call) async {
      navigationVisibility.add((call.arguments as Map)['hidden'] as bool);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(navigation, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpWave6(tester, const ListingEditorScreen(),
        recovery: Wave6Recovery(snapshot));

    await _enter(tester, 'listing-sai-amount', '50000');
    expect(
        find.text(
            'حصة المنصة 10% وهي 5,000 ريال سعودي من سعي المعلن الذي هو 50,000 ريال سعودي'),
        findsOneWidget);
    await _preview(tester);
    final copyButton = _key('listing-copy-text');
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(copiedText, contains('السعي 50,000 ريال سعودي'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigationVisibility, [true, false]);

    // The previously accepted fee becomes excessive when the price is lowered.
    await _enter(tester, 'listing-price-input', '900000');
    expect(_key('listing-sai-total'), findsNothing);
    expect(
        tester
            .widget<TextField>(_key('listing-sai-amount'))
            .decoration!
            .errorText,
        contains('45,000'));
    await _preview(tester);
    expect(copyButton, findsNothing);
    expect(find.text('معاينة قبل الإرسال'), findsNothing);

    await _enter(tester, 'listing-sai-amount', '45000');
    expect(
        tester
            .widget<TextField>(_key('listing-sai-amount'))
            .decoration!
            .errorText,
        isNull);
    await _preview(tester);
    expect(find.text('معاينة قبل الإرسال'), findsOneWidget);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(copiedText, contains('السعي 45,000 ريال سعودي'));
    await finishWave6(tester);
  });

  testWidgets(
      'rental advance selected in specifications never increases the first-month fee ceiling or zero fallback',
      (tester) async {
    final snapshot = editorSnapshot()..['purpose'] = 'rent';
    final fields = snapshot['fields'] as Map;
    fields.remove('price');
    fields['monthly_rent'] = '40000';
    final drafts = Wave6Drafts();
    final draft = ListingAccountDraft(
        key: newListingDraftKey(),
        revision: 1,
        title: 'منزل للإيجار',
        progress: 70,
        payload: snapshot,
        images: const {'cover': 'https://fixture.invalid/cover.jpg'});
    drafts.drafts[draft.key] = draft;
    await pumpWave6(tester, ListingEditorScreen(accountDraft: draft),
        drafts: drafts);

    final advance = _key('rent-condition-advance');
    await tester.ensureVisible(advance);
    await tester.tap(advance);
    await tester.pumpAndSettle();
    final advanceMonths = _key('rent-advance-0');
    await tester.ensureVisible(advanceMonths);
    await tester.tap(advanceMonths);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 أشهر').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(_key('listing-sai-amount'), findsOneWidget);

    await _enter(tester, 'listing-sai-amount', '40000');
    expect(
        find.text(
            'حصة المنصة 10% وهي 4,000 ريال من سعي المعلن الذي هو 40,000 ريال'),
        findsOneWidget);
    // This fee would fit three prepaid months but exceeds the first month.
    await _enter(tester, 'listing-sai-amount', '40000.01');
    expect(
        tester
            .widget<TextField>(_key('listing-sai-amount'))
            .decoration!
            .errorText,
        contains('40,000'));
    expect(_key('listing-sai-total'), findsNothing);
    await _preview(tester);
    expect(_key('listing-copy-text'), findsNothing);

    final percentage = _key('listing-sai-percentage');
    await tester.ensureVisible(percentage);
    await tester.tap(percentage);
    await tester.pumpAndSettle();
    await _enter(tester, 'listing-sai-rate', '100');
    expect(
        find.text(
            'حصة المنصة 10% وهي 4,000 ريال من سعي المعلن الذي هو 40,000 ريال'),
        findsOneWidget);
    await _enter(tester, 'listing-sai-rate', '100.01');
    expect(
        tester
            .widget<TextField>(_key('listing-sai-rate'))
            .decoration!
            .errorText,
        contains('100%'));
    expect(_key('listing-sai-total'), findsNothing);

    await _enter(tester, 'listing-sai-rate', '0');
    expect(
        find.text(
            'حصة المنصة 100% وهي 8,000 ريال من سعي المعلن الذي هو 8,000 ريال'),
        findsOneWidget);
    await _preview(tester);
    expect(_key('listing-copy-text'), findsOneWidget);
    await finishWave6(tester);
  });
}
