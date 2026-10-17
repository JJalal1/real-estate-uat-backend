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
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
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

Future<void> pumpWave6(WidgetTester tester,Widget child,{Wave6Ai? ai,Wave6Drafts? drafts,Wave6Recovery? recovery,double scale=1,GlobalKey? boundary})async{
  tester.view.physicalSize=const Size(412,915);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(()=>BrokerTestAuth(1)),
    propertyRepositoryProvider.overrideWithValue(Wave6Properties()),aiRepositoryProvider.overrideWithValue(ai??Wave6Ai()),
    listingAccountDraftRepositoryProvider.overrideWithValue(drafts??Wave6Drafts()),listingRecoveryStoreProvider.overrideWithValue(recovery??Wave6Recovery()),
    voiceInputProvider.overrideWithValue(Wave3VoiceFake()),
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
void main(){
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
    expect(find.byKey(const ValueKey('smart-search-save')),findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-map')));await tester.tap(find.byKey(const ValueKey('smart-search-map')));await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,'شقة للإيجار في صنعاء');expect(container.read(smartSearchSessionProvider).filters.values,before);
    expect(find.text('15.3694,44.191'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('marker-11')));await tester.pumpAndSettle();expect(find.text('عقار تجريبي 11'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-pan')));await tester.pumpAndSettle();expect(container.read(smartSearchSessionProvider).filters.values['south'],15.2);
    await tester.tap(find.byKey(const ValueKey('smart-search-list')));await tester.pumpAndSettle();expect(tester.widget<TextField>(field).controller!.text,'شقة للإيجار في صنعاء');
    router.pop();await tester.pumpAndSettle();await tester.tap(find.text('ابدأ'));await tester.pumpAndSettle();
    expect(container.read(smartSearchSessionProvider).filters.values,isEmpty);expect(tester.widget<TextField>(field).controller!.text,isEmpty);expect(properties.queries,isNotEmpty);
    await finishWave6(tester);
  });
  for(final scale in [1.0,2.4]){
    testWidgets('comparison cards differences and groups are readable at scale $scale',(tester)async{
      final boundary=GlobalKey();await pumpWave6(tester,const PropertyCompareScreen(propertyIds:[11,12]),scale:scale,boundary:boundary);
      expect(find.text('الفرق باختصار'),findsOneWidget);expect(find.text('استبدال'),findsNWidgets(2));expect(find.text('عرض العقار'),findsNWidgets(2));
      await previewWave6(tester,boundary,'wave6-compare-$scale');
      await tester.ensureVisible(find.byKey(const ValueKey('compare-all')));await tester.tap(find.byKey(const ValueKey('compare-all')));await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('العقار والمبنى'));await tester.pumpAndSettle();await previewWave6(tester,boundary,'wave6-compare-facts-$scale');
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
