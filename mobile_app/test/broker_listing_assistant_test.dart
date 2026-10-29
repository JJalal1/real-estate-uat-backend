import 'support/wave6_fakes.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/domain/property_location_address.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_preview.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth;
import 'support/wave3_fakes.dart';

class _Assistant extends Wave3AiFake {
  bool fail = false;
  Map<String, dynamic>? composedFacts;
  int prepares = 0;
  Map<String, dynamic> get proposals => {'bedrooms': 4, 'has_parking': true};
  @override
  Future<Map<String, dynamic>> prepareListing(String message, Map<String, dynamic> facts, {int? propertyId, String? draftKey}) async {
    prepares++;
    if (fail) throw StateError('Temporary failure');
    return {'fields': proposals, 'source': 'text', 'requires_review': true,
      'message': 'تعذّر المساعد الذكي الآن. رتّبنا المعلومات الصريحة من النص فقط؛ راجعها وأكمل الناقص.',
      'copy': {'title': 'شقة للإيجار في صنعاء', 'description': 'شقة للإيجار، غرف النوم: 4، يوجد موقف.'}};
  }
  @override
  Future<Map<String, dynamic>> listingCopy(Map<String, dynamic> facts, {int? propertyId, String? draftKey}) async {
    composedFacts = Map.of(facts);
    return {'source': 'facts', 'copy': {'title': 'شقة للإيجار في صنعاء', 'description': 'شقة للإيجار، غرف النوم: 4.'}};
  }
}

const ownerBrief = 'شقة للايجار في اب شارع السبل ثلاث غرف واثنين حمامات\nويوجد موقف سيارات\nمطلوب ايجار مقدم ثلاثة اشهر وضمانه تجاريه\nالسعر مئة الف ريال ونسبة السعي 100%';
class _CompleteAssistant extends _Assistant {
  String? received;
  @override
  Map<String,dynamic> get proposals => {'type':'apartment','purpose':'rent','governorate':'إب','street':'السبل',
    'bedrooms':3,'bathrooms':2,'monthly_rent':100000,'has_parking':true,'sai_amount_type':'percentage','broker_sai_rate_percent':100,
    'rental_conditions':[{'kind':'advance','months':3},{'kind':'guarantor'}]};
  @override
  Future<Map<String,dynamic>> prepareListing(String message, Map<String,dynamic> facts,{int? propertyId,String? draftKey}) async {
    received=message; prepares++;
    return {'fields':proposals,'source':'ai','requires_review':true,'message':'راجع بياناتك ثم استخدمها.',
      'copy':{'title':'شقة للإيجار في إب','description':'شقة للإيجار في إب، شارع السبل. تضم 3 غرف نوم وحمامين ويتوفر موقف. الإيجار الشهري 100000 ريال. مقدم 3 أشهر وضمانة تجارية. السعي 100%.'}};
  }
}

class _PinnedAssistant extends _Assistant {
  @override
  Map<String, dynamic> get proposals => {'type':'house','purpose':'sale','governorate':'اب','district':'المدينة','street':'الروضة'};
  @override
  Future<Map<String, dynamic>> prepareListing(String message, Map<String, dynamic> facts, {int? propertyId, String? draftKey}) async => {
    'fields': proposals, 'source':'ai', 'requires_review':true,
    'copy':{'title':'منزل للبيع في إب','description':'منزل للبيع في إب، شارع الروضة.'},
  };
}

class _Recovery extends ListingRecoveryStore {
  @override
  Future<List<Map<String,dynamic>>> saved(int userId) async => [];
  @override
  Future<void> pinExplicitSave(int userId, {bool preserveUnclassified = false}) async {}
  @override
  Future<void> deleteSaved(int userId, String key) async {}

  _Recovery(this.snapshot);
  Map<String, dynamic>? snapshot;
  @override
  Future<Map<String, dynamic>?> read(int userId, int? listingId) async => snapshot;
  @override
  Future<void> write(int userId, int? listingId, Map<String, dynamic> value, List<String> paths) async { snapshot = value; }
  @override
  Future<void> clear(int userId, int? listingId) async { snapshot = null; }
}

