import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/property_card_gallery.dart';
import 'package:real_estate_mobile/core/widgets/property_type_icon.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/auth_screen.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/listing_creation_menu.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_marker.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/favorites_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_actions.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_summary_card.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth, BrokerTestRepository;

class _Anonymous extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}

PropertySummary _property(int id, {String type = 'house', String purpose = 'sale'}) => PropertySummary.fromJson({
  'id':id, 'title':type == 'shop' ? 'محل على شارع رئيسي' : 'منزل واسع بإطلالة هادئة', 'type':type, 'purpose':purpose,
  'price':purpose == 'rent' ? 300000 : 125000000, 'currency':'YER', 'latitude':13.96, 'longitude':44.18,
  if (purpose == 'rent') ...{'monthly_rent':100000, 'advance_months':3, 'price_display_note':'السعي YER 100000'},
  'address':'إب، شارع السبل', 'bedrooms':3, 'bathrooms':2, 'area_value':180, 'area_unit':'sqm', 'has_parking':true,
});

Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1, GlobalKey? boundary, bool broker = false, List<PropertyMarker>? favorites}) async {
  tester.view.physicalSize = const Size(412,915); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(() => broker ? BrokerTestAuth(1) : _Anonymous()),
    brokerRepositoryProvider.overrideWithValue(BrokerTestRepository()),
    if (favorites != null) favoritePropertiesProvider.overrideWith((ref) async => favorites),
  ], child: MaterialApp(theme: AppTheme.light, builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: boundary, child: child!)), home: Directionality(textDirection: TextDirection.rtl, child: child))));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey boundary, String name) async {
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/listing-design-preview/$name.png');
    await file.parent.create(recursive: true); await file.writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['sans-serif','NotoSansArabic']) {
      await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    }
    final font = FontLoader('PrimaryFont');
    for (final weight in ['Regular','Medium','SemiBold','Bold','ExtraBold']) { font.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await font.load();
    final bytes = await File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(bytes.buffer.asByteData()))).load();
  });

  test('Arabic money retains the exact amount and distinguishes currencies', () {
    expect(moneyLabel('125000000','YER'),'١٢٥٬٠٠٠٬٠٠٠ ريال');
    expect(moneyLabel('100000.50','YER'),'١٠٠٬٠٠٠٫٥ ريال');
    expect(moneyLabel('75','USD'),'٧٥ دولار أمريكي');
    expect(moneyLabel('500','SAR'),'٥٠٠ ريال سعودي');
    expect(localizedMoneyText('السعي YER 100000'),'السعي ١٠٠٬٠٠٠ ريال');
  });

  test('property types have distinct symbols and unknown facts are omitted', () {
    expect(['apartment','floor','house','villa','building','land','farm','shop','office'].map(propertyTypeIcon).toSet(), hasLength(9));
    final fields = summaryPropertyFacts(_property(1, type:'apartment', purpose:'rent'));
    expect(fields.any((f) => f.label.contains('م²')), isFalse);
    expect(fields.any((f) => f.label == '٣ غرف'), isTrue);
    expect(fields.any((f) => f.label == '٢ حمام'), isTrue);
    expect(summaryPropertyFacts(_property(2,type:'land')).any((f) => f.label.contains('غرف')), isFalse);
  });

  for (final scale in [1.0,2.4]) {
    testWidgets('cards show real facts, Arabic prices and comparison on the photo at $scale', (tester) async {
      final key = GlobalKey();
      await _pump(tester, Scaffold(body: ListView(padding: const EdgeInsets.all(18), children: [
        PropertySummaryCard(property: _property(1)), const SizedBox(height:14),
        PropertySummaryCard(property: _property(2,type:'shop',purpose:'rent')),
      ]), bottomNavigationBar: const Padding(padding: EdgeInsets.all(16), child: PropertyCompareTray())), scale:scale, boundary:key);
      final compare = find.byKey(const ValueKey('compare-property-1'));
      final gallery = find.byType(PropertyCardGallery).first;
      expect(tester.getRect(gallery).contains(tester.getCenter(compare)), isTrue);
      expect(find.text('٣ غرف'), findsOneWidget); expect(find.text('٢ حمام'), findsOneWidget);
      expect(find.textContaining('١٢٥٬٠٠٠٬٠٠٠', findRichText: true), findsOneWidget);
      await tester.tap(compare); await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(compare).isSelected, isTrue);
      await _capture(tester,key,'cards-$scale'); expect(tester.takeException(),isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('compare-property-2'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('compare-property-2'))); await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('open-property-comparison'))).onPressed, isNotNull);
      expect(find.textContaining('شهريًا',findRichText:true),findsOneWidget);
      expect(find.textContaining('مقدم ٣ أشهر'),findsOneWidget);
      expect(find.text('السعي ١٠٠٬٠٠٠ ريال'),findsOneWidget); expect(tester.takeException(),isNull);
    });

    testWidgets('login keeps the WhatsApp journey readable at $scale', (tester) async {
      final key = GlobalKey(); await _pump(tester, const AuthScreen(),scale:scale,boundary:key);
      await _capture(tester,key,'login-$scale');
      await tester.ensureVisible(find.byKey(const ValueKey('auth-phone'))); await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('auth-phone'))).controller!.text,'+967');
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit'))); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-submit')).hitTestable(),findsOneWidget);
      if(scale>1) await _capture(tester,key,'login-controls-$scale');
      expect(tester.takeException(),isNull);
    });

    testWidgets('center action offers assisted or manual entry at $scale', (tester) async {
      bool? assisted;
      final key = GlobalKey();
      await _pump(tester, Scaffold(body: const Center(child: Text('عقارات حولك')), bottomNavigationBar: Builder(builder:(context) => AppNavigationBar(
        destinations: const [AppNavDestination(label:'الرئيسية',icon:Icons.home_outlined), AppNavDestination(label:'عملي',icon:Icons.work_outline),
          AppNavDestination(label:'العملاء',icon:Icons.people_outline), AppNavDestination(label:'حسابي',icon:Icons.person_outline)],
        selectedIndex:0,onSelected:(_){},onCreate:() async {assisted=await showListingCreationMenu(context);}))),scale:scale,boundary:key);
      await tester.tap(find.byKey(const ValueKey('home-add-property'))); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('create-listing-ai')),findsOneWidget);
      await _capture(tester,key,'creation-menu-$scale');
      await tester.ensureVisible(find.byKey(const ValueKey('create-listing-manual'))); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-listing-manual'))); await tester.pumpAndSettle();
      expect(assisted,isFalse); expect(tester.takeException(),isNull);
    });

    testWidgets('selection sheet supports long Arabic options and null selection at $scale', (tester) async {
      String? chosen='new'; final key=GlobalKey();
      await _pump(tester, Scaffold(body: Padding(padding:const EdgeInsets.all(20),child:StatefulBuilder(builder:(context,change) => AppSelectField<String>(
        value:chosen,decoration:const InputDecoration(labelText:'حالة المتابعة'),items:const [
          DropdownMenuItem(value:null,child:Text('كل العملاء')), DropdownMenuItem(value:'new',child:Text('عميل جديد')),
          DropdownMenuItem(value:'contacted',child:Text('تم التواصل مع العميل'))],onChanged:(value)=>change(()=>chosen=value))))),scale:scale,boundary:key);
      await tester.tap(find.byType(AppSelectField<String>)); await tester.pumpAndSettle();
      await _capture(tester,key,'selection-$scale');
      await tester.tap(find.byKey(const ValueKey('select-option-null'))); await tester.pumpAndSettle();
      expect(chosen,isNull); expect(find.text('كل العملاء'),findsOneWidget); expect(tester.takeException(),isNull);
    });
  }

  testWidgets('work tools omit duplicate create and customers entries while retaining deals and finance', (tester) async {
    final key=GlobalKey(); await _pump(tester,const BrokerDashboardScreen(),broker:true,boundary:key);
    await _capture(tester,key,'work-overview');
    expect(find.byKey(const ValueKey('broker-tool-إضافة عقار')),findsNothing);
    expect(find.byKey(const ValueKey('broker-tool-العملاء')),findsNothing);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('broker-tool-المستحقات')),200);
    expect(find.byKey(const ValueKey('broker-tool-الصفقات')),findsOneWidget);
    expect(find.byKey(const ValueKey('broker-tool-المستحقات')),findsOneWidget); expect(tester.takeException(),isNull);
  });

  testWidgets('favorites share photo comparison selection with discovery without entering a separate selection mode', (tester) async {
    await _pump(tester, const FavoritesScreen(), broker: true, favorites: [PropertyMarker.fromJson({
      'id': 1, 'title': 'منزل محفوظ في إب', 'type': 'house', 'purpose': 'sale', 'price': 125000000,
      'currency': 'YER', 'latitude': 13.96, 'longitude': 44.18, 'bedrooms': 3, 'bathrooms': 2,
    })]);
    final action = find.byKey(const ValueKey('compare-property-1'));
    final container = ProviderScope.containerOf(tester.element(find.byType(FavoritesScreen)));
    container.read(propertyCompareSelectionProvider.notifier).toggle(1); await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(action).isSelected, isTrue);
    expect(tester.getRect(find.byType(PropertyCardGallery)).contains(tester.getCenter(action)), isTrue);
    await tester.tap(action); await tester.pumpAndSettle();
    expect(container.read(propertyCompareSelectionProvider), isEmpty);
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget); expect(tester.takeException(), isNull);
  });
}
