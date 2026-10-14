import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/platform/voice_capture_controller.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/home_ai_search_entry.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'support/wave3_fakes.dart';

const currentFilters = {'type': 'apartment', 'purpose': 'rent', 'search': 'صنعاء', 'min_bedrooms': 3};

ProviderContainer searchContainer(Wave3VoiceFake voice, Wave3AiFake ai, Wave3PropertiesFake properties) => ProviderContainer(overrides: [
  voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai), propertyRepositoryProvider.overrideWithValue(properties),
]);

Future<GoRouter> pumpHome(WidgetTester tester, ProviderContainer container, {GlobalKey? boundary, double scale = 1, bool reducedMotion = false}) async {
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => Scaffold(body: SingleChildScrollView(child: const HomeAiSearchEntry()))),
    GoRoute(path: '/smart-search', builder: (_, __) => const AssistedSearchScreen()),
    GoRoute(path: '/other', builder: (_, __) => const Scaffold(body: Text('صفحة أخرى')))]);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(theme: AppTheme.light, routerConfig: router,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: reducedMotion),
      child: Directionality(textDirection: TextDirection.rtl, child: RepaintBoundary(key: boundary, child: child!))))));
  await tester.pumpAndSettle(); return router;
}

Future<void> preview(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('build/broker-preview/$name.png'); await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('home listens inline and applies only final budget to existing rental session without navigation', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    final container = searchContainer(voice, ai, properties); addTearDown(container.dispose); addTearDown(voice.dispose);
    final session = container.read(smartSearchSessionProvider.notifier); session.replaceManually(SmartSearchFilters.fromMap(currentFilters));
    ai.onRefine = (text, filters, revision) async => {'revision': revision, 'filters': {...filters, 'min_price': 50000, 'max_price': 100000}};
    final boundary = GlobalKey(); final router = await pumpHome(tester, container, boundary: boundary);
    await tester.tap(find.byKey(const ValueKey('home-ai-voice'))); await tester.pump();
    expect(find.text('نجهّز الميكروفون…'), findsOneWidget);
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('level', level: .8));
    voice.latest.emit(const VoiceEvent('partial', text: 'خلي السعر من خمسين'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('نستمع إليك الآن'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('home-smart-search')), matching: find.byKey(const ValueKey('voice-transcript'))), findsOneWidget);
    expect(find.text('خلي السعر من خمسين'), findsOneWidget); expect(find.byKey(const ValueKey('voice-wave')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing); expect(ai.requests, isEmpty);
    expect(session.state.filters.values, currentFilters);
    await preview(tester, boundary, 'voice-home-listening');
    voice.latest.emit(const VoiceEvent('processing')); await tester.pump(); expect(find.text('نجهّز النص…'), findsOneWidget);
    voice.latest.emit(const VoiceEvent('final', text: 'خلي السعر من خمسين إلى مئة ألف')); await tester.pumpAndSettle();
    expect(ai.requests.single.filters, currentFilters);
    expect(session.state.filters.values, {...currentFilters, 'min_price': 50000, 'max_price': 100000});
    expect(properties.queries.last.filters['min_monthly_rent'], 50000); expect(properties.queries.last.filters['max_monthly_rent'], 100000);
    expect(find.byKey(const ValueKey('home-smart-chip-budget')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-ai-result-11')), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
    voice.latest.emit(const VoiceEvent('final', text: 'طلب مكرر')); await tester.pump(); expect(ai.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel discards partial and late final, restores draft and keeps previous filters', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    final session = container.read(smartSearchSessionProvider.notifier); session.replaceManually(SmartSearchFilters.fromMap(currentFilters));
    await pumpHome(tester, container); await tester.enterText(find.byKey(const ValueKey('home-ai-description')), 'مسودة مكتوبة');
    await tester.tap(find.byKey(const ValueKey('home-ai-voice'))); await tester.pump();
    final old = voice.latest; old.emit(const VoiceEvent('ready')); old.emit(const VoiceEvent('partial', text: 'غير المكان')); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
    old.emit(const VoiceEvent('final', text: 'غير المكان')); await tester.pump();
    expect(old.cancellations, 1); expect(ai.requests, isEmpty); expect(session.state.filters.values, currentFilters);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('home-ai-description'))).controller!.text, 'مسودة مكتوبة');
    await tester.tap(find.byKey(const ValueKey('home-ai-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); old.emit(const VoiceEvent('final', text: 'قديم')); await tester.pump();
    expect(find.text('قديم'), findsNothing); await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual revision cancels capture and a late transcript cannot replace it', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    await pumpHome(tester, container); await tester.tap(find.byKey(const ValueKey('home-ai-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    final session = container.read(smartSearchSessionProvider.notifier);
    session.replaceManually(SmartSearchFilters.fromMap({'type': 'land', 'search': 'تعز'})); await tester.pumpAndSettle();
    voice.latest.emit(const VoiceEvent('final', text: 'شقة في صنعاء')); await tester.pump();
    expect(voice.latest.cancellations, 1); expect(ai.requests, isEmpty);
    expect(session.state.filters.values, {'type': 'land', 'search': 'تعز'}); expect(tester.takeException(), isNull);
  });

  testWidgets('leaving home cancels microphone and never submits a delayed final', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    final router = await pumpHome(tester, container); await tester.tap(find.byKey(const ValueKey('home-ai-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump(); router.push('/other'); await tester.pumpAndSettle();
    expect(voice.latest.cancellations, 1); voice.latest.emit(const VoiceEvent('final', text: 'شقة')); await tester.pump();
    expect(ai.requests, isEmpty); expect(router.routeInformationProvider.value.uri.path, '/other'); expect(tester.takeException(), isNull);
  });

  for (final code in ['SPEECH_PERMISSION', 'SPEECH_NO_MATCH', 'SPEECH_NETWORK', 'SPEECH_UNAVAILABLE']) {
    testWidgets('$code returns to editable home search without executing or clearing context', (tester) async {
      final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
      final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
      final session = container.read(smartSearchSessionProvider.notifier); session.replaceManually(SmartSearchFilters.fromMap(currentFilters));
      final router = await pumpHome(tester, container); await tester.tap(find.byKey(const ValueKey('home-ai-voice'))); await tester.pump();
      voice.latest.emit(VoiceEvent('error', code: code)); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inline-voice-capture')), findsNothing); expect(find.byKey(const ValueKey('home-ai-description')), findsOneWidget);
      expect(ai.requests, isEmpty); expect(session.state.filters.values, currentFilters);
      expect(router.routeInformationProvider.value.uri.path, '/'); expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow RTL listening supports large text and reduced motion', (tester) async {
    tester.view.physicalSize = const Size(320, 1000); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    final boundary = GlobalKey(); await pumpHome(tester, container, boundary: boundary, scale: 1.8, reducedMotion: true);
    await tester.tap(find.byKey(const ValueKey('home-ai-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('partial', text: 'شقة للإيجار في صنعاء، ثلاث غرف، السعر من خمسين إلى مئة ألف'));
    await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
    await preview(tester, boundary, 'voice-home-large-text');
    await tester.ensureVisible(find.byKey(const ValueKey('voice-cancel'))); await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
    expect(voice.latest.cancellations, 1); expect(ai.requests, isEmpty);
  });

  testWidgets('explicit new search cancels voice before resetting the shared session', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    final session = container.read(smartSearchSessionProvider.notifier); session.replaceManually(SmartSearchFilters.fromMap(currentFilters));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: AppTheme.light, home: const AssistedSearchScreen())));
    await tester.pumpAndSettle(); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('smart-search-reset'))); await tester.pumpAndSettle();
    voice.latest.emit(const VoiceEvent('final', text: 'قديم')); await tester.pump();
    expect(voice.latest.cancellations, 1); expect(session.state.filters.values, isEmpty); expect(ai.requests, isEmpty); expect(tester.takeException(), isNull);
  });

  testWidgets('native bridge uses start events and ignores another or cancelled recording ID', (tester) async {
    const channel = MethodChannel('real_estate/speech'); final commands = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { commands.add(call); return null; });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final capture = VoiceCaptureController(SystemVoiceInput()); addTearDown(capture.dispose);
    final completion = capture.start(); await tester.pump(); final id = (commands.single.arguments as Map)['id'] as int;
    Future<void> event(int eventId, String type, {String text = ''}) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('event', {'id': eventId, 'type': type, 'text': text})), null);
      await tester.pump();
    }
    await event(id, 'ready'); expect(capture.phase, VoicePhase.listening);
    await event(id + 1, 'final', text: 'خاطئ'); expect(capture.active, true);
    await event(id, 'partial', text: 'سعر أقل'); expect(capture.transcript, 'سعر أقل');
    capture.stop(); await tester.pump(); expect(commands.last.method, 'stop');
    capture.cancel(); await tester.pump(); expect(await completion, isNull); expect(commands.last.method, 'cancel');
    await event(id, 'final', text: 'متأخر'); expect(capture.transcript, isEmpty);
    final next = capture.start(); await tester.pump(); final nextId = (commands.last.arguments as Map)['id'] as int;
    await event(id, 'final', text: 'قديم'); expect(capture.active, true);
    await event(nextId, 'final', text: 'السعر مئة ألف'); expect(await next, 'السعر مئة ألف');
    expect(commands.map((call) => call.method), ['start', 'stop', 'cancel', 'start']);
  });

  testWidgets('backgrounding and watchdog stop listening without a partial AI submission', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false); addTearDown(voice.dispose);
    final capture = VoiceCaptureController(voice); addTearDown(capture.dispose);
    final first = capture.start(); voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    voice.latest.emit(const VoiceEvent('partial', text: 'شقة')); await tester.pump();
    capture.didChangeAppLifecycleState(AppLifecycleState.paused); await tester.pump(); expect(await first, isNull); expect(voice.latest.cancellations, 1);
    final second = capture.start(); voice.latest.emit(const VoiceEvent('ready')); await tester.pump(const Duration(seconds: 46));
    expect(await second, isNull); expect(voice.latest.cancellations, 1); expect(capture.error, contains('انتهى وقت'));
  });
}