class _Properties extends Wave3PropertiesFake {
  @override
  Future<PropertySaiManagement> saiPolicy(String purpose) async => const PropertySaiManagement(configured: false,
    advertiserType: 'broker', fixedRatePercent: 1, brokerMaxRatePercent: 5, fallbackPlatformSharePercent: 100, professionalPlatformSharePercent: 20);
}

Map<String, dynamic> _snapshot() => {
  'editor_version': 7, 'units_per_floor': ['2','1'], 'step': 3, 'type': 'house', 'purpose': 'sale', 'tenure_type': 'freehold',
  'latitude': 15.3694, 'longitude': 44.1910, 'parking': 'no', 'facade': 'north', 'sai_touched': true,
  'fields': {'title': 'منزل اختبار المساعد', 'description': 'وصف مدخل يدويًا', 'price': '10000000',
    'floors_count': '2', 'phone': '771234567', 'area': '160', 'bedrooms': '3', 'bathrooms': '2', 'governorate': 'صنعاء', 'district': 'حدة',
    'document_owner_name': 'اسم مستند خاص', 'relationship_note': 'ملاحظة علاقة خاصة', 'broker_sai_rate_percent': '2'},
};

Future<void> _pump(WidgetTester tester, Widget child, {required _Assistant ai, _Recovery? recovery,
  Wave3VoiceFake? voice, double scale = 1, GlobalKey? boundary, PropertyLocationPicker? picker, Wave6Drafts? drafts}) async {
  tester.view.physicalSize = const Size(412, 915); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    aiRepositoryProvider.overrideWithValue(ai), propertyRepositoryProvider.overrideWithValue(_Properties()),
    listingAccountDraftRepositoryProvider.overrideWithValue(drafts ?? Wave6Drafts()),
    if (picker != null) propertyLocationPickerProvider.overrideWithValue(picker),
    propertyMapPreviewBuilderProvider.overrideWithValue((context,lat,lon) => Text('نقطة اختبار $lat,$lon')),
    authControllerProvider.overrideWith(() => BrokerTestAuth(1)),
    listingRecoveryStoreProvider.overrideWithValue(recovery ?? _Recovery(null)),
    voiceInputProvider.overrideWithValue(voice ?? Wave3VoiceFake()),
  ], child: MaterialApp(theme: AppTheme.light,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(key: boundary, child: child!)), home: child)));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    final sheet = find.byType(ListingAiSheet);
    final scrollable = sheet.evaluate().isEmpty ? find.byType(Scrollable).first
      : find.descendant(of: sheet, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(finder, 220, scrollable: scrollable);
  }
  await tester.ensureVisible(finder); await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  final finder = find.byKey(ValueKey(key));
  await tester.tap(finder); await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/broker-preview/assistant-$name.png');
    await out.parent.create(recursive: true); await out.writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final name in ['sans-serif', 'NotoSansArabic']) {
      await (FontLoader(name)..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    }
    final primary = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf'));
    }
    await primary.load();
    final root = Platform.environment['FLUTTER_ROOT']!;
    final icons = await File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });

  for (final scale in [1.0, 2.4]) {
    testWidgets('inline listing dictation preserves typed context at scale $scale', (tester) async {
      final voice = Wave3VoiceFake(autoComplete: false); addTearDown(voice.dispose);
      final boundary = GlobalKey();
      await _pump(tester, const Scaffold(body: ListingAiSheet(prepareDraft: true, facts: {}, initialMessage: 'شقة للإيجار')),
        ai: _Assistant(), voice: voice, scale: scale, boundary: boundary);
      await tester.ensureVisible(find.byKey(const ValueKey('listing-ai-voice')));
      await tester.tap(find.byKey(const ValueKey('listing-ai-voice'))); await tester.pump();
      voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
      voice.latest.emit(const VoiceEvent('ready'));
      voice.latest.emit(const VoiceEvent('partial', text: 'في صنعاء ثلاث غرف، الإيجار مئة ألف ريال'));
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.widget<TextField>(find.byKey(const ValueKey('listing-ai-brief'))).controller!.text,
        'شقة للإيجار في صنعاء ثلاث غرف، الإيجار مئة ألف ريال');
      await _capture(tester, boundary, 'voice-inline-$scale');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('voice-finish'))); await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('voice-finish')).hitTestable(), findsOneWidget);
      if (scale == 2.4) await _capture(tester, boundary, 'voice-controls-2.4');
      await tester.ensureVisible(find.byKey(const ValueKey('voice-cancel')));
      await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('listing-ai-brief'))).controller!.text, 'شقة للإيجار');
    });
  }

  for(final byVoice in [false,true]) {
    testWidgets('complete owner brief fills every supplied field after explicit review via ${byVoice?'voice':'typing'}',(tester) async {
      final ai=_CompleteAssistant(), voice=Wave3VoiceFake(autoComplete:false); addTearDown(voice.dispose);
      final boundary=GlobalKey();
      Map<String,dynamic>? applied;
      await _pump(tester,Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:() async {
        applied=await AppBottomSheet.show<Map<String,dynamic>>(context,builder:(_)=>const ListingAiSheet(prepareDraft:true,facts:{}));
      },child:const Text('تجهيز الوصف')))),ai:ai,voice:voice,boundary:boundary);
      await tester.tap(find.text('تجهيز الوصف'));await tester.pumpAndSettle();
      if(byVoice){
        await _tap(tester,'listing-ai-voice');voice.latest.emit(const VoiceEvent('ready'));await tester.pump();
        voice.latest.emit(const VoiceEvent('partial',text:ownerBrief));await tester.pump();
        expect(ai.prepares,0);expect(applied,isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('voice-finish')));await tester.pump(const Duration(milliseconds:180));
        await tester.tap(find.byKey(const ValueKey('voice-finish')));await tester.pump();
        voice.latest.emit(const VoiceEvent('final',text:ownerBrief));await tester.pumpAndSettle();
        expect(ai.prepares,0);expect(applied,isNull);
      }else{await tester.enterText(find.byKey(const ValueKey('listing-ai-brief')),ownerBrief);}
      await _tap(tester,'listing-ai-prepare'); expect(ai.received,ownerBrief);expect(applied,isNull);
      await _reveal(tester,'listing-ai-field-type');
      await _capture(tester,boundary,'complete-fields-${byVoice?'voice':'typed'}');
      for(final field in ai.proposals.keys.where((key) => key != 'sai_amount_type')) { await _reveal(tester,'listing-ai-field-$field'); }
      expect(find.text('نوع السعي'), findsNothing);
      expect(find.byKey(const ValueKey('listing-ai-field-sai_amount_type')), findsNothing);
      await _reveal(tester,'listing-ai-apply-draft');
      await _capture(tester,boundary,'complete-copy-${byVoice?'voice':'typed'}');
      await _tap(tester,'listing-ai-apply-draft');
      for(final field in ai.proposals.keys) { expect(applied![field],ai.proposals[field],reason:field); }
      expect(applied!['title'],'شقة للإيجار في إب');expect(applied!['description'],contains('ضمانة تجارية'));
      expect(ai.prepares,1);expect(tester.takeException(),isNull);
    });
  }

  testWidgets('deselection invalidates copy and only reviewed fields and recomposed text are applied', (tester) async {
    final ai = _Assistant(); Map<String, dynamic>? applied;
    await _pump(tester, Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
      applied = await AppBottomSheet.show<Map<String, dynamic>>(context,
        builder: (_) => const ListingAiSheet(prepareDraft: true, facts: {'type': 'apartment', 'bedrooms': 2}));
    }, child: const Text('تجهيز')))), ai: ai);
    await tester.tap(find.text('تجهيز')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('listing-ai-brief')), '4 غرف نوم ويوجد موقف');
    await _tap(tester, 'listing-ai-prepare');
    expect(applied, isNull); expect(find.textContaining('الحالي: ٢'), findsOneWidget);
    await _tap(tester, 'listing-ai-field-has_parking');
    expect(find.byKey(const ValueKey('listing-ai-apply-draft')), findsNothing);
    expect(find.byKey(const ValueKey('listing-ai-copy')), findsNothing);
    await _tap(tester, 'listing-ai-refresh-copy');
    expect(ai.composedFacts, {'type': 'apartment', 'bedrooms': 4});
    await _tap(tester, 'listing-ai-apply-draft');
    expect(applied!['bedrooms'], 4); expect(applied!.containsKey('has_parking'), isFalse);
    expect(applied!['description'], isNot(contains('موقف'))); expect(tester.takeException(), isNull);
  });

  testWidgets('request failure and canceled recording retain the typed draft and never apply', (tester) async {
    final ai = _Assistant()..fail = true, voice = Wave3VoiceFake(autoComplete: false);
    addTearDown(voice.dispose);
    await _pump(tester, const Scaffold(body: ListingAiSheet(prepareDraft: true, facts: {}, initialMessage: 'مسودتي السابقة')),
      ai: ai, voice: voice);
    await _tap(tester, 'listing-ai-prepare');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('listing-ai-brief'))).controller!.text, 'مسودتي السابقة');
    await _tap(tester, 'listing-ai-voice');
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('voice-cancel'))); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
    expect(voice.latest.cancellations, greaterThan(0));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('listing-ai-brief'))).controller!.text, 'مسودتي السابقة');
    expect(find.byKey(const ValueKey('listing-ai-apply-draft')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor applies reviewed copy locally, recovers brief and directs to missing location', (tester) async {
    final snapshot = _snapshot()..['step'] = 0..['latitude'] = null..['longitude'] = null;
    final recovery = _Recovery(snapshot), ai = _Assistant();
    await _pump(tester, const ListingEditorScreen(), ai: ai, recovery: recovery);
    await _tap(tester, 'listing-draft-assistant');
    await tester.enterText(find.byKey(const ValueKey('listing-ai-brief')), 'شقة في صنعاء أربع غرف');
    await _tap(tester, 'listing-ai-prepare');
    await _tap(tester, 'listing-ai-apply-draft');
    expect(find.text('أكمل الناقص فقط'), findsOneWidget);
    expect(find.text('2/4'), findsNothing);
    expect(find.text('تأكيد الموقع على الخريطة'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); await tester.pumpAndSettle();
    final fields = recovery.snapshot!['fields'] as Map;
    expect(fields['ai_listing_brief'], 'شقة في صنعاء أربع غرف');
    expect(fields['title'], 'شقة للإيجار في صنعاء');
    expect(fields['description'], contains('غرف النوم: 4'));
    expect(ai.prepares, 1); expect(tester.takeException(), isNull);
  });

  testWidgets('the complete owner brief populates the canonical editor including rental conditions and explicit Sai', (tester) async {
    final snapshot = _snapshot()..['step'] = 0;
    final recovery = _Recovery(snapshot), ai = _CompleteAssistant();
    await _pump(tester, const ListingEditorScreen(), ai: ai, recovery: recovery);
    await _tap(tester, 'listing-draft-assistant');
    await tester.enterText(find.byKey(const ValueKey('listing-ai-brief')), ownerBrief);
    await _tap(tester, 'listing-ai-prepare');
    await _tap(tester, 'listing-ai-apply-draft');
    await tester.pump(const Duration(seconds: 1)); await tester.pumpAndSettle();
    final saved = recovery.snapshot!, fields = saved['fields'] as Map;
    expect(saved['type'], 'apartment'); expect(saved['purpose'], 'rent');
    expect(saved['parking'], 'yes'); expect(saved['sai_amount_type'], 'percentage');
    expect(saved['rental_conditions'], ai.proposals['rental_conditions']);
    expect(fields['governorate'], 'إب'); expect(fields['street'], 'السبل');
    expect(fields['bedrooms'], '3'); expect(fields['bathrooms'], '2');
    expect(fields['monthly_rent'], '100000'); expect(fields['broker_sai_rate_percent'], '100');
    expect(fields['title'], 'شقة للإيجار في إب'); expect(fields['description'], contains('ضمانة تجارية'));
    expect(saved['latitude'], 15.3694); expect(saved['longitude'], 44.1910);
    expect(fields['floor_number'], isEmpty); expect(fields['area'], isEmpty);
    expect(find.text('أكمل الناقص فقط'), findsOneWidget); expect(ai.prepares, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion navigation respects required photos before the price step', (tester) async {
    final snapshot = _snapshot(); (snapshot['fields'] as Map)['price'] = '';
    final key = GlobalKey();
    await _pump(tester, const ListingEditorScreen(), ai: _Assistant(), recovery: _Recovery(snapshot), boundary: key);
    await _tap(tester, 'listing-completion');
    await _capture(tester, key, 'completion');
    final price = find.text('أدخل سعراً صحيحاً أكبر من صفر.');
    await tester.ensureVisible(price); await tester.tap(price); await tester.pumpAndSettle();
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('أضف صورًا حقيقية للعقار قبل المتابعة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview copies public ad text on explicit tap without private evidence or finance splits', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester, const ListingEditorScreen(), ai: _Assistant(), recovery: _Recovery(_snapshot()));
    await tester.tap(find.byTooltip('خيارات المسودة')); await tester.pumpAndSettle();
    await tester.tap(find.text('معاينة')); await tester.pumpAndSettle();
    expect(clipboard, isNull);
    await _tap(tester, 'listing-copy-text');
    expect(clipboard, contains('منزل اختبار المساعد')); expect(clipboard, contains('وصف مدخل يدويًا'));
    for (final private in ['اسم مستند خاص', 'ملاحظة علاقة خاصة', 'صافي السعي', 'مستحق المنصة']) {
      expect(clipboard, isNot(contains(private)));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed map point survives back, canceled editing and account draft recovery', (tester) async {
    final snapshot = _snapshot()..['step'] = 1..['latitude'] = null..['longitude'] = null;
    final recovery = _Recovery(snapshot), drafts = Wave6Drafts(), boundary = GlobalKey();
    var picks = 0;
    Future<PropertyLocationSelection?> picker(BuildContext context, {double? initialLatitude, double? initialLongitude}) async {
      picks++;
      if (picks == 1) {
        expect(initialLatitude, isNull); expect(initialLongitude, isNull);
        return const PropertyLocationSelection(latitude:13.966, longitude:44.183,
          address:PropertyLocationAddress(governorate:'إب',street:'السيل'));
      }
      expect(initialLatitude,13.966); expect(initialLongitude,44.183);
      return null;
    }
    await _pump(tester,const ListingEditorScreen(),ai:_Assistant(),recovery:recovery,drafts:drafts,picker:picker,boundary:boundary);
    await _tap(tester,'listing-select-location');
    expect(find.text('تم تحديد موقع العقار على الخريطة'),findsOneWidget);
    expect(find.text('نقطة اختبار 13.966,44.183'),findsOneWidget);
    await tester.tap(find.text('التالي'));await tester.pumpAndSettle();
    expect(find.text('3/4'),findsOneWidget);
    await tester.tap(find.text('السابق'));await tester.pumpAndSettle();
    await _tap(tester,'listing-select-location');
    expect(find.text('تم تحديد موقع العقار على الخريطة'),findsOneWidget);
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(recovery.snapshot!['latitude'],13.966);expect(recovery.snapshot!['longitude'],44.183);
    expect((recovery.snapshot!['fields'] as Map)['district'],isEmpty);
    expect(drafts.saves.last['latitude'],13.966);expect(drafts.saves.last['longitude'],44.183);
    await tester.pumpWidget(const SizedBox.shrink());await tester.pumpAndSettle();
    await _pump(tester,const ListingEditorScreen(),ai:_Assistant(),recovery:recovery,drafts:drafts,picker:picker,boundary:boundary);
    expect(find.text('تم تحديد موقع العقار على الخريطة'),findsOneWidget);
    await _capture(tester,boundary,'complete-pin-restored');
    await tester.tap(find.text('التالي'));await tester.pumpAndSettle();
    expect(find.text('3/4'),findsOneWidget);expect(picks,2);expect(tester.takeException(),isNull);
  });

  testWidgets('closing preview and returning through the location step never asks to select its saved point again', (tester) async {
    final recovery = _Recovery(_snapshot());
    await _pump(tester,const ListingEditorScreen(),ai:_Assistant(),recovery:recovery);
    await tester.tap(find.byTooltip('خيارات المسودة'));await tester.pumpAndSettle();
    await tester.tap(find.text('معاينة'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('إغلاق المعاينة'));await tester.tap(find.text('إغلاق المعاينة'));await tester.pumpAndSettle();
    for (var i=0;i<2;i++) {await tester.tap(find.text('السابق'));await tester.pumpAndSettle();}
    expect(find.text('2/4'),findsOneWidget);
    expect(find.text('تم تحديد موقع العقار على الخريطة'),findsOneWidget);
    await tester.tap(find.text('التالي'));await tester.pumpAndSettle();
    expect(find.text('3/4'),findsOneWidget);
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(recovery.snapshot!['latitude'],15.3694);expect(recovery.snapshot!['longitude'],44.1910);
    expect(find.textContaining('حدد موقع العقار يدويًا'),findsNothing);expect(tester.takeException(),isNull);
  });

  testWidgets('moving to the next full step dismisses typing and starts the new step at its top', (tester) async {
    final snapshot=_snapshot()..['step']=0;
    await _pump(tester,const ListingEditorScreen(),ai:_Assistant(),recovery:_Recovery(snapshot),scale:2.4);
    final title=find.byWidgetPredicate((widget)=>widget is TextField && widget.decoration?.labelText=='عنوان الإعلان *');
    await tester.ensureVisible(title);await tester.pumpAndSettle();
    await tester.tap(title);await tester.pumpAndSettle();
    final scroll=tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(scroll.pixels,greaterThan(0));
    await tester.tap(find.text('التالي'));await tester.pumpAndSettle();
    expect(find.text('2/4'),findsOneWidget);expect(scroll.pixels,0);
    expect(tester.testTextInput.isVisible,isFalse);expect(tester.takeException(),isNull);
  });

  testWidgets('reviewed street changes and Arabic city spelling preserve the already confirmed point', (tester) async {
    final snapshot=_snapshot()..['step']=0..['latitude']=13.966..['longitude']=44.183;
    (snapshot['fields'] as Map)['governorate']='إب';
    final recovery=_Recovery(snapshot);
    await _pump(tester,const ListingEditorScreen(),ai:_PinnedAssistant(),recovery:recovery);
    await _tap(tester,'listing-draft-assistant');
    await tester.enterText(find.byKey(const ValueKey('listing-ai-brief')),'منزل للبيع في اب شارع الروضة');
    await _tap(tester,'listing-ai-prepare');await _tap(tester,'listing-ai-apply-draft');
    expect(find.text('تم تحديد موقع العقار على الخريطة'),findsOneWidget);
    expect(find.text('إرسال للمراجعة'),findsNothing);expect(find.text('معاينة الإعلان'),findsOneWidget);
    await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
    expect(recovery.snapshot!['latitude'],13.966);expect(recovery.snapshot!['longitude'],44.183);
    expect((recovery.snapshot!['fields'] as Map)['street'],'الروضة');
    expect(tester.takeException(),isNull);
  });

  testWidgets('address text alone requires manual map confirmation and its warning stays above navigation', (tester) async {
    final snapshot=_snapshot()..['step']=1..['latitude']=null..['longitude']=null;
    final boundary=GlobalKey();
    await _pump(tester,const ListingEditorScreen(),ai:_Assistant(),recovery:_Recovery(snapshot),boundary:boundary);
    expect(find.text('حدد نقطة العقار أولًا'),findsOneWidget);
    expect(find.textContaining('بعدها يمكنك تصحيح العنوان'),findsOneWidget);
    expect(find.text('تحديد موقعي الحالي'),findsOneWidget);
    await tester.tap(find.text('التالي'));await tester.pumpAndSettle();
    expect(find.text('2/4'),findsOneWidget);
    final error=find.text('حدد نقطة العقار على الخريطة أو من موقعك الحالي، ثم أكد الموقع.');
    expect(error,findsOneWidget);
    final bar=tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar!;
    expect(tester.getRect(error).bottom,lessThanOrEqualTo(tester.getRect(find.byWidget(bar)).top+1));
    expect(find.text('التالي').hitTestable(),findsOneWidget);
    await _capture(tester,boundary,'complete-required-map');expect(tester.takeException(),isNull);
  });

  testWidgets('deselecting the visible Sai value also removes its hidden discriminator from recomposition and apply', (tester) async {
    final ai=_CompleteAssistant();Map<String,dynamic>? applied;
    await _pump(tester,Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async {
      applied=await AppBottomSheet.show<Map<String,dynamic>>(context,builder:(_)=>const ListingAiSheet(prepareDraft:true,facts:{},initialMessage:ownerBrief));
    },child:const Text('ابدأ')))),ai:ai);
    await tester.tap(find.text('ابدأ'));await tester.pumpAndSettle();await _tap(tester,'listing-ai-prepare');
    expect(find.text('نوع السعي'),findsNothing);
    await _tap(tester,'listing-ai-field-broker_sai_rate_percent');await _tap(tester,'listing-ai-refresh-copy');
    expect(ai.composedFacts!.containsKey('sai_amount_type'),isFalse);
    expect(ai.composedFacts!.containsKey('broker_sai_rate_percent'),isFalse);
    await _tap(tester,'listing-ai-apply-draft');
    expect(applied!.containsKey('sai_amount_type'),isFalse);expect(applied!.containsKey('broker_sai_rate_percent'),isFalse);
    expect(tester.takeException(),isNull);
  });

  for (final scale in [1.0,2.4]) {
    testWidgets('review action stays visible while reading every proposed field at scale $scale',(tester)async {
      final boundary=GlobalKey();
      await _pump(tester,const Scaffold(body:ListingAiSheet(prepareDraft:true,facts:{},initialMessage:ownerBrief)),
        ai:_CompleteAssistant(),scale:scale,boundary:boundary);
      await _tap(tester,'listing-ai-prepare');
      final action=find.byKey(const ValueKey('listing-ai-apply-draft'));
      expect(action.hitTestable(),findsOneWidget);
      final before=tester.getRect(action);
      await _reveal(tester,'listing-ai-field-rental_conditions');
      expect(action.hitTestable(),findsOneWidget);expect(tester.getRect(action),before);
      expect(find.byKey(const ValueKey('listing-ai-field-sai_amount_type')),findsNothing);
      await _capture(tester,boundary,'complete-sticky-$scale');expect(tester.takeException(),isNull);
    });
  }

  for (final scale in [1.0, 2.4]) {
    testWidgets('assistant remains readable and scrollable at Arabic scale $scale', (tester) async {
      final key = GlobalKey();
      await _pump(tester, const Scaffold(body: ListingAiSheet(prepareDraft: true, facts: {}, initialMessage: 'شقة أربع غرف مع موقف')),
        ai: _Assistant(), scale: scale, boundary: key);
      await _tap(tester, 'listing-ai-prepare');
      await _capture(tester, key, 'review-$scale');
      await _tap(tester, 'listing-ai-field-has_parking');
      await _tap(tester, 'listing-ai-refresh-copy');
      await _reveal(tester, 'listing-ai-apply-draft');
      await _capture(tester, key, 'copy-$scale');
      expect(find.byKey(const ValueKey('listing-ai-apply-draft')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
