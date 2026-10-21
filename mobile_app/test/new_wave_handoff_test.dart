import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/platform/voice_capture_controller.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_contact_policy.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_schema.dart';
import 'package:real_estate_mobile/features/properties/domain/property_comparison.dart';
import 'package:real_estate_mobile/features/properties/domain/rental_condition_summary.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      await tester.ensureVisible(find.byKey(const ValueKey('listing-units-1')));await tester.enterText(find.byKey(const ValueKey('listing-units-1')),'4');
      await tester.pump(const Duration(seconds:1));
      expect(recovery.snapshot!['units_per_floor'],['2','4','2']);
      expect(find.text('المصعد'),findsNothing);
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

  testWidgets('broker robot menu uses the two AI paths and an outside tap closes it', (tester) async {
    final boundary=GlobalKey();
    await pumpWave6(tester,const Scaffold(body:SmartSearchAssistantLayer(child:ColoredBox(color:Colors.white))),boundary:boundary);
    await tester.tap(find.byKey(const ValueKey('floating-smart-search')));await tester.pumpAndSettle();
    expect(find.text('بحث عن عقار بالذكاء'),findsOneWidget);expect(find.text('إضافة عقار بالذكاء'),findsOneWidget);
    expect(find.text('تعبئة يدوي'),findsNothing);
    await previewWave6(tester,boundary,'new-wave-robot-1.0');
    final scope=ProviderScope.containerOf(tester.element(find.byType(SmartSearchAssistantLayer)));
    expect(scope.read(brokerAssistantMenuProvider),isTrue);
    await tester.tapAt(const Offset(360,80));await tester.pumpAndSettle();
    expect(scope.read(brokerAssistantMenuProvider),isFalse);expect(tester.takeException(),isNull);
    await finishWave6(tester);
  });
}
