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
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth;
import 'support/wave3_fakes.dart';

class _Assistant extends Wave3AiFake {
  bool fail = false;
  Map<String, dynamic>? composedFacts;
  int prepares = 0;
  Map<String, dynamic> get proposals => {'bedrooms': 4, 'has_elevator': true};
  @override
  Future<Map<String, dynamic>> prepareListing(String message, Map<String, dynamic> facts, {int? propertyId}) async {
    prepares++;
    if (fail) throw StateError('Temporary failure');
    return {'fields': proposals, 'source': 'text', 'requires_review': true,
      'message': 'تعذّر المساعد الذكي الآن. رتّبنا المعلومات الصريحة من النص فقط؛ راجعها وأكمل الناقص.',
      'copy': {'title': 'شقة للإيجار في صنعاء', 'description': 'شقة للإيجار، غرف النوم: 4، يوجد مصعد.'}};
  }
  @override
  Future<Map<String, dynamic>> listingCopy(Map<String, dynamic> facts, {int? propertyId}) async {
    composedFacts = Map.of(facts);
    return {'source': 'facts', 'copy': {'title': 'شقة للإيجار في صنعاء', 'description': 'شقة للإيجار، غرف النوم: 4.'}};
  }
}

class _Recovery extends ListingRecoveryStore {
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
    advertiserType: 'broker', fixedRatePercent: 1, brokerMaxRatePercent: 5, professionalPlatformSharePercent: 20);
}

Map<String, dynamic> _snapshot() => {
  'editor_version': 7, 'step': 3, 'type': 'house', 'purpose': 'sale', 'tenure_type': 'freehold',
  'latitude': 15.3694, 'longitude': 44.1910, 'parking': 'no', 'facade': 'north', 'sai_touched': true,
  'fields': {'title': 'منزل اختبار المساعد', 'description': 'وصف مدخل يدويًا', 'price': '10000000',
    'area': '160', 'bedrooms': '3', 'bathrooms': '2', 'governorate': 'صنعاء', 'district': 'حدة',
    'document_owner_name': 'اسم مستند خاص', 'relationship_note': 'ملاحظة علاقة خاصة', 'broker_sai_rate_percent': '2'},
};

Future<void> _pump(WidgetTester tester, Widget child, {required _Assistant ai, _Recovery? recovery,
  Wave3VoiceFake? voice, double scale = 1, GlobalKey? boundary}) async {
  tester.view.physicalSize = const Size(412, 915); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    aiRepositoryProvider.overrideWithValue(ai), propertyRepositoryProvider.overrideWithValue(_Properties()),
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

  testWidgets('deselection invalidates copy and only reviewed fields and recomposed text are applied', (tester) async {
    final ai = _Assistant(); Map<String, dynamic>? applied;
    await _pump(tester, Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
      applied = await AppBottomSheet.show<Map<String, dynamic>>(context,
        builder: (_) => const ListingAiSheet(prepareDraft: true, facts: {'type': 'apartment', 'bedrooms': 2}));
    }, child: const Text('تجهيز')))), ai: ai);
    await tester.tap(find.text('تجهيز')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('listing-ai-brief')), '4 غرف نوم ويوجد مصعد');
    await _tap(tester, 'listing-ai-prepare');
    expect(applied, isNull); expect(find.textContaining('الحالي: 2'), findsOneWidget);
    await _tap(tester, 'listing-ai-field-has_elevator');
    expect(find.byKey(const ValueKey('listing-ai-apply-draft')), findsNothing);
    expect(find.byKey(const ValueKey('listing-ai-copy')), findsNothing);
    await _tap(tester, 'listing-ai-refresh-copy');
    expect(ai.composedFacts, {'type': 'apartment', 'bedrooms': 4});
    await _tap(tester, 'listing-ai-apply-draft');
    expect(applied!['bedrooms'], 4); expect(applied!.containsKey('has_elevator'), isFalse);
    expect(applied!['description'], isNot(contains('مصعد'))); expect(tester.takeException(), isNull);
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
    expect(find.text('2/4'), findsOneWidget); expect(find.text('اختيار من الخريطة'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); await tester.pumpAndSettle();
    final fields = recovery.snapshot!['fields'] as Map;
    expect(fields['ai_listing_brief'], 'شقة في صنعاء أربع غرف');
    expect(fields['title'], 'شقة للإيجار في صنعاء');
    expect(fields['description'], contains('غرف النوم: 4'));
    expect(ai.prepares, 1); expect(tester.takeException(), isNull);
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

  for (final scale in [1.0, 2.4]) {
    testWidgets('assistant remains readable and scrollable at Arabic scale $scale', (tester) async {
      final key = GlobalKey();
      await _pump(tester, const Scaffold(body: ListingAiSheet(prepareDraft: true, facts: {}, initialMessage: 'شقة أربع غرف مع مصعد')),
        ai: _Assistant(), scale: scale, boundary: key);
      await _tap(tester, 'listing-ai-prepare');
      await _capture(tester, key, 'review-$scale');
      await _tap(tester, 'listing-ai-field-has_elevator');
      await _tap(tester, 'listing-ai-refresh-copy');
      await _reveal(tester, 'listing-ai-apply-draft');
      await _capture(tester, key, 'copy-$scale');
      expect(find.byKey(const ValueKey('listing-ai-apply-draft')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
