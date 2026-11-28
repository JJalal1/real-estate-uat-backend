import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/core/widgets/app_select_field.dart';
import 'support/wave3_fakes.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'support/wave6_fakes.dart';
import 'current_wave_contract_test.dart' show MemoryLocationStore, FakeLocationAccess;
import 'wave6_product_ui_test.dart' show pumpWave6,finishWave6,editorSnapshot,previewWave6,textField;

class _LocationMarketplace extends Wave3MarketplaceFake {
  _LocationMarketplace() : super(onFeed: (query) async =>
      MarketplaceFeed(label: query.governorate ?? 'صنعاء', governorate: query.governorate));

  @override
  Future<HomeLocation> resolveLocation(HomeLocation fix) async => HomeLocation(
    latitude: fix.latitude, longitude: fix.longitude, accuracyMetres: fix.accuracyMetres,
    governorate: 'عدن', governorateCode: 'ADEN', label: 'عدن', device: true,
  );
}

class _ConfiguredProperties extends Wave6Properties {
  _ConfiguredProperties(this.mode);
  final String mode;

  @override
  Future<PropertySaiEnvelope> saiForEditor(int id) async => PropertySaiEnvelope(
    management: PropertySaiManagement(configured: true, advertiserType: 'broker', purpose: 'sale',
      amountType: mode, requestedBrokerRatePercent: mode == 'percentage' ? 2 : null,
      saiRatePercent: 2, fixedAmount: mode == 'fixed' ? 200000 : null,
      fixedCurrency: mode == 'fixed' ? 'AED' : null, brokerMaxRatePercent: 5,
      professionalPlatformSharePercent: 10, platformSharePercent: 20),
  );
}

