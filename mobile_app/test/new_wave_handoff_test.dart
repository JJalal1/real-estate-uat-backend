import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/app_shell/presentation/app_shell_screen.dart';
import 'package:real_estate_mobile/core/platform/voice_capture_controller.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_contact_policy.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_schema.dart';
import 'package:real_estate_mobile/features/properties/domain/property_comparison.dart';
import 'package:real_estate_mobile/features/properties/domain/rental_condition_summary.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';
import 'package:real_estate_mobile/features/properties/domain/property_location_address.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/broker/data/customer_help_store.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/domain/broker_models.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_workspaces.dart';
import 'broker_experience_ui_test.dart' show BrokerTestRepository;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, editorSnapshot, finishWave6, textField, previewWave6;

class _DescriptionAi extends Wave6Ai {
  String? source;
  final result = Completer<Map<String,dynamic>>();
  @override
  Future<Map<String,dynamic>> description(Map<String,dynamic> facts, {int? propertyId, String? draftKey, String sourceDescription = ''}) {
    source = sourceDescription;
    return result.future;
  }
}

class _Help extends CustomerHelpStore {
  final accounts=<int>{};
  @override
  Future<bool> seen(int accountId) async => accounts.contains(accountId);
  @override
  Future<void> markSeen(int accountId) async { accounts.add(accountId); }
}
class _Customers extends BrokerTestRepository {
  @override
  Future<BrokerPage<BrokerCustomer>> customers({String? stage,int? propertyId,int page=1,String? filter}) async => const BrokerPage(
    items:[BrokerCustomer(threadId:11,customerName:'عميل اختبار',propertyId:3,propertyTitle:'شقة',stage:'new')],page:1,lastPage:1);
}
class _Account extends AuthController {
  _Account(this.id);
  final int id;
  @override
  Future<AuthUser?> build() async => AuthUser.fromJson({'id':id,'name':'دلال اختبار','phone':'+967771234567','account_status':'active',
    'phone_verified_at':'2026-10-12T00:00:00Z','profile_completed_at':'2026-10-12T00:00:00Z','verification_profile':{'type':'broker','status':'approved','reviewed_at':'2026-10-12T00:00:00Z'}});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final arabic=FontLoader('NotoSansArabic')..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    await arabic.load();
    final latin=await File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf').readAsBytes();
    await (FontLoader('sans-serif')..addFont(Future.value(latin.buffer.asByteData()))..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    final primary=FontLoader('PrimaryFont');
    for(final weight in ['Regular','Medium','SemiBold','Bold','ExtraBold']) { primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await primary.load();
    final icons=await File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });

  test('new facts survive roundtrip and comparison; retired elevator cannot surface', () {
    final property = PropertyDetails.fromJson({'id': 11, 'title':'منزل', 'type':'house', 'purpose':'sale', 'price':1000,
      'floors_count':3,'units_per_floor':[2,3,2],'has_elevator':true,'shop_openings':9});
    expect(property.floorsCount,3); expect(property.unitsPerFloor,[2,3,2]); expect(property.shopOpenings,isNull);
    expect(property.toSummary().unitsPerFloor,[2,3,2]); expect(property.hasElevator,isNull);
    final rows=propertyComparisonFacts([property]);
    expect(rows.where((row)=>row.label=='عدد الأدوار').single.values,['3']);
    expect(rows.any((row)=>row.label=='المصعد'),isFalse);
    expect(DynamicPropertySchema.filters({'has_elevator':true}),isEmpty);
    expect(DynamicPropertySchema.applies('has_elevator',{}),isFalse);
    final input=PropertyListingInput(inputVersion:9,title:'منزل',purpose:'sale',type:'house',price:1000,latitude:15,longitude:44,
      floorsCount:3,unitsPerFloor:const [2,3,2],hasElevator:true,shopOpenings:3).toMap();
    expect(input['units_per_floor'],'[2,3,2]'); expect(input.containsKey('has_elevator'),isFalse);expect(input.containsKey('shop_openings'),isFalse);
  });

  test('listing-only mobile contacts normalize Yemen numbers and reject unsupported identities', () {
    const policy=ListingContactPolicy();
    expect(ListingContactPolicy.normalize('+967 ٧٧١ ٢٣٤ ٥٦٧'),'771234567');
    expect(ListingContactPolicy.normalize('00967711234567'),'711234567');
    for(final prefix in policy.prefixes) { expect(policy.error('${prefix}1234567',required:true),isNull); }
    expect(policy.error('',required:true),isNotNull);expect(policy.error(''),isNull);
    expect(policy.error('+12025550103'),isNotNull);expect(policy.error('721234567'),isNotNull);
    expect(const ListingContactPolicy(prefixes:['79']).error('791234567'),isNull);
    expect(rentalConditionSummary({'kind':'duration','months':12}),'مدة العقد: سنة واحدة');
    expect(rentalConditionSummary({'kind':'guarantor'}),'ضمانة تجارية: مطلوبة');
  });

