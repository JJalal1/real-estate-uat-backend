import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_entry_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot;

// These frames record real Widget interactions with explicitly synthetic
// ASR, API and map fixtures. They never claim physical microphone/provider QA.
void main() {
  setUpAll(loadUxFixtures);
  testWidgets('Wave01 synthetic video records final-only voice, independent sheet drag and stable saved recovery', (tester) async {
    final originalShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = originalShadows);
    var frame = 0;
    final chapters = <String, int>{};
    var boundary = GlobalKey();
    Future<void> capture([int count = 1]) async {
      for (var index = 0; index < count; index++) {
        await tester.pump(const Duration(milliseconds: 100));
        final surface = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final current = frame++;
        await tester.runAsync(() async {
          final picture = await surface.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/wave01-video/frame-${current.toString().padLeft(4, '0')}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List()); picture.dispose();
        });
      }
    }
    Future<void> tap(String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target); await tester.tap(target); await tester.pump();
    }
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    addTearDown(voice.dispose);
    ai.onRefine = (_, __, revision) async => {'revision': revision,
      'filters': {'type': 'apartment', 'purpose': 'rent', 'search': 'صنعاء', 'max_price': 150000}, 'message': 'شروط الاختبار الاصطناعية'};
    final scope = uxContainer(extra: [voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai),
      propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, select, viewport) => const ColoredBox(
        color: Color(0xffdceae3), child: Center(child: Text('خريطة اصطناعية لاختبار الواجهة')))),
    ]);
    await pumpUx(tester, scope, const AssistedSearchScreen(), boundary: boundary);
    chapters['typed_context'] = frame;
    await tester.enterText(find.byKey(const ValueKey('smart-search-description')), 'أريد');
    await capture(8);
    await tap('smart-search-voice');
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation')); voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('speech_start'));
    chapters['live_partial'] = frame;
    voice.latest.emit(const VoiceEvent('partial', text: 'شقة للإيجار')); await capture(6);
    voice.latest.emit(const VoiceEvent('partial', text: 'شقة للإيجار في صنعاء')); await capture(8);
    expect(ai.requests, isEmpty);
    voice.latest.emit(const VoiceEvent('segment', text: 'شقة للإيجار في صنعاء'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    chapters['natural_silence_waits_for_final'] = frame;
    await capture(27);
    expect(voice.latest.stops, 1); expect(ai.requests, isEmpty);
    voice.latest.emit(const VoiceEvent('final', text: 'شقة للإيجار في صنعاء'));
    await tester.pumpAndSettle();
    expect(ai.requests.single.message, 'أريد شقة للإيجار في صنعاء');
    expect(properties.queries, hasLength(1));
    chapters['one_automatic_search'] = frame;
    await capture(10);
    await tap('floating-map-search'); await tester.pumpAndSettle();
    chapters['map_panel'] = frame;
    await capture(8);
    await tap('map-filter-panel-toggle'); await tester.pumpAndSettle();
    chapters['collapsed_panel'] = frame;
    await capture(8);
    final start = tester.getCenter(find.byKey(const ValueKey('map-results-handle')));
    final gesture = await tester.startGesture(start);
    chapters['handle_drag'] = frame;
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(start - Offset(0, step * 17)); await capture();
    }
    await gesture.up(); await tester.pumpAndSettle(); await capture(6);
    await closeUx(tester);

    final key = newListingDraftKey(), drafts = Wave6Drafts();
    drafts.drafts[key] = ListingAccountDraft(key: key, revision: 1, title: 'مسودة محفوظة للاختبار', progress: 60,
      payload: {...editorSnapshot(), 'editor_version': 10, 'draft_key': key, 'draft_kind': 'saved', 'entry_method': 'manual'});
    final draftScope = uxContainer(user: uxUser(type: 'broker'), extra: [listingAccountDraftRepositoryProvider.overrideWithValue(drafts),
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()), aiRepositoryProvider.overrideWithValue(Wave6Ai())]);
    boundary = GlobalKey();
    await pumpUx(tester, draftScope, const ListingDraftEntryScreen(), boundary: boundary); await tester.pumpAndSettle();
    chapters['stable_saved_choice'] = frame;
    await capture(10); await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(const ValueKey('listing-recovery-choice')), findsOneWidget);
    await capture(5); await tap('listing-recovery-resume'); await tester.pumpAndSettle();
    expect(find.byType(ListingEditorScreen), findsOneWidget);
    chapters['resume_same_work'] = frame;
    await capture(8);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async => File('build/wave01-video/proof.json').writeAsString(jsonEncode({
      'source_commit': Platform.environment['GITHUB_SHA'], 'kind': 'synthetic_widget_interactions', 'fps': 5,
      'frames': frame, 'chapters': chapters, 'voice_searches': ai.requests.length,
      'actual_device_asr_map_or_ai_provider': false,
    })));
    await closeUx(tester);
  });
}
