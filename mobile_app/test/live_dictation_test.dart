import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/platform/voice_capture_controller.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'support/wave3_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live bridge previews corrections but only a complete post-stop final becomes text', (tester) async {
    const channel = MethodChannel('real_estate/speech');
    final commands = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { commands.add(call); return null; });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    var uploads = 0;
    final capture = VoiceCaptureController(SystemVoiceInput(liveDictation: true, transcribe: (_, __) async { uploads++; return 'unused'; }));
    addTearDown(capture.dispose);
    Future<void> event(int id, String type, {String text = '', String code = '', bool complete = false}) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('event',
          {'id': id, 'type': type, 'text': text, 'code': code, 'complete': complete})), null);
      await tester.pump();
    }
    final result = capture.start(); await tester.pump();
    final args = commands.first.arguments as Map, id = args['id'] as int;
    expect(args['mode'], 'dictation');
    await event(id, 'mode', code: 'dictation'); await event(id, 'ready');
    await event(id, 'partial', text: 'ابحث في تعز');
    expect(capture.preview, 'ابحث في تعز'); expect(capture.transcript, isEmpty);
    await event(id, 'partial', text: 'ابحث في صنعاء للإيجار');
    expect(capture.preview, 'ابحث في صنعاء للإيجار');
    await event(id, 'final', text: 'premature', complete: true);
    expect(capture.active, isTrue); expect(capture.transcript, isEmpty);
    capture.stop(); capture.stop(); await tester.pump();
    expect(commands.where((c) => c.method == 'stop'), hasLength(1));
    await event(id, 'final', text: 'incomplete'); expect(capture.active, isTrue);
    await event(id + 1, 'final', text: 'wrong session', complete: true); expect(capture.active, isTrue);
    await event(id, 'final', text: 'ابحث في صنعاء للإيجار ثلاث غرف', complete: true);
    expect(await result, 'ابحث في صنعاء للإيجار ثلاث غرف'); expect(uploads, 0);
    expect(commands.last.method, 'release'); expect(capture.active, isFalse);
  });

  testWidgets('a device without dictation retains complete-clip transcription after explicit finish', (tester) async {
    const channel = MethodChannel('real_estate/speech');
    final commands = <MethodCall>[], paths = <String>[];
    final uploaded = Completer<String>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { commands.add(call); return null; });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final capture = VoiceCaptureController(SystemVoiceInput(liveDictation: true, transcribe: (path, _) { paths.add(path); return uploaded.future; }));
    addTearDown(capture.dispose);
    Future<void> event(int id, String type, {String code = '', String path = ''}) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('event', {'id': id, 'type': type, 'code': code, 'path': path})), null);
      await tester.pump();
    }
    final result = capture.start(); await tester.pump(); final id = (commands.first.arguments as Map)['id'] as int;
    await event(id, 'mode', code: 'clip'); await event(id, 'ready');
    expect(capture.liveDictation, isFalse);
    await event(id, 'recorded', path: 'premature.m4a'); expect(paths, isEmpty);
    capture.stop(); await tester.pump(); await event(id, 'recorded', path: 'whole.m4a');
    expect(paths, ['whole.m4a']); expect(capture.transcript, isEmpty);
    uploaded.complete('نص التسجيل كاملًا'); await tester.pump();
    expect(await result, 'نص التسجيل كاملًا'); expect(commands.last.method, 'release');
  });

  testWidgets('explicit whole recording bypasses dictation and releases the clip after one complete upload', (tester) async {
    const channel = MethodChannel('real_estate/speech');
    final commands = <MethodCall>[], paths = <String>[];
    final uploaded = Completer<String>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { commands.add(call); return null; });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final capture = VoiceCaptureController(SystemVoiceInput(liveDictation: true, transcribe: (path, _) {
      paths.add(path); return uploaded.future;
    }));
    addTearDown(capture.dispose);
    Future<void> event(int id, String type, {String code = '', String path = '', String text = ''}) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('event',
          {'id': id, 'type': type, 'code': code, 'path': path, 'text': text, 'complete': true})), null);
      await tester.pump();
    }
    final result = capture.start(wholeRecording: true); await tester.pump();
    final args = commands.single.arguments as Map, id = args['id'] as int;
    expect(args['mode'], 'clip');
    await event(id, 'mode', code: 'clip'); await event(id, 'ready');
    await event(id, 'partial', text: 'لا يعتمد هذا الجزء');
    await event(id, 'final', text: 'لا يعتمد هذا الجزء');
    await event(id, 'recorded', path: 'premature.m4a');
    expect(capture.preview, isEmpty); expect(capture.transcript, isEmpty); expect(paths, isEmpty);
    capture.stop(); capture.stop(); await tester.pump();
    expect(commands.where((c) => c.method == 'stop'), hasLength(1));
    await event(id, 'recorded', path: 'complete-listing.m4a');
    await event(id, 'recorded', path: 'duplicate.m4a');
    expect(paths, ['complete-listing.m4a']); expect(capture.transcript, isEmpty);
    uploaded.complete('شقة للإيجار في إب ثلاث غرف وحمامان'); await tester.pump();
    expect(await result, 'شقة للإيجار في إب ثلاث غرف وحمامان');
    expect(commands.where((c) => c.method == 'release'), hasLength(1));
    expect(capture.active, isFalse);
  });

  testWidgets('an error never promotes a preview and cancellation rejects delayed results', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false); addTearDown(voice.dispose);
    final capture = VoiceCaptureController(voice); addTearDown(capture.dispose);
    final result = capture.start();
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('partial', text: 'معلومة غير مكتملة'));
    await tester.pump(); expect(capture.preview, isNotEmpty);
    voice.latest.emit(const VoiceEvent('error', code: 'SPEECH_NETWORK')); await tester.pump();
    expect(await result, isNull); expect(capture.transcript, isEmpty); expect(capture.error, isNotNull);
    final next = capture.start(); voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    capture.cancel(); voice.latest.emit(const VoiceEvent('final', text: 'متأخر')); await tester.pump();
    expect(await next, isNull); expect(capture.transcript, isEmpty); expect(capture.preview, isEmpty);
  });

  testWidgets('dictation appends to typed search, waits for final then permits a separate edited submission', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    addTearDown(voice.dispose);
    final container = ProviderContainer(overrides: [
      voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai),
      propertyRepositoryProvider.overrideWithValue(properties),
    ]); addTearDown(container.dispose);
    final session = container.read(smartSearchSessionProvider.notifier);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(theme: AppTheme.light, home: const AssistedSearchScreen())));
    await tester.pumpAndSettle();
    session.replaceManually(SmartSearchFilters.fromMap({'type': 'apartment', 'purpose': 'rent', 'search': 'صنعاء'}));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('smart-search-description'));
    await tester.enterText(input, 'شقة للإيجار');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice')));
    await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('partial', text: 'في تعز')); await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, 'شقة للإيجار في تعز');
    voice.latest.emit(const VoiceEvent('partial', text: 'في صنعاء')); await tester.pump(const Duration(seconds: 12));
    expect(tester.widget<TextField>(input).controller!.text, 'شقة للإيجار في صنعاء');
    expect(ai.requests, isEmpty); expect(voice.latest.stops, 0);
    await tester.ensureVisible(find.byKey(const ValueKey('voice-finish'))); await tester.tap(find.byKey(const ValueKey('voice-finish'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('final', text: 'في صنعاء ثلاث غرف')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).readOnly, isFalse);
    expect(tester.widget<TextField>(input).controller!.text, 'شقة للإيجار في صنعاء ثلاث غرف');
    expect(ai.requests, hasLength(1));
    expect(ai.requests.single.message, 'شقة للإيجار في صنعاء ثلاث غرف');
    await tester.enterText(input, 'شقة للإيجار في صنعاء أربع غرف');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-send'))); await tester.tap(find.byKey(const ValueKey('smart-search-send'))); await tester.pumpAndSettle();
    expect(ai.requests, hasLength(2));
    expect(ai.requests.last.message, 'شقة للإيجار في صنعاء أربع غرف');
    expect(ai.requests.last.filters['search'], 'صنعاء');
    expect(find.byKey(const ValueKey('smart-search-result-11')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('listing previews stay in the original input without persisting or calling AI until accepted', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    addTearDown(voice.dispose);
    final saved = <String>[];
    await tester.pumpWidget(ProviderScope(overrides: [
      voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai),
    ], child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: ListingAiSheet(
      facts: const {}, initialMessage: 'شقة', onMessageChanged: saved.add)))));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('listing-ai-brief'));
    await tester.tap(find.byKey(const ValueKey('listing-ai-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('partial', text: 'في تعز')); await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, 'شقة في تعز');
    expect(saved, isEmpty);
    await tester.ensureVisible(find.byKey(const ValueKey('voice-cancel'))); await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'شقة');
    expect(saved.where((s) => s.contains('تعز')), isEmpty);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-ai-voice'))); await tester.tap(find.byKey(const ValueKey('listing-ai-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('voice-finish'))); await tester.tap(find.byKey(const ValueKey('voice-finish'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('final', text: 'في صنعاء ثلاث غرف')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'شقة في صنعاء ثلاث غرف');
    expect(saved.last, 'شقة في صنعاء ثلاث غرف');
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-ai-prepare'))); await tester.tap(find.byKey(const ValueKey('listing-ai-prepare'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-ai-field-bedrooms')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