  testWidgets('whole clip waits through silence, saves before transcribing and retries the same file once', (tester) async {
    const channel=MethodChannel('real_estate/speech');
    final commands=<MethodCall>[], paths=<String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {commands.add(call);return null;});
    addTearDown(()=>tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,null));
    final retryResult=Completer<String>();
    final capture=VoiceCaptureController(SystemVoiceInput(liveDictation:true,transcribe:(path,token) async {
      paths.add(path);
      if(paths.length==1) throw DioException(requestOptions:RequestOptions(path:'/transcribe'),type:DioExceptionType.connectionError);
      return retryResult.future;
    }));
    addTearDown(capture.dispose);
    Future<void> event(int id,String type,{String? path}) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,const StandardMethodCodec().encodeMethodCall(
        MethodCall('event',{'id':id,'type':type,if(path!=null)'path':path})),null);
      await tester.pump();
    }
    final first=capture.start(wholeRecording:true);await tester.pump();
    final start=commands.firstWhere((c)=>c.method=='start'),id=(start.arguments as Map)['id'] as int;
    expect((start.arguments as Map)['mode'],'clip');
    await event(id,'ready');await tester.pump(const Duration(seconds:45));
    expect(capture.active,isTrue);expect(capture.elapsed.inSeconds,45);expect(paths,isEmpty);
    expect(commands.where((c)=>c.method=='stop'),isEmpty);
    capture.stop();capture.stop();await tester.pump();
    expect(commands.where((c)=>c.method=='stop'),hasLength(1));
    await event(id,'recorded',path:'/private/full-recording.m4a');
    expect(await first,isNull);expect(capture.canRetry,isTrue);
    expect(commands.where((c)=>c.method=='release'),isEmpty);
    await event(id,'recorded',path:'/private/full-recording.m4a');expect(paths,hasLength(1));
    final retried=capture.retryTranscription();await tester.pump();
    await capture.retryTranscription();expect(paths,['/private/full-recording.m4a','/private/full-recording.m4a']);
    retryResult.complete('عمارة ثلاثة أدوار، وحدتان في كل دور');await tester.pump();
    expect(await retried,'عمارة ثلاثة أدوار، وحدتان في كل دور');expect(capture.canRetry,isFalse);
    expect(commands.where((c)=>c.method=='release'),hasLength(1));
    expect(commands.where((c)=>c.method=='start'),hasLength(1));
  });

  for(final scale in [1.0,2.4]) {
    testWidgets('floor distribution survives the checkpoint and the large Arabic view at $scale', (tester) async {
      final snapshot=editorSnapshot()..['editor_version']=9..['units_per_floor']=['2','3','2'];
      (snapshot['fields'] as Map)['floors_count']='3';
      final recovery=Wave6Recovery(snapshot), boundary=GlobalKey();
      await pumpWave6(tester,const ListingEditorScreen(),recovery:recovery,scale:scale,boundary:boundary);
      final floors=find.byKey(const ValueKey('listing-floors-count'));
      await tester.ensureVisible(floors);await tester.pumpAndSettle();
      expect(tester.widget<TextField>(floors).controller!.text,'3');
      await tester.ensureVisible(find.byWidgetPredicate((w) => w is TextFormField && w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('listing-units-1-')));await tester.enterText(find.byWidgetPredicate((w) => w is TextFormField && w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('listing-units-1-')),'4');
      await tester.pump(const Duration(seconds:1));
      expect(recovery.snapshot!['units_per_floor'],['2','4','2']);
      expect(find.text('المصعد'),findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();await tester.ensureVisible(floors);await tester.pumpAndSettle();
      await previewWave6(tester,boundary,'new-wave-floors-$scale');
      expect(tester.takeException(),isNull);await finishWave6(tester);
    });
  }

  testWidgets('existing free description reaches improvement and a late reply preserves user editing', (tester) async {
    final ai=_DescriptionAi();
    await pumpWave6(tester,const ListingEditorScreen(),ai:ai,recovery:Wave6Recovery(editorSnapshot(type:'apartment')));
    final action=find.byKey(const ValueKey('listing-description-generate'));
    await tester.ensureVisible(action);await tester.tap(action);await tester.pump();
    expect(ai.source,'وصف كتبه الدلال');
    final field=textField('وصف العقار');await tester.ensureVisible(field);await tester.enterText(field,'مدخل مستقل وحوش');
    ai.result.complete({'description':'اقتراح وصل متأخرًا'});await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,'مدخل مستقل وحوش');
    expect(find.text('ترتيب وصياغة الشروط بالذكاء الاصطناعي'),findsNothing);
    await finishWave6(tester);
  });

  testWidgets('address waits for explicit point confirmation and text corrections preserve the point', (tester) async {
    final snapshot=editorSnapshot()..['step']=1..['latitude']=null..['longitude']=null;
    final recovery=Wave6Recovery(snapshot);
    var picks=0, fixes=0;
    final boundary=GlobalKey();
    await pumpWave6(tester,ProviderScope(overrides:[
      propertyCurrentLocationProvider.overrideWithValue(() async { fixes++; return const PropertyLocationSelection(latitude:13.96,longitude:44.18); }),
      propertyLocationPickerProvider.overrideWithValue((context,{initialLatitude,initialLongitude}) async {
        picks++;expect(initialLatitude,13.96);expect(initialLongitude,44.18);
        return picks==1 ? null : const PropertyLocationSelection(latitude:13.96,longitude:44.18,
          address:PropertyLocationAddress(governorate:'إب',district:'السبل',street:'المدخل'));
      }),
    ],child:const ListingEditorScreen()),recovery:recovery,boundary:boundary);
    final governorate=textField('المحافظة *'),gps=find.byKey(const ValueKey('listing-current-location'));
    expect(tester.widget<TextField>(governorate).enabled,isFalse);
    await tester.ensureVisible(gps);await tester.tap(gps);await tester.pumpAndSettle();
    expect(tester.widget<TextField>(governorate).enabled,isFalse);
    await tester.tap(gps);await tester.pumpAndSettle();
    expect(tester.widget<TextField>(governorate).enabled,isTrue);
    expect(tester.widget<TextField>(governorate).controller!.text,'إب');
    await tester.ensureVisible(governorate);await tester.enterText(governorate,'تعز');await tester.pump(const Duration(seconds:1));
    expect(recovery.snapshot!['latitude'],13.96);expect(recovery.snapshot!['longitude'],44.18);
    expect((recovery.snapshot!['fields'] as Map)['governorate'],'تعز');expect(fixes,2);expect(picks,2);
    FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();
    await previewWave6(tester,boundary,'new-wave-confirmed-location-1.0');
    expect(tester.takeException(),isNull);await finishWave6(tester);
  });

  testWidgets('customer help is remembered once for each account', (tester) async {
    final help=_Help();
    Future<void> open(int id) => pumpWave6(tester,ProviderScope(overrides:[
      authControllerProvider.overrideWith(()=>_Account(id)),customerHelpStoreProvider.overrideWithValue(help),
      brokerRepositoryProvider.overrideWithValue(_Customers()),
    ],child:const BrokerCustomersScreen()));
    await open(1);expect(find.byKey(const ValueKey('customer-help-dismiss')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('customer-help-dismiss')));await tester.pumpAndSettle();expect(help.accounts,{1});
    await finishWave6(tester);await open(1);expect(find.byKey(const ValueKey('customer-help-dismiss')),findsNothing);
    await finishWave6(tester);await open(2);expect(find.byKey(const ValueKey('customer-help-dismiss')),findsOneWidget);
    expect(find.textContaining('من أول تواصل'),findsOneWidget);await finishWave6(tester);
  });

  for(final scale in [1.0,2.4]) {
  testWidgets('broker robot keeps navigation usable with both AI paths at $scale', (tester) async {
    final boundary=GlobalKey();
    await pumpWave6(tester,const AppShellScreen(),boundary:boundary,scale:scale);
    final nav=find.byType(AppNavigationBar);
    expect(tester.widget<AppNavigationBar>(nav).destinations.map((d)=>d.label),['العقارات','الخريطة','الرسائل','حسابي']);
    await tester.tap(find.byKey(const ValueKey('floating-smart-search')));await tester.pumpAndSettle();
    expect(find.text('بحث عن عقار بالذكاء'),findsOneWidget);expect(find.text('إضافة عقار بالذكاء'),findsOneWidget);
    expect(find.text('تعبئة يدوي'),findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey('create-listing-scrim'))).bottom,lessThanOrEqualTo(tester.getRect(nav).top));
    expect(find.byKey(const ValueKey('home-add-property')).hitTestable(),findsOneWidget);
    await previewWave6(tester,boundary,'new-wave-robot-$scale');
    final scope=ProviderScope.containerOf(tester.element(find.byType(SmartSearchAssistantLayer)));
    expect(scope.read(brokerAssistantMenuProvider),isTrue);
    await tester.tapAt(const Offset(360,250));await tester.pumpAndSettle();
    expect(scope.read(brokerAssistantMenuProvider),isFalse);expect(tester.takeException(),isNull);
    await finishWave6(tester);
  });
  }
}
