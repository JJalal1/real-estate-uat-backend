import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_query_summary.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

import 'in_app_voice_search_test.dart' show pumpHome, preview, searchContainer;
import 'support/wave3_fakes.dart';

const _input = ValueKey('smart-search-description');
const _send = ValueKey('smart-search-send');
const _voice = ValueKey('smart-search-voice');

String _draft(WidgetTester tester) => tester.widget<TextField>(find.byKey(_input)).controller!.text;

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.byKey(_input));
  await tester.enterText(find.byKey(_input), text);
  await tester.ensureVisible(find.byKey(_send));
  await tester.tap(find.byKey(_send));
  await tester.pumpAndSettle();
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
    final icons = await File('${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.buffer.asByteData()))).load();
  });

  test('accepted criteria consume only their draft before result retrieval completes', () async {
    final rows = Completer<void>();
    final ai = Wave3AiFake();
    final properties = Wave3PropertiesFake()..onSearch = (_, __) async {
      await rows.future;
      return ([wave3Property(11)], false);
    };
    final session = SmartSearchSession(ai, properties);
    addTearDown(session.dispose);
    session.setDraftText('شقة في صنعاء');
    final pending = session.interpret('شقة في صنعاء');
    await Future<void>.delayed(Duration.zero);
    expect(session.state.draftText, isEmpty);
    expect(session.state.lastRequest, 'شقة في صنعاء');
    expect(session.state.filters.values['search'], 'صنعاء');
    expect(session.state.loading, isTrue);
    rows.complete();
    await pending;
    expect(session.state.rows.single.id, 11);
  });

  test('a response cannot consume a newer unsent draft', () async {
    final response = Completer<Map<String, dynamic>>();
    final ai = Wave3AiFake()..onRefine = (_, __, ___) => response.future;
    final session = SmartSearchSession(ai, Wave3PropertiesFake());
    addTearDown(session.dispose);
    session.setDraftText('عقارات في إب');
    final pending = session.interpret('عقارات في إب');
    session.setDraftText('السعر أكثر من مئة مليون');
    response.complete({'revision': ai.requests.single.revision, 'filters': {'search': 'إب'}});
    await pending;
    expect(session.state.draftText, 'السعر أكثر من مئة مليون');
    expect(session.state.filters.values, {'search': 'إب'});
  });

  test('manual revisions invalidate pending interpretation without consuming a draft', () async {
    final response = Completer<Map<String, dynamic>>();
    final ai = Wave3AiFake()..onRefine = (_, __, ___) => response.future;
    final session = SmartSearchSession(ai, Wave3PropertiesFake());
    addTearDown(session.dispose);
    session.setDraftText('عقارات في إب');
    final pending = session.interpret('عقارات في إب');
    session.replaceManually(SmartSearchFilters.fromMap({'search': 'ذمار'}));
    response.complete({'revision': ai.requests.single.revision, 'filters': {'search': 'إب'}});
    await pending;
    expect(session.state.draftText, 'عقارات في إب');
    expect(session.state.filters.values, {'search': 'ذمار'});
  });

  testWidgets('Ibb search then voice price becomes criteria and arbitrary typed followups remain open', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    final container = searchContainer(voice, ai, properties);
    addTearDown(container.dispose);
    addTearDown(voice.dispose);
    ai.onRefine = (text, filters, revision) async => {
      'revision': revision,
      'filters': {
        ...filters,
        if (text == 'ابحث لي عن عقارات في إب') 'search': 'إب',
        if (text == 'السعر أكثر من ١٠٠ مليون') ...{'min_price': 100000000, 'currency': 'YER'},
        if (text == 'خلها أرض للبيع') ...{'type': 'land', 'purpose': 'sale'},
        if (text == 'بدّل الموقع إلى ذمار') 'search': 'ذمار',
      },
    };
    final router = await pumpHome(tester, container);
    final session = container.read(smartSearchSessionProvider.notifier);
    await _submit(tester, 'ابحث لي عن عقارات في إب');
    expect(_draft(tester), isEmpty);
    expect(session.state.draftText, isEmpty);
    expect(find.byKey(const ValueKey('smart-search-query-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('smart-chip-search')), findsOneWidget);
    expect(find.text('إب'), findsOneWidget);

    await tester.ensureVisible(find.byKey(_voice));
    await tester.tap(find.byKey(_voice));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'السعر أكثر من'));
    await tester.pump();
    expect(_draft(tester), 'السعر أكثر من');
    expect(ai.requests, hasLength(1));
    expect(session.state.filters.values, {'search': 'إب'});
    await tester.ensureVisible(find.byKey(const ValueKey('voice-finish')));
    await tester.tap(find.byKey(const ValueKey('voice-finish')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('final', text: 'السعر أكثر من ١٠٠ مليون'));
    await tester.pumpAndSettle();
    expect(_draft(tester), 'السعر أكثر من ١٠٠ مليون');
    expect(ai.requests, hasLength(1));
    await tester.ensureVisible(find.byKey(_send));
    await tester.tap(find.byKey(_send));
    await tester.pumpAndSettle();
    expect(ai.requests.last.message, 'السعر أكثر من ١٠٠ مليون');
    expect(ai.requests.last.filters, {'search': 'إب'});
    expect(session.state.filters.values, {'search': 'إب', 'min_price': 100000000, 'currency': 'YER'});
    expect(_draft(tester), isEmpty);
    expect(find.text('من 100 مليون ريال يمني'), findsOneWidget);
    expect(properties.queries.last.filters['min_price'], 100000000);

    await _submit(tester, 'خلها أرض للبيع');
    expect(ai.requests.last.message, 'خلها أرض للبيع');
    expect(session.state.filters.values['type'], 'land');
    expect(session.state.filters.values['search'], 'إب');
    expect(session.state.filters.values['min_price'], 100000000);
    await _submit(tester, 'بدّل الموقع إلى ذمار');
    expect(session.state.filters.values['search'], 'ذمار');
    expect(session.state.filters.values['min_price'], 100000000);
    expect(ai.requests, hasLength(4));
    expect(_draft(tester), isEmpty);
    expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/smart-search');
    expect(find.byType(AssistedSearchScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable interpretation keeps the new request and accepted criteria without retries', (tester) async {
    final voice = Wave3VoiceFake(), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    final container = searchContainer(voice, ai, properties);
    addTearDown(container.dispose);
    addTearDown(voice.dispose);
    await pumpHome(tester, container);
    await _submit(tester, 'شقة في صنعاء');
    final previous = container.read(smartSearchSessionProvider).filters.values;
    ai.onRefine = (_, __, ___) async => throw StateError('unavailable');
    await _submit(tester, 'السعر أكثر من مئة مليون');
    expect(_draft(tester), 'السعر أكثر من مئة مليون');
    expect(container.read(smartSearchSessionProvider).filters.values, previous);
    expect(container.read(smartSearchSessionProvider).aiError, isNotNull);
    await tester.pump(const Duration(seconds: 20));
    expect(ai.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending interpretation displays progress without inventing accepted filters', (tester) async {
    final voice = Wave3VoiceFake(), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    final response = Completer<Map<String, dynamic>>();
    ai.onRefine = (_, __, ___) => response.future;
    final container = searchContainer(voice, ai, properties);
    addTearDown(container.dispose);
    addTearDown(voice.dispose);
    await pumpHome(tester, container);
    await tester.enterText(find.byKey(_input), 'عقارات في إب');
    await tester.ensureVisible(find.byKey(_send));
    await tester.tap(find.byKey(_send));
    await tester.pump();
    expect(find.byKey(const ValueKey('smart-search-query-pending')), findsOneWidget);
    expect(find.byKey(const ValueKey('smart-chip-search')), findsNothing);
    expect(properties.queries, isEmpty);
    response.complete({'revision': ai.requests.single.revision, 'filters': {'search': 'إب'}});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('smart-chip-search')), findsOneWidget);
    expect(_draft(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('query criteria retain exact money, monthly meaning, currency and editable keys', (tester) async {
    final edited = <String>[], removed = <String>[];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(16),
      child: SmartSearchQuerySummary(
        filters: SmartSearchFilters.fromMap({'type': 'house', 'purpose': 'rent', 'search': 'إب',
          'max_price': 100000001.25, 'currency': 'USD', 'has_parking': false}),
        onEdit: edited.add, onRemove: removed.add,
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('حتى 100٬000٬001.25 دولار شهريًا'), findsOneWidget);
    expect(find.text('بدون موقف'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('smart-chip-edit-budget')));
    await tester.tap(find.byKey(const ValueKey('smart-chip-remove-budget')));
    expect(edited, ['budget']);
    expect(removed, ['budget']);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.4]) {
    testWidgets('query and fresh voice followup remain readable at scale $scale', (tester) async {
      tester.view.physicalSize = Size(scale == 1 ? 390 : 360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
      final container = searchContainer(voice, ai, properties);
      addTearDown(container.dispose);
      addTearDown(voice.dispose);
      ai.onRefine = (_, __, revision) async => {'revision': revision, 'filters': {
        'type': 'house', 'purpose': 'sale', 'search': 'إب', 'min_price': 100000000,
        'currency': 'YER', 'min_bedrooms': 3, 'has_parking': true,
      }};
      final boundary = GlobalKey();
      await pumpHome(tester, container, boundary: boundary, scale: scale, reducedMotion: true);
      await _submit(tester, 'منزل للبيع في إب بسعر أكثر من مئة مليون، ثلاث غرف وموقف');
      expect(_draft(tester), isEmpty);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      for (final key in ['type', 'purpose', 'search', 'budget', 'min_bedrooms', 'has_parking']) {
        final chip = tester.getRect(find.byKey(ValueKey('smart-chip-$key')));
        final label = tester.getRect(find.byKey(ValueKey('smart-chip-label-$key')));
        expect(chip.contains(label.topLeft), isTrue, reason: '$key label starts inside its criterion');
        expect(chip.contains(label.bottomRight - const Offset(.1, .1)), isTrue, reason: '$key label must not be clipped');
      }
      await preview(tester, boundary, 'search-query-summary-$scale');

      await tester.ensureVisible(find.byKey(_voice));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_voice));
      await tester.pump();
      voice.latest.emit(const VoiceEvent('ready'));
      voice.latest.emit(const VoiceEvent('partial', text: 'خلّي السعر أقل من مئتي مليون'));
      await tester.pumpAndSettle();
      expect(_draft(tester), 'خلّي السعر أقل من مئتي مليون');
      expect(ai.requests, hasLength(1));
      await tester.ensureVisible(find.byKey(_input));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-finish')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-cancel')).hitTestable(), findsOneWidget);
      await preview(tester, boundary, 'search-query-followup-$scale');
      await tester.ensureVisible(find.byKey(const ValueKey('voice-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-cancel')));
      await tester.pumpAndSettle();
      expect(_draft(tester), isEmpty);
      expect(container.read(smartSearchSessionProvider).filters.values['min_price'], 100000000);
      expect(ai.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('zero results never relax filters silently and expose explicit recovery', (tester) async {
    final voice = Wave3VoiceFake();
    final ai = Wave3AiFake()
      ..onRefine = (_, __, revision) async => {
        'revision': revision,
        'filters': {
          'search': 'حدة',
          'type': 'apartment',
          'purpose': 'sale',
          'max_price': 50000000,
          'currency': 'YER',
        },
      };
    final properties = Wave3PropertiesFake()
      ..onSearch = (_, __) async => (<PropertySummary>[], false);
    final container = searchContainer(voice, ai, properties);
    addTearDown(container.dispose);
    addTearDown(voice.dispose);

    await pumpHome(tester, container);
    await _submit(tester, 'شقة للبيع في حدة حتى خمسين مليون');

    expect(find.text('لا توجد عقارات بهذه الشروط'), findsOneWidget);
    expect(find.byKey(const ValueKey('zero-results-budget')), findsOneWidget);
    expect(find.byKey(const ValueKey('zero-results-type')), findsOneWidget);
    expect(find.byKey(const ValueKey('zero-results-search')), findsOneWidget);
    expect(container.read(smartSearchSessionProvider).filters.values['max_price'], 50000000);

    await tester.tap(find.byKey(const ValueKey('zero-results-budget')));
    await tester.pumpAndSettle();

    expect(container.read(smartSearchSessionProvider).filters.values.containsKey('max_price'), isFalse);
    expect(properties.queries.last.filters.containsKey('max_price'), isFalse);
    expect(properties.queries.last.filters['search'], 'حدة');
    expect(properties.queries.last.filters['type'], 'apartment');
    expect(tester.takeException(), isNull);
  });


}
