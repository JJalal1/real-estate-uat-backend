import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/app_shell_screen.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/discovery_location.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_sai_configuration_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_entry_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_compare_screen.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth;
import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';

Map<String,dynamic> editorSnapshot({String type='house'})=>{
  'editor_version':8,'type_confirmed':true,'purpose_confirmed':true,'step':2,'type':type,'purpose':'sale','tenure_type':'freehold',
  'latitude':15.37,'longitude':44.19,'parking':'no','facade':'north','area_unit':'sqm',
  'fields':{'title':'عقار للاختبار','description':'وصف كتبه الدلال','price':'10000000','area':'160','bedrooms':'3','bathrooms':'2',
    'governorate':'صنعاء','district':'حدة',if(type=='shop')...{'floor_number':'3','unit_number':'7'}},
};
Finder textField(String label)=>find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText==label);

Future<void> pumpWave6(WidgetTester tester,Widget child,{Wave6Ai? ai,Wave6Drafts? drafts,Wave6Recovery? recovery,Wave3VoiceFake? voice,bool testMap=false,double scale=1,GlobalKey? boundary,
  bool allowLocation=false,DiscoveryLocationStore? locationStore,DiscoveryLocationAccess? locationAccess,Wave3MarketplaceFake? marketplace})async{
  tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(()=>BrokerTestAuth(1)),
    propertyRepositoryProvider.overrideWithValue(Wave6Properties()),aiRepositoryProvider.overrideWithValue(ai??Wave6Ai()),
    listingAccountDraftRepositoryProvider.overrideWithValue(drafts??Wave6Drafts()),listingRecoveryStoreProvider.overrideWithValue(recovery??Wave6Recovery()),
    voiceInputProvider.overrideWithValue(voice??Wave3VoiceFake()),
    homeLocationAttemptedProvider.overrideWith((ref)=>!allowLocation),
    if(locationStore!=null) discoveryLocationStoreProvider.overrideWithValue(locationStore),
    if(locationAccess!=null) discoveryLocationAccessProvider.overrideWithValue(locationAccess),
    if(testMap) sharedSearchMapBuilderProvider.overrideWithValue((context,rows,select,viewport)=>ColoredBox(color:Colors.teal.shade50,
      child:Center(child:Wrap(spacing:12,runSpacing:12,children:[for(final row in rows)TextButton(
        key:ValueKey('fixture-map-${row.id}'),onPressed:()=>select(row.id),child:Text('${row.latitude}, ${row.longitude}'))])))),
    marketplaceRepositoryProvider.overrideWithValue(marketplace??Wave3MarketplaceFake(onFeed:(q)async=>MarketplaceFeed(label:'صنعاء',governorate:'صنعاء',sectionOrder:const ['rent','latest'],
      sections:{'latest':[wave3Property(11)],'rent':[wave3Property(12)]}))),
  ],child:MaterialApp(theme:AppTheme.light,home:child,builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),
    child:RepaintBoundary(key:boundary,child:child!)))));
  await tester.pumpAndSettle();
}
Future<void> finishWave6(WidgetTester tester)async{await tester.pumpWidget(const SizedBox.shrink());await tester.pump(const Duration(seconds:1));}
Future<void> previewWave6(WidgetTester tester,GlobalKey key,String name)async{
  final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(()async{final image=await boundary.toImage(pixelRatio:2);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    final file=File('build/broker-preview/$name.png');await file.parent.create(recursive:true);await file.writeAsBytes(bytes!.buffer.asUint8List());image.dispose();});
}
class Wave6SaiProperties extends Wave6Properties {
  int writes=0;
  String? savedType, decision;
  double? savedAmount, savedRate;
  static const policy=PropertySaiManagement(configured:true,advertiserType:'broker',purpose:'sale',
    requestedBrokerRatePercent:2.5,brokerMaxRatePercent:6,fixedRatePercent:1.25,
    professionalPlatformSharePercent:17.5,fallbackPlatformSharePercent:100);
  @override
  Future<PropertySaiEnvelope> saiForEditor(int id)async=>const PropertySaiEnvelope(management:policy);
  @override
  Future<PropertySaiEnvelope> configureSai(int propertyId,{required String payer,double? brokerRatePercent,
    String? platformTermsDecision,bool deferPlatformTerms=false,String amountType='percentage',double? fixedAmount})async{
    writes++;savedType=amountType;savedAmount=fixedAmount;savedRate=brokerRatePercent;decision=platformTermsDecision;
    return const PropertySaiEnvelope(management:policy);
  }
}
void main(){
  setUpAll(() { WidgetController.hitTestWarningShouldBeFatal=true; });
  tearDownAll(() { WidgetController.hitTestWarningShouldBeFatal=false; });
  setUpAll(()async{
    await (FontLoader('NotoSansArabic')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    await (FontLoader('sans-serif')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    final primary=FontLoader('PrimaryFont');for(final weight in ['Regular','Medium','SemiBold','Bold','ExtraBold']){primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf'));}await primary.load();
    final icons=await File('${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });
  testWidgets('fresh entry has no initial chips or save; list/map share text, coordinates and filters; full reentry is empty',(tester)async{
    final properties=Wave6Properties(),ai=Wave6Ai(),container=ProviderContainer(overrides:[propertyRepositoryProvider.overrideWithValue(properties),
      aiRepositoryProvider.overrideWithValue(ai),voiceInputProvider.overrideWithValue(Wave3VoiceFake()),
      sharedSearchMapBuilderProvider.overrideWithValue((context,rows,select,viewport)=>ColoredBox(color:Colors.grey.shade200,child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final row in rows)TextButton(key:ValueKey('marker-${row.id}'),onPressed:()=>select(row.id),child:Text('${row.latitude},${row.longitude}')),
        TextButton(key:const ValueKey('map-pan'),onPressed:()=>viewport(15.2,44.0,15.5,44.5),child:const Text('تحريك الخريطة')),
      ])))),
    ]);addTearDown(container.dispose);
    final router=GoRouter(routes:[GoRoute(path:'/',builder:(context,__)=>Scaffold(body:TextButton(onPressed:()=>context.push('/search'),child:const Text('ابدأ')))),GoRoute(path:'/search',builder:(_,__)=>const AssistedSearchScreen())]);addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container:container,child:MaterialApp.router(theme:AppTheme.light,routerConfig:router)));
    await tester.tap(find.text('ابدأ'));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('smart-search-save')),findsNothing);expect(find.byKey(const ValueKey('smart-search-manual')),findsNothing);expect(find.text('أضف نوع العقار'),findsNothing);
    final field=find.byKey(const ValueKey('smart-search-description'));await tester.enterText(field,'شقة للإيجار في صنعاء');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-send')));await tester.tap(find.byKey(const ValueKey('smart-search-send')));await tester.pumpAndSettle();
    final before=container.read(smartSearchSessionProvider).filters.values;
    expect(tester.widget<TextField>(field).controller!.text,isEmpty);
    expect(find.byKey(const ValueKey('smart-search-query-summary')),findsOneWidget);
    await tester.enterText(field,'مسودة متابعة لم أرسلها');
    expect(find.byKey(const ValueKey('smart-search-save')),findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-map')));await tester.tap(find.byKey(const ValueKey('smart-search-map')));await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,'مسودة متابعة لم أرسلها');expect(container.read(smartSearchSessionProvider).filters.values,before);
    expect(find.text('15.3694,44.191'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('marker-11')));await tester.pumpAndSettle();expect(find.text('عقار تجريبي 11'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-pan')));await tester.pumpAndSettle();expect(container.read(smartSearchSessionProvider).filters.values['south'],15.2);
    await tester.tap(find.byKey(const ValueKey('smart-search-list')));await tester.pumpAndSettle();expect(tester.widget<TextField>(field).controller!.text,'مسودة متابعة لم أرسلها');
    router.pop();await tester.pumpAndSettle();await tester.tap(find.text('ابدأ'));await tester.pumpAndSettle();
    expect(container.read(smartSearchSessionProvider).filters.values,isEmpty);expect(tester.widget<TextField>(field).controller!.text,isEmpty);expect(properties.queries,isNotEmpty);
    await finishWave6(tester);
  });
  for(final scale in [1.0,2.4]){
    testWidgets('comparison cards differences and groups are readable at scale $scale',(tester)async{
      final boundary=GlobalKey();await pumpWave6(tester,const PropertyCompareScreen(propertyIds:[11,12]),scale:scale,boundary:boundary);
      expect(find.text('الفرق باختصار'),findsOneWidget);expect(find.text('استبدال'),findsNWidgets(2));expect(find.text('عرض العقار'),findsNWidgets(2));
      await previewWave6(tester,boundary,'wave6-compare-$scale');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('compare-all')),300,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('compare-all')));await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('compare-all'))).selected,isTrue);
      await tester.scrollUntilVisible(find.text('العقار والمبنى'),300,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();await previewWave6(tester,boundary,'wave6-compare-facts-$scale');
      expect(tester.takeException(),isNull);await finishWave6(tester);
    });
    testWidgets('description is inline and a delayed result cannot replace a manual edit at scale $scale',(tester)async{
      final ai=Wave6Ai()..descriptionResult=Completer<Map<String,dynamic>>(),drafts=Wave6Drafts(),boundary=GlobalKey();
      await pumpWave6(tester,const ListingEditorScreen(),ai:ai,drafts:drafts,recovery:Wave6Recovery(editorSnapshot()),scale:scale,boundary:boundary);
      await tester.ensureVisible(find.text('إنشاء وصف بالذكاء الاصطناعي'));await tester.tap(find.text('إنشاء وصف بالذكاء الاصطناعي'));await tester.pump();
      expect(find.text('جارٍ تجهيز الوصف…'),findsOneWidget);expect(find.byType(BottomSheet),findsNothing);expect(find.byType(Dialog),findsNothing);
      await previewWave6(tester,boundary,'wave6-description-loading-$scale');
      await tester.enterText(textField('وصف العقار'),'تعديل الدلال أثناء التجهيز');ai.descriptionResult!.complete({'description':'رد متأخر'});await tester.pumpAndSettle();
      expect(tester.widget<TextField>(textField('وصف العقار')).controller!.text,'تعديل الدلال أثناء التجهيز');
      ai.descriptionResult=null;await tester.ensureVisible(find.text('إنشاء وصف بالذكاء الاصطناعي'));await tester.tap(find.text('إنشاء وصف بالذكاء الاصطناعي'));await tester.pumpAndSettle();
      expect(tester.widget<TextField>(textField('وصف العقار')).controller!.text,contains('ثلاث غرف'));
      await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();expect(drafts.saves,isNotEmpty);expect(drafts.saves.last.containsKey('image_tokens'),isFalse);
      await previewWave6(tester,boundary,'wave6-description-ready-$scale');expect(tester.takeException(),isNull);await finishWave6(tester);
    });
  }
  testWidgets('rental assistance uses the saved draft identity and keeps explicit review',(tester)async{
    final drafts=Wave6Drafts(),ai=Wave6Ai(),key=newListingDraftKey(),snapshot=editorSnapshot(type:'shop')
      ..['purpose']='rent'..['rental_conditions']=[{'kind':'advance','months':3}];
    (snapshot['fields'] as Map)['monthly_rent']='75000';
    final draft=ListingAccountDraft(key:key,revision:2,payload:snapshot);drafts.drafts[key]=draft;
    await pumpWave6(tester,ListingEditorScreen(accountDraft:draft),ai:ai,drafts:drafts);
    final polish=find.text('ترتيب وصياغة الشروط بالذكاء الاصطناعي');
    await tester.ensureVisible(polish);await tester.tap(polish);await tester.pumpAndSettle();
    expect(ai.rentalConditionsDraftKey,key);expect(find.text('راجع صياغة الشروط'),findsOneWidget);
    expect(find.text('استخدام الترتيب المقترح'),findsOneWidget);
    await tester.tap(find.text('إلغاء'));await tester.pumpAndSettle();
    expect(drafts.drafts[key]!.propertyId,isNull);expect(tester.takeException(),isNull);await finishWave6(tester);
  });
  testWidgets('apartment floor is a selection and its ground value survives account saving',(tester)async{
    final drafts=Wave6Drafts(),snapshot=editorSnapshot(type:'apartment');
    (snapshot['fields'] as Map)['floor_number']='3';(snapshot['fields'] as Map)['unit_number']='شمالية';
    await pumpWave6(tester,const ListingEditorScreen(),drafts:drafts,recovery:Wave6Recovery(snapshot));
    final floor=find.byKey(const ValueKey('listing-floor-select'));expect(floor,findsOneWidget);
    await tester.tap(floor);await tester.pumpAndSettle();await tester.tap(find.text('الأرضي').last);await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect((drafts.saves.last['fields'] as Map)['floor_number'],'0');await finishWave6(tester);
  });
  testWidgets('a resumed fixed-fee account draft retains the entered amount and explicit choice after autosave',(tester)async{
    final drafts=Wave6Drafts(),key=newListingDraftKey(),snapshot=editorSnapshot(type:'shop')
      ..['step']=3..['sai_amount_type']='fixed'..['sai_touched']=true..['sai_terms_accepted']=true;
    (snapshot['fields'] as Map)['fixed_sai_amount']='2500';
    final draft=ListingAccountDraft(key:key,revision:2,payload:snapshot);drafts.drafts[key]=draft;
    await pumpWave6(tester,ListingEditorScreen(accountDraft:draft),drafts:drafts);
    expect(find.byKey(const ValueKey('listing-sai-rate')),findsNothing);
    final amount=find.byKey(const ValueKey('listing-sai-amount'));
    await tester.ensureVisible(amount);expect(tester.widget<TextField>(amount).controller!.text,'2500');
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(drafts.saves.last['sai_touched'],isTrue);expect(drafts.saves.last['sai_terms_accepted'],isTrue);
    expect((drafts.saves.last['fields'] as Map)['fixed_sai_amount'],'2500');
    await tester.enterText(amount,'3500');await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect((drafts.saves.last['fields'] as Map)['fixed_sai_amount'],'3500');await finishWave6(tester);
  });
  for(final scale in [1.0,2.4]){
    testWidgets('search and its shared map keep usable controls at scale $scale',(tester)async{
      final boundary=GlobalKey();await pumpWave6(tester,const AssistedSearchScreen(),testMap:true,scale:scale,boundary:boundary);
      final field=find.byKey(const ValueKey('smart-search-description'));
      await tester.enterText(field,'شقة للإيجار في صنعاء');await tester.ensureVisible(find.byKey(const ValueKey('smart-search-send')));
      await tester.tap(find.byKey(const ValueKey('smart-search-send')));await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('smart-search-manual')),findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text,isEmpty);
      await previewWave6(tester,boundary,'wave6-search-$scale');
      await tester.enterText(field,'أضف شرطًا آخر');
      await tester.ensureVisible(find.byKey(const ValueKey('smart-search-map')));await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('smart-search-map')));await tester.pumpAndSettle();
      expect(find.byType(MapScreen),findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text,'أضف شرطًا آخر');
      await tester.tap(find.byKey(const ValueKey('fixture-map-11')));await tester.pumpAndSettle();
      expect(find.text('عقار تجريبي 11'),findsOneWidget);
      await previewWave6(tester,boundary,'wave6-map-$scale');
      expect(tester.takeException(),isNull);await finishWave6(tester);
    });
    testWidgets('existing-listing Sai uses server shares and compact fixed money at scale $scale',(tester)async{
      final repository=Wave6SaiProperties(),boundary=GlobalKey();
      await pumpWave6(tester,Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>showPropertySaiConfigurationSheet(context,
        repository:repository,propertyId:11,purpose:'sale',basis:100000),child:const Text('ضبط السعي')))),scale:scale,boundary:boundary);
      await tester.tap(find.text('ضبط السعي'));await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('listing-sai-total')));
      expect(find.textContaining('حصة المنصة 17.5%'),findsOneWidget);expect(find.textContaining('437.50 ريال'),findsOneWidget);
      expect(find.textContaining('صافي'),findsNothing);expect(repository.writes,0);
      await tester.ensureVisible(find.byKey(const ValueKey('listing-sai-fixed')));await tester.tap(find.byKey(const ValueKey('listing-sai-fixed')));await tester.pumpAndSettle();
      final amount=find.byKey(const ValueKey('listing-sai-amount'));await tester.ensureVisible(amount);await tester.enterText(amount,'1500');await tester.pumpAndSettle();
      expect(find.text('حصة المنصة 262.50 ريال'),findsOneWidget);expect(find.textContaining('حصة المنصة 17.5%'),findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('listing-sai-total')));await previewWave6(tester,boundary,'wave6-existing-sai-$scale');
      expect(repository.writes,0);await tester.ensureVisible(find.text('قبول'));await tester.tap(find.text('قبول'));await tester.pumpAndSettle();
      expect(repository.writes,1);expect(repository.savedType,'fixed');expect(repository.savedRate,isNull);expect(repository.savedAmount,1500);expect(repository.decision,'accept');
      expect(tester.takeException(),isNull);await finishWave6(tester);
    });
    testWidgets('professional home has a compact house-plus CTA and dynamic sections at scale $scale',(tester)async{
      final boundary=GlobalKey();await pumpWave6(tester,const AppShellScreen(),scale:scale,boundary:boundary);
      expect(find.byKey(const ValueKey('home-add-property')),findsOneWidget);expect(find.text('إدارة عملي'),findsNothing);
      expect(find.text('بحث ذكي'),findsOneWidget);expect(find.byTooltip('عملي'),findsOneWidget);
      expect(find.byKey(const ValueKey('floating-smart-search')),findsOneWidget);
      await previewWave6(tester,boundary,'wave6-home-$scale');expect(tester.takeException(),isNull);await finishWave6(tester);
    });
    testWidgets('voice prepares a reviewed shop draft then asks only for missing point and real photos at scale $scale',(tester)async{
      final voice=Wave3VoiceFake(autoComplete:false),drafts=Wave6Drafts(),boundary=GlobalKey();addTearDown(voice.dispose);
      await pumpWave6(tester,const ListingEditorScreen(),ai:Wave6Ai(),drafts:drafts,voice:voice,scale:scale,boundary:boundary);
      await tester.tap(find.byKey(const ValueKey('listing-draft-assistant')));await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('listing-ai-voice')));await tester.tap(find.byKey(const ValueKey('listing-ai-voice')));await tester.pump();
      voice.latest.emit(const VoiceEvent('ready'));voice.latest.emit(const VoiceEvent('partial',text:'وصف لم يكتمل'));await tester.pump(const Duration(seconds:12));
      expect(voice.latest.stops,0);expect(drafts.saves.any((p)=>(p['fields'] as Map)['ai_listing_brief']=='وصف لم يكتمل'),isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('voice-finish')));await tester.tap(find.byKey(const ValueKey('voice-finish')));await tester.pump();
      voice.latest.emit(const VoiceEvent('final',text:'محل للإيجار في حدة، المساحة خمسة وستون مترًا والإيجار خمسة وسبعون ألفًا والسعي خمسون بالمئة'));await tester.pumpAndSettle();
      final scroll=find.descendant(of:find.byKey(const ValueKey('listing-ai-scroll')),matching:find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('listing-ai-prepare')),250,scrollable:scroll);await tester.tap(find.byKey(const ValueKey('listing-ai-prepare')));await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('listing-ai-apply-draft')),350,scrollable:scroll);await tester.tap(find.byKey(const ValueKey('listing-ai-apply-draft')));await tester.pumpAndSettle();
      expect(find.text('أكمل الناقص فقط'),findsOneWidget);expect(find.text('تأكيد الموقع على الخريطة'),findsOneWidget);
      expect(find.text('الشقة في الدور *'),findsNothing);expect(textField('الإيجار الشهري بالريال اليمني *'),findsNothing);expect(textField('المساحة بالمتر المربع *'),findsNothing);
      await tester.pump(const Duration(seconds:5));await tester.pumpAndSettle();
      expect((drafts.saves.last['fields'] as Map)['monthly_rent'],'75000');expect(drafts.saves.last['parking'],isNull);expect(drafts.saves.last['completion_only'],isTrue);
      await previewWave6(tester,boundary,'wave6-completion-$scale');expect(tester.takeException(),isNull);await finishWave6(tester);
    });
  }
  testWidgets('shop discards stale hidden state before account autosave',(tester)async{
    final drafts=Wave6Drafts();await pumpWave6(tester,const ListingEditorScreen(),drafts:drafts,recovery:Wave6Recovery(editorSnapshot(type:'shop')));
    expect(find.text('الشقة في الدور *'),findsNothing);expect(find.text('موقف سيارة *'),findsNothing);expect(find.text('واجهة البناء *'),findsNothing);
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();expect(drafts.saves,isNotEmpty);
    final last=drafts.saves.last,fields=drafts.saves.last['fields'] as Map;
    expect(fields.containsKey('floor_number'),isFalse);expect(fields.containsKey('unit_number'),isFalse);expect(last.containsKey('parking'),isFalse);expect(last['area_unit'],'sqm');
    await finishWave6(tester);
  });
  testWidgets('starting a new account draft keeps previous drafts and resume restores the saved step',(tester)async{
    final drafts=Wave6Drafts(),key=newListingDraftKey();drafts.drafts[key]=ListingAccountDraft(key:key,revision:2,payload:editorSnapshot(),title:'مسودة الدلال',progress:60);
    await pumpWave6(tester,const ListingDraftEntryScreen(),drafts:drafts);
    expect(find.text('لديك إعلان غير مكتمل'),findsOneWidget);await tester.tap(find.text('بدء إعلان جديد'));await tester.pumpAndSettle();
    await tester.ensureVisible(textField('عنوان الإعلان *'));await tester.enterText(textField('عنوان الإعلان *'),'إعلان جديد محفوظ');await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(drafts.drafts.containsKey(key),isTrue);expect(drafts.drafts.length,2);await finishWave6(tester);
    await pumpWave6(tester,ListingEditorScreen(accountDraft:drafts.drafts[key]),drafts:drafts,recovery:Wave6Recovery());
    expect(textField('وصف العقار'),findsOneWidget);expect(tester.widget<TextField>(textField('وصف العقار')).controller!.text,'وصف كتبه الدلال');await finishWave6(tester);
  });
}