void main() {
  testWidgets('editor selects one sale currency, retains it on resume, and starts contact empty', (tester) async {
    final initial = editorSnapshot()..['step'] = 3;
    (initial['fields'] as Map).remove('phone');
    final recovery = Wave6Recovery(initial);
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery);
    final picker = find.byKey(const ValueKey('listing-sale-currency'));
    final pickerContents = tester.widget<DropdownButtonFormField<String>>(picker);
    expect(pickerContents.initialValue, 'YER');
    final phone = textField('رقم الاتصال');
    expect(tester.widget<TextField>(phone).controller!.text, isEmpty);

    final price = textField('المبلغ');
    for (final currency in ['SAR', 'USD']) {
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text(currency == 'SAR' ? 'سعر البيع بالريال السعودي' : 'سعر البيع بالدولار').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(price).controller!.text, isEmpty);
      await tester.ensureVisible(price);
      await tester.enterText(price, '١٠٬٠٠٠٬٠٠٠');
      await tester.pump();
      expect(tester.widget<TextField>(price).controller!.text, '10,000,000');
      final fee = find.byKey(const ValueKey('listing-sai-amount'));
      await tester.ensureVisible(fee);
      await tester.enterText(fee, '٢٠٠٠٠٠');
      await tester.pumpAndSettle();
      final unit = currency == 'SAR' ? 'ريال سعودي' : 'دولار أمريكي';
      expect(find.text('حصة المنصة 10% وهي 20,000 $unit من سعي المعلن الذي هو 200,000 $unit'), findsOneWidget);
      await tester.ensureVisible(phone);
      await tester.enterText(phone, '771234567');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(recovery.snapshot?['currency'], currency);
    }
    await finishWave6(tester);
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery);
    expect(tester.widget<DropdownButtonFormField<String>>(picker).initialValue, 'USD');
    expect(tester.widget<TextField>(phone).controller!.text, '771234567');
    expect(tester.widget<TextField>(price).controller!.text, '10,000,000');
    await finishWave6(tester);
  });

  for (final mode in ['fixed', 'percentage']) {
    testWidgets('existing listing keeps legacy currency, saved contact and frozen share for $mode terms', (tester) async {
      final listing = PropertyDetails.fromJson({
        'id': 11, 'title': 'بيت للبيع', 'purpose': 'sale', 'type': 'house', 'currency': 'AED',
        'price': 10000000.01, 'contact_phone': '771234566', 'status': 'draft',
      });
      await pumpWave6(tester, ListingEditorScreen(existingProperty: listing, localRecovery: const {
        'step': 3, 'editor_version': 11,
      }), properties: _ConfiguredProperties(mode));
      final picker = find.byKey(const ValueKey('listing-sale-currency'));
      expect(tester.widget<DropdownButtonFormField<String>>(picker).initialValue, 'AED');
      expect(find.text('سعر البيع بعملة AED'), findsOneWidget);
      expect(tester.widget<TextField>(textField('رقم الاتصال')).controller!.text, '771234566');
      expect(tester.widget<TextField>(textField('المبلغ')).controller!.text, '10000000.01');
      expect(find.text('حصة المنصة 20% وهي 40,000 AED من سعي المعلن الذي هو 200,000 AED'), findsOneWidget);
      final fee = find.byKey(ValueKey(mode == 'fixed' ? 'listing-sai-amount' : 'listing-sai-rate'));
      await tester.ensureVisible(fee);
      await tester.enterText(fee, mode == 'fixed' ? '100000' : '1');
      await tester.pumpAndSettle();
      expect(find.text('حصة المنصة 10% وهي 10,000 AED من سعي المعلن الذي هو 100,000 AED'), findsOneWidget);
      await finishWave6(tester);
    });
  }

  test('sale and rent quote the frozen share until the publisher chooses new terms', () {
    for (final purpose in ['sale', 'rent']) {
      final policy = PropertySaiManagement(configured: true, advertiserType: 'broker', purpose: purpose,
          brokerMaxRatePercent: 5, professionalPlatformSharePercent: 10, platformSharePercent: 20);
      for (final fixedAmount in <double?>[null, 200000]) {
        final frozen = PropertySaiQuote.calculate(policy, 2, 10000000, fixedAmount: fixedAmount, keepConfiguredShare: true)!;
        final revised = PropertySaiQuote.calculate(policy, 2, 10000000, fixedAmount: fixedAmount)!;
        expect(frozen.platform, 40000);
        expect(revised.platform, 20000);
        expect(frozen.platformPercent, 20);
        expect(revised.platformPercent, 10);
      }
    }
  });

  for(final scale in [1.0,2.4]) {
    testWidgets('current wave Sai defaults to fixed, spells the amount and caps percentages at scale $scale',(tester) async {
      final snapshot=editorSnapshot()..['step']=3,boundary=GlobalKey();
      await pumpWave6(tester,const ListingEditorScreen(),recovery:Wave6Recovery(snapshot),scale:scale,boundary:boundary);
      final fixed=find.byKey(const ValueKey('listing-sai-fixed')),amount=find.byKey(const ValueKey('listing-sai-amount'));
      expect(tester.widget<ChoiceChip>(fixed).selected,true);expect(find.byKey(const ValueKey('listing-sai-rate')),findsNothing);
      await tester.ensureVisible(amount);await tester.enterText(amount,'١٠٠٠٠٠');await tester.pumpAndSettle();
      expect(find.text('مائة ألف ريال يمني'),findsOneWidget);expect(find.text('حصة المنصة تحسب على ناشر الإعلان'),findsOneWidget);
      await tester.ensureVisible(find.text('حصة المنصة تحسب على ناشر الإعلان'));await previewWave6(tester,boundary,'wave6-current-fixed-$scale');
      final percentage=find.byKey(const ValueKey('listing-sai-percentage'));
      await tester.ensureVisible(percentage);await tester.tap(percentage);await tester.pumpAndSettle();
      final rate=find.byKey(const ValueKey('listing-sai-rate'));await tester.ensureVisible(rate);await tester.enterText(rate,'101');await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listing-sai-amount')),findsNothing);expect(find.text('أقصى نسبة للسعي 100%'),findsOneWidget);
      await previewWave6(tester,boundary,'wave6-current-rate-limit-$scale');expect(tester.takeException(),isNull);await finishWave6(tester);
    });
    testWidgets('current wave apartment floor selector contains exactly ground through seven at scale $scale',(tester)async {
      final snapshot=editorSnapshot(type:'apartment');(snapshot['fields'] as Map)['floor_number']='7';
      await pumpWave6(tester,const ListingEditorScreen(),recovery:Wave6Recovery(snapshot),scale:scale);
      final field=tester.widget<AppSelectField<String>>(find.byKey(const ValueKey('listing-floor-select')));
      // Inspect the actual controlled field used by the editor.
      expect(field.items.map((item)=>item.value),['0','1','2','3','4','5','6','7']);
      expect(field.value,'7');expect(tester.takeException(),isNull);await finishWave6(tester);
    });
  }
  testWidgets('explicit home location permission updates the real feed query and manual city persists',(tester)async {
    final store=MemoryLocationStore(),access=FakeLocationAccess()..decision=LocationPermission.whileInUse;
    final repository=_LocationMarketplace();
    await pumpWave6(tester,const MarketplaceHomeScreen(),allowLocation:true,locationStore:store,locationAccess:access,marketplace:repository);
    expect(access.requests,0);expect(repository.queries.last.device,false);
    expect(find.byKey(const ValueKey('location-introduction-device')), findsNothing);
    expect(find.text('عقارات في منطقتك'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-location')));await tester.pumpAndSettle();
    await tester.tap(find.text('استخدم موقعي'));await tester.pumpAndSettle();
    expect(access.requests,1);expect(repository.queries.last.device,true);expect(repository.queries.last.latitude,12.8);expect(find.text('عدن'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-location')));await tester.pumpAndSettle();await tester.tap(find.text('تعز'));await tester.pumpAndSettle();
    expect(repository.queries.last.governorate,'تعز');expect(store.value.manual!.governorate,'تعز');expect(access.requests,1);
    expect(tester.takeException(),isNull);await finishWave6(tester);
  });
}
