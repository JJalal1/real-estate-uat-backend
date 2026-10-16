import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
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
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/account/presentation/account_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/rental_conditions_editor.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'support/wave3_fakes.dart';

const currentFilters = {'type': 'apartment', 'purpose': 'rent', 'search': 'صنعاء', 'min_bedrooms': 3};

class _AnonymousAuth extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}

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
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsNothing);
  expect(find.text('بحث ذكي'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('home-smart-search')));
  await tester.pumpAndSettle();
  return router;
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
  setUpAll(() async {
    for (final name in ['sans-serif', 'NotoSansArabic']) {
      await (FontLoader(name)..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))).load();
    }
    final primary = FontLoader('PrimaryFont');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) { primary.addFont(rootBundle.load('assets/ebroker/fonts/Manrope-$weight.ttf')); }
    await primary.load();
    final root = Platform.environment['FLUTTER_ROOT']!;
    final icons = await File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });
  testWidgets('lightweight home opens the existing search and final voice edits retain the rental context', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    final container = searchContainer(voice, ai, properties); addTearDown(container.dispose); addTearDown(voice.dispose);
    final session = container.read(smartSearchSessionProvider.notifier); session.replaceManually(SmartSearchFilters.fromMap(currentFilters));
    ai.onRefine = (text, filters, revision) async => {'revision': revision, 'filters': {...filters, 'min_price': 50000, 'max_price': 100000}};
    final boundary = GlobalKey(); final router = await pumpHome(tester, container, boundary: boundary);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    expect(find.text('نجهّز الميكروفون…'), findsOneWidget);
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('level', level: .8));
    voice.latest.emit(const VoiceEvent('partial', text: 'خلي السعر من خمسين'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('نستمع إليك الآن'), findsOneWidget);
    expect(find.descendant(of: find.byType(AssistedSearchScreen), matching: find.byKey(const ValueKey('voice-transcript'))), findsOneWidget);
    expect(find.text('خلي السعر من خمسين'), findsNothing); expect(voice.latest.stops, 0); expect(find.byKey(const ValueKey('voice-wave')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing); expect(ai.requests, isEmpty);
    expect(session.state.filters.values, currentFilters);
    await preview(tester, boundary, 'voice-home-listening');
    await tester.tap(find.byKey(const ValueKey('voice-finish'))); await tester.pump();
    expect(voice.latest.stops, 1); expect(find.text('نفرّغ التسجيل كاملًا…'), findsOneWidget);
    voice.latest.emit(const VoiceEvent('final', text: 'خلي السعر من خمسين إلى مئة ألف')); await tester.pumpAndSettle();
    expect(ai.requests.single.filters, currentFilters);
    expect(session.state.filters.values, {...currentFilters, 'min_price': 50000, 'max_price': 100000});
    expect(properties.queries.last.filters['min_monthly_rent'], 50000); expect(properties.queries.last.filters['max_monthly_rent'], 100000);
    expect(find.byKey(const ValueKey('smart-chip-budget')), findsOneWidget);
    expect(find.byKey(const ValueKey('smart-search-result-11')), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/smart-search');
    expect(find.byType(AssistedSearchScreen), findsOneWidget);
    voice.latest.emit(const VoiceEvent('final', text: 'طلب مكرر')); await tester.pump(); expect(ai.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('budget chip edits only budget and manual chip removal keeps the same search session', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    final container = searchContainer(voice, ai, properties); addTearDown(container.dispose); addTearDown(voice.dispose);
    final session = container.read(smartSearchSessionProvider.notifier);
    session.replaceManually(SmartSearchFilters.fromMap({...currentFilters, 'min_price': 50000, 'max_price': 100000}));
    await pumpHome(tester, container);
    await tester.tap(find.byKey(const ValueKey('smart-chip-budget'))); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-search')), findsNothing);
    expect(find.byKey(const ValueKey('filter-min_bedrooms')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('filter-max_price')), '١٢٠٠٠٠');
    await tester.ensureVisible(find.text('تطبيق الشروط')); await tester.tap(find.text('تطبيق الشروط')); await tester.pumpAndSettle();
    expect(session.state.filters.values, {...currentFilters, 'min_price': 50000, 'max_price': 120000.0});
    final rooms = tester.widget<InputChip>(find.byKey(const ValueKey('smart-chip-min_bedrooms')));
    rooms.onDeleted!(); await tester.pumpAndSettle();
    expect(session.state.filters.values['search'], 'صنعاء');
    expect(session.state.filters.values['purpose'], 'rent');
    expect(session.state.filters.values['type'], 'apartment');
    expect(session.state.filters.values['max_price'], 120000);
    expect(session.state.filters.values.containsKey('min_bedrooms'), isFalse);
    expect(properties.queries.last.filters['max_monthly_rent'], 120000);
    expect(ai.requests, isEmpty); expect(tester.takeException(), isNull);
  });

  testWidgets('cancel discards partial and late final, restores draft and keeps previous filters', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    final session = container.read(smartSearchSessionProvider.notifier); session.replaceManually(SmartSearchFilters.fromMap(currentFilters));
    await pumpHome(tester, container); await tester.enterText(find.byKey(const ValueKey('smart-search-description')), 'مسودة مكتوبة');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    final old = voice.latest; old.emit(const VoiceEvent('ready')); old.emit(const VoiceEvent('partial', text: 'غير المكان')); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
    old.emit(const VoiceEvent('final', text: 'غير المكان')); await tester.pump();
    expect(old.cancellations, 1); expect(ai.requests, isEmpty); expect(session.state.filters.values, currentFilters);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('smart-search-description'))).controller!.text, 'مسودة مكتوبة');
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); old.emit(const VoiceEvent('final', text: 'قديم')); await tester.pump();
    expect(find.text('قديم'), findsNothing); await tester.tap(find.byKey(const ValueKey('voice-cancel'))); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual revision cancels capture and a late transcript cannot replace it', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    await pumpHome(tester, container); await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    final session = container.read(smartSearchSessionProvider.notifier);
    session.replaceManually(SmartSearchFilters.fromMap({'type': 'land', 'search': 'تعز'})); await tester.pumpAndSettle();
    voice.latest.emit(const VoiceEvent('final', text: 'شقة في صنعاء')); await tester.pump();
    expect(voice.latest.cancellations, 1); expect(ai.requests, isEmpty);
    expect(session.state.filters.values, {'type': 'land', 'search': 'تعز'}); expect(tester.takeException(), isNull);
  });

  testWidgets('leaving smart search cancels microphone and never submits a delayed final', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    final router = await pumpHome(tester, container); await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump(); router.push('/other'); await tester.pumpAndSettle();
    expect(voice.latest.cancellations, 1); voice.latest.emit(const VoiceEvent('final', text: 'شقة')); await tester.pump();
    expect(ai.requests, isEmpty); expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/other');
    expect(find.text('صفحة أخرى'), findsOneWidget); expect(find.byKey(const ValueKey('smart-search-voice')).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final code in ['SPEECH_PERMISSION', 'SPEECH_NO_MATCH', 'SPEECH_NETWORK', 'SPEECH_UNAVAILABLE']) {
    testWidgets('$code returns to editable smart search without executing or clearing context', (tester) async {
      final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
      final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
      final session = container.read(smartSearchSessionProvider.notifier); session.replaceManually(SmartSearchFilters.fromMap(currentFilters));
      final router = await pumpHome(tester, container); await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
      voice.latest.emit(VoiceEvent('error', code: code)); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inline-voice-capture')), findsNothing); expect(find.byKey(const ValueKey('smart-search-description')), findsOneWidget);
      expect(ai.requests, isEmpty); expect(session.state.filters.values, currentFilters);
      expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/smart-search'); expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow RTL listening supports large text and reduced motion', (tester) async {
    tester.view.physicalSize = const Size(320, 1000); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake();
    final container = searchContainer(voice, ai, Wave3PropertiesFake()); addTearDown(container.dispose); addTearDown(voice.dispose);
    final boundary = GlobalKey(); await pumpHome(tester, container, boundary: boundary, scale: 1.8, reducedMotion: true);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
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
    await tester.pumpAndSettle(); await tester.ensureVisible(find.byKey(const ValueKey('smart-search-voice'))); await tester.tap(find.byKey(const ValueKey('smart-search-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('smart-search-reset'))); await tester.pumpAndSettle();
    voice.latest.emit(const VoiceEvent('final', text: 'قديم')); await tester.pump();
    expect(voice.latest.cancellations, 1); expect(session.state.filters.values, isEmpty); expect(ai.requests, isEmpty); expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets('lightweight home and account reopen one search session at scale $scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final voice = Wave3VoiceFake(), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
      addTearDown(voice.dispose);
      final feed = Wave3MarketplaceFake(onFeed: (q) async => MarketplaceFeed(label: 'صنعاء',
        governorate: 'صنعاء', sections: {'latest': [wave3Property(11)]}));
      final boundary = GlobalKey();
      final container = ProviderContainer(overrides: [
        voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai),
        propertyRepositoryProvider.overrideWithValue(properties), marketplaceRepositoryProvider.overrideWithValue(feed),
        homeLocationAttemptedProvider.overrideWith((_) => true),
        authControllerProvider.overrideWith(_AnonymousAuth.new),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const MarketplaceHomeScreen()),
        GoRoute(path: '/smart-search', builder: (_, __) => const AssistedSearchScreen()),
        GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: TextDirection.rtl, child: RepaintBoundary(key: boundary, child: child!))))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-ai-description')), findsNothing);
      expect(find.byKey(const ValueKey('home-ai-voice')), findsNothing);
      expect(find.text('بحث ذكي'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('home-smart-search'))).height, lessThan(100));
      await preview(tester, boundary, scale == 1 ? 'wave5-home' : 'wave5-home-large');
      await tester.tap(find.byKey(const ValueKey('home-smart-search'))); await tester.pumpAndSettle();
      expect(find.byType(AssistedSearchScreen), findsOneWidget);
      final filters = {...currentFilters, 'max_price': 125000};
      container.read(smartSearchSessionProvider.notifier).replaceManually(SmartSearchFilters.fromMap(filters));
      await tester.pumpAndSettle();
      router.pop(); await tester.pumpAndSettle();
      router.push('/account'); await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('account-smart-search')));
      await tester.tap(find.byKey(const ValueKey('account-smart-search'))); await tester.pumpAndSettle();
      expect(find.byType(AssistedSearchScreen), findsOneWidget);
      expect(container.read(smartSearchSessionProvider).filters.values, filters);
      expect(ai.requests, isEmpty); expect(voice.calls, 0); expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selected rental condition chips render inline with real Arabic fonts', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    var value = <Map<String, dynamic>>[
      {'kind': 'advance', 'months': 2}, {'kind': 'guarantor'}, {'kind': 'deposit'},
      {'kind': 'duration', 'months': 12}, {'kind': 'special', 'text': 'المحافظة على نظافة العقار'},
    ];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Directionality(textDirection: TextDirection.rtl,
      child: RepaintBoundary(key: boundary, child: Scaffold(appBar: AppBar(title: const Text('شروط الإيجار')),
        body: StatefulBuilder(builder: (context, update) => ListView(padding: const EdgeInsets.all(18), children: [
          RentalConditionsEditor(value: value, onChanged: (next) => update(() => value = next)),
        ])))))));
    await tester.pumpAndSettle();
    expect(find.byType(FilterChip), findsNWidgets(5));
    expect(find.byType(CheckboxListTile), findsNothing);
    await preview(tester, boundary, 'wave5-rental-conditions');
    expect(tester.takeException(), isNull);
  });

  testWidgets('native bridge transcribes one complete clip only after manual stop, isolates IDs and cancels upload', (tester) async {
    const channel = MethodChannel('real_estate/speech'); final commands = <MethodCall>[];
    final transcriptions = <Completer<String>>[], tokens = <CancelToken>[], paths = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { commands.add(call); return null; });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final capture = VoiceCaptureController(SystemVoiceInput(transcribe: (path, token) {
      paths.add(path); tokens.add(token); final next = Completer<String>(); transcriptions.add(next); return next.future;
    }));
    addTearDown(capture.dispose);
    Future<void> event(int id, String type, {String path = ''}) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('event', {'id': id, 'type': type, 'path': path})), null);
      await tester.pump();
    }
    final first = capture.start(); await tester.pump(); final id = (commands.last.arguments as Map)['id'] as int;
    await event(id, 'ready');
    await event(id, 'recorded', path: 'premature'); expect(paths, isEmpty);
    capture.stop(); capture.stop(); await tester.pump();
    expect(commands.where((c) => c.method == 'stop'), hasLength(1));
    await event(id + 1, 'recorded', path: 'wrong-id'); expect(paths, isEmpty);
    await event(id, 'recorded', path: 'whole-first.m4a');
    await event(id, 'recorded', path: 'duplicate'); expect(paths, ['whole-first.m4a']);
    capture.cancel(); await tester.pump(); expect(await first, isNull); expect(tokens.single.isCancelled, true);
    transcriptions.first.complete('نتيجة متأخرة'); await tester.pump(); expect(capture.transcript, isEmpty);
    final next = capture.start(); await tester.pump(); final nextId = (commands.last.arguments as Map)['id'] as int;
    await event(nextId, 'ready'); capture.stop(); await tester.pump();
    await event(id, 'recorded', path: 'old'); expect(paths, hasLength(1));
    await event(nextId, 'recorded', path: 'whole-second.m4a');
    transcriptions.last.complete('خلي السعر من خمسين إلى مئة ألف بعد هذا التوقف'); await tester.pump();
    expect(await next, 'خلي السعر من خمسين إلى مئة ألف بعد هذا التوقف');
    expect(paths, ['whole-first.m4a', 'whole-second.m4a']);
    expect(commands.last.method, 'release');
  });

  testWidgets('silence beyond old watchdog keeps listening; background cancels and only post-stop processing expires', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false); addTearDown(voice.dispose);
    final capture = VoiceCaptureController(voice); addTearDown(capture.dispose);
    final first = capture.start(); voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    voice.latest.emit(const VoiceEvent('partial', text: 'جزء ناقص')); await tester.pump();
    await tester.pump(const Duration(minutes: 2)); expect(capture.phase, VoicePhase.listening);
    expect(capture.transcript, isEmpty); expect(voice.latest.stops, 0);
    capture.didChangeAppLifecycleState(AppLifecycleState.paused); await tester.pump();
    expect(await first, isNull); expect(voice.latest.cancellations, 1);
    final second = capture.start(); voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    capture.stop(); await tester.pump(const Duration(minutes: 3, seconds: 1));
    expect(await second, isNull); expect(voice.latest.cancellations, 1); expect(capture.error, contains('لم نغير بحثك'));
  });
}
