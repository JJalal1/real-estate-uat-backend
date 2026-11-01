import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/platform/voice_capture_controller.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, finishWave6, editorSnapshot, textField;

void main() {
  setUpAll(loadUxFixtures);
  testWidgets('D08 live dictation waits for the recognizer result before silence stop', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice);
    addTearDown(capture.dispose); addTearDown(voice.dispose);
    final result = capture.start();
    final recording = voice.latest;
    recording.emit(const VoiceEvent('mode', code: 'dictation'));
    recording.emit(const VoiceEvent('ready'));
    recording.emit(const VoiceEvent('speech_start'));
    recording.emit(const VoiceEvent('partial', text: 'شقة للإيجار'));
    recording.emit(const VoiceEvent('speech_end')); // Android onEndOfSpeech precedes onResults.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    expect(recording.stops, 0);
    expect(capture.preview, 'شقة للإيجار');
    recording.emit(const VoiceEvent('segment', text: 'شقة للإيجار'));
    recording.emit(const VoiceEvent('speech_end')); // Android onResults confirmed the segment.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2499));
    expect(recording.stops, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(recording.stops, 1);
    recording.emit(const VoiceEvent('final', text: 'شقة للإيجار'));
    await tester.pump();
    expect(await result, 'شقة للإيجار');
  });
  testWidgets('D09 a new partial after a segment cancels the old silence timer', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice);
    addTearDown(capture.dispose); addTearDown(voice.dispose);
    final result = capture.start();
    final recording = voice.latest;
    recording.emit(const VoiceEvent('mode', code: 'dictation'));
    recording.emit(const VoiceEvent('ready'));
    recording.emit(const VoiceEvent('segment', text: 'first segment'));
    recording.emit(const VoiceEvent('speech_end'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    recording.emit(const VoiceEvent('partial', text: 'first segment continuing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(recording.stops, 0);
    expect(capture.preview, 'first segment continuing');
    recording.emit(const VoiceEvent('segment', text: 'first segment continuing'));
    recording.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(milliseconds: 2500));
    expect(recording.stops, 1);
    recording.emit(const VoiceEvent('final', text: 'first segment continuing'));
    await tester.pump();
    expect(await result, 'first segment continuing');
  });
  testWidgets('D10 a missing recognizer segment fails in bounded time without a final', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice);
    addTearDown(capture.dispose); addTearDown(voice.dispose);
    final result = capture.start();
    final recording = voice.latest;
    recording.emit(const VoiceEvent('mode', code: 'dictation'));
    recording.emit(const VoiceEvent('ready'));
    recording.emit(const VoiceEvent('speech_start'));
    recording.emit(const VoiceEvent('partial', text: 'tentative words'));
    recording.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    expect(capture.phase, VoicePhase.idle);
    expect(capture.preview, 'tentative words');
    expect(capture.transcript, isEmpty);
    expect(capture.error, isNotNull);
    expect(recording.cancellations, 1);
    expect(await result, isNull);
  });
  testWidgets('D11 a new hypothesis cannot inherit the previous final-result deadline', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice);
    addTearDown(capture.dispose); addTearDown(voice.dispose);
    final result = capture.start();
    final recording = voice.latest;
    recording.emit(const VoiceEvent('mode', code: 'dictation'));
    recording.emit(const VoiceEvent('ready'));
    recording.emit(const VoiceEvent('segment', text: 'confirmed first phrase'));
    recording.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(milliseconds: 1000));
    recording.emit(const VoiceEvent('partial', text: 'confirmed first phrase and new words'));
    await tester.pump(const Duration(seconds: 12));
    expect(capture.phase, VoicePhase.listening);
    expect(recording.cancellations, 0);
    expect(recording.stops, 0);
    expect(capture.preview, 'confirmed first phrase and new words');

    recording.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    expect(capture.phase, VoicePhase.idle);
    expect(capture.transcript, isEmpty);
    expect(await result, isNull);
  });
  testWidgets('D12 late partial after speech end cannot remove the final-result deadline', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice);
    addTearDown(capture.dispose); addTearDown(voice.dispose);
    final result = capture.start();
    final recording = voice.latest;
    recording.emit(const VoiceEvent('mode', code: 'dictation'));
    recording.emit(const VoiceEvent('ready'));
    recording.emit(const VoiceEvent('speech_start'));
    recording.emit(const VoiceEvent('partial', text: 'first hypothesis'));
    recording.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 2));
    recording.emit(const VoiceEvent('partial', text: 'late hypothesis'));
    await tester.pump(const Duration(seconds: 10));
    expect(capture.phase, VoicePhase.idle);
    expect(capture.preview, 'late hypothesis');
    expect(capture.transcript, isEmpty);
    expect(recording.cancellations, 1);
    expect(await result, isNull);
  });
  testWidgets('D12 a late event from a canceled generation cannot postpone the next result deadline', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice);
    addTearDown(capture.dispose); addTearDown(voice.dispose);
    final oldResult = capture.start(), old = voice.latest;
    old.emit(const VoiceEvent('mode', code: 'dictation'));
    old.emit(const VoiceEvent('ready'));
    old.emit(const VoiceEvent('speech_start'));
    old.emit(const VoiceEvent('speech_end'));
    await tester.pump();
    capture.cancel();
    final currentResult = capture.start(), current = voice.latest;
    current.emit(const VoiceEvent('mode', code: 'dictation'));
    current.emit(const VoiceEvent('ready'));
    current.emit(const VoiceEvent('speech_start'));
    current.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 2));
    old.emit(const VoiceEvent('partial', text: 'stale'));
    await tester.pump(const Duration(seconds: 10));
    expect(await oldResult, isNull);
    expect(await currentResult, isNull);
    expect(capture.phase, VoicePhase.idle);
    expect(current.cancellations, 1);
    expect(capture.preview, isEmpty);
  });
  testWidgets('D02 D03 short pauses survive and VAD silence stops once before a reliable final', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final controller = VoiceCaptureController(voice);
    addTearDown(controller.dispose); addTearDown(voice.dispose);
    final result = controller.start();
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('speech_start'));
    voice.latest.emit(const VoiceEvent('partial', text: 'أربع غرف'));
    voice.latest.emit(const VoiceEvent('speech_end')); await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500)); expect(voice.latest.stops, 0);
    voice.latest.emit(const VoiceEvent('speech_start')); await tester.pump();
    voice.latest.emit(const VoiceEvent('segment', text: 'أربع غرف وحمامين'));
    voice.latest.emit(const VoiceEvent('speech_end')); await tester.pump();
    await tester.pump(const Duration(milliseconds: 2499)); expect(voice.latest.stops, 0);
    await tester.pump(const Duration(milliseconds: 1)); expect(voice.latest.stops, 1);
    expect(controller.phase, VoicePhase.processing); expect(controller.transcript, isEmpty);
    voice.latest.emit(const VoiceEvent('final', text: 'أربع غرف وحمامين')); await tester.pump();
    expect(await result, 'أربع غرف وحمامين'); expect(controller.phase, VoicePhase.idle);
    await tester.pump(const Duration(seconds: 5)); expect(voice.latest.stops, 1);
  });
  testWidgets('D02 no partial-only watchdog treats a hypothesis as a final', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final controller = VoiceCaptureController(voice); addTearDown(controller.dispose); addTearDown(voice.dispose);
    final result = controller.start(); voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'مئة ألف')); await tester.pump(const Duration(seconds: 4));
    expect(voice.latest.stops, 0); expect(controller.transcript, isEmpty);
    controller.cancel(); await tester.pump(); expect(await result, isNull);
  });
  testWidgets('D03 silence without any speech cancels without returning a search query', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice); addTearDown(capture.dispose); addTearDown(voice.dispose);
    final result = capture.start(); voice.latest.emit(const VoiceEvent('ready')); await tester.pump();
    await tester.pump(const Duration(seconds: 15)); expect(await result, isNull);
    expect(voice.latest.cancellations, 1); expect(voice.latest.stops, 0); expect(capture.transcript, isEmpty);
  });
  testWidgets('D04 D07 canceled generation cannot revive text or its silence timer', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final capture = VoiceCaptureController(voice); addTearDown(capture.dispose); addTearDown(voice.dispose);
    final oldResult = capture.start(), old = voice.latest;
    old.emit(const VoiceEvent('ready')); old.emit(const VoiceEvent('speech_start'));
    old.emit(const VoiceEvent('speech_end')); await tester.pump(); capture.cancel();
    final result = capture.start(), fresh = voice.latest;
    fresh.emit(const VoiceEvent('ready')); old.emit(const VoiceEvent('final', text: 'نص متأخر'));
    await tester.pump(const Duration(seconds: 3));
    expect(await oldResult, isNull); expect(capture.preview, isEmpty); expect(fresh.stops, 0);
    capture.didChangeAppLifecycleState(AppLifecycleState.paused); await tester.pump();
    expect(await result, isNull); expect(fresh.cancellations, 1);
  });
  testWidgets('D05 technical failure keeps stable text separate from an unconfirmed hypothesis', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final controller = VoiceCaptureController(voice); addTearDown(controller.dispose); addTearDown(voice.dispose);
    final result = controller.start(); voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('segment', text: 'شقة للإيجار'));
    voice.latest.emit(const VoiceEvent('partial', text: 'شقة للإيجار بمئة'));
    voice.latest.emit(const VoiceEvent('error', code: 'SPEECH_NETWORK')); await tester.pump();
    expect(await result, isNull); expect(controller.transcript, isEmpty);
    expect(controller.stablePreview, 'شقة للإيجار'); expect(controller.error, isNotNull);
  });
  testWidgets('D10 listing keeps tentative words visible without committing them', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final changes = <String>[];
    addTearDown(voice.dispose);
    await pumpWave6(tester, Scaffold(body: ListingAiSheet(
      prepareDraft: true, facts: const {}, initialMessage: 'typed',
      onMessageChanged: changes.add,
    )), voice: voice, ai: Wave6Ai());
    await tester.tap(find.byKey(const ValueKey('listing-ai-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('speech_start'));
    voice.latest.emit(const VoiceEvent('partial', text: 'tentative words'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    final brief = tester.widget<TextField>(find.byKey(const ValueKey('listing-ai-brief')));
    expect(brief.controller!.text, 'typed tentative words');
    expect(changes, isEmpty);
    expect(find.byKey(const ValueKey('listing-ai-field-type')), findsNothing);
    await finishWave6(tester);
  });
  testWidgets('D01 D04 D06 listing live text resets only the dictated portion and never prepares automatically', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), ai = Wave6Ai(); addTearDown(voice.dispose);
    await pumpWave6(tester, const Scaffold(body: ListingAiSheet(prepareDraft: true, facts: {}, initialMessage: 'كتبت هذا')), voice: voice, ai: ai);
    await tester.tap(find.byKey(const ValueKey('listing-ai-voice'))); await tester.pump();
    final old = voice.latest;
    old.emit(const VoiceEvent('mode', code: 'dictation')); old.emit(const VoiceEvent('ready'));
    old.emit(const VoiceEvent('partial', text: 'أربع غرف')); await tester.pump();
    final brief = find.byKey(const ValueKey('listing-ai-brief'));
    expect(tester.widget<TextField>(brief).controller!.text, 'كتبت هذا أربع غرف');
    await tester.ensureVisible(find.byKey(const ValueKey('voice-restart')));
    await tester.tap(find.byKey(const ValueKey('voice-restart'))); await tester.pump();
    expect(voice.calls, 2); expect(tester.widget<TextField>(brief).controller!.text, 'كتبت هذا');
    old.emit(const VoiceEvent('final', text: 'قديم'));
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('speech_start'));
    voice.latest.emit(const VoiceEvent('segment', text: 'حمامين')); voice.latest.emit(const VoiceEvent('speech_end')); await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500));
    voice.latest.emit(const VoiceEvent('final', text: 'حمامين')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(brief).controller!.text, 'كتبت هذا حمامين');
    expect(find.byKey(const ValueKey('listing-ai-field-type')), findsNothing);
    expect(find.byKey(const ValueKey('listing-ai-prepare')), findsOneWidget);
    expect(find.byKey(const ValueKey('listing-voice-clip')), findsNothing);
    await finishWave6(tester);
  });
  testWidgets('D10 editor retains tentative description without automatic save', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final recovery = Wave6Recovery(editorSnapshot());
    final drafts = Wave6Drafts();
    addTearDown(voice.dispose);
    await pumpWave6(tester, const ListingEditorScreen(),
        voice: voice, recovery: recovery, drafts: drafts);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('speech_start'));
    voice.latest.emit(const VoiceEvent('partial', text: 'tentative words'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    final description = tester.widget<TextField>(textField('وصف العقار'));
    expect(description.controller!.text, contains('tentative words'));
    expect(drafts.saves.any((p) =>
        (p['fields'] as Map)['description'].toString().contains('tentative words')), isFalse);
    await finishWave6(tester);
  });

  testWidgets('D11 tentative description stays out of recovery after the debounce', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final initial = editorSnapshot(), recovery = Wave6Recovery(editorSnapshot());
    final drafts = Wave6Drafts();
    addTearDown(voice.dispose);
    await pumpWave6(tester, const ListingEditorScreen(), voice: voice, recovery: recovery, drafts: drafts);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'tentative words'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    await tester.pump(const Duration(milliseconds: 700));
    final description = tester.widget<TextField>(textField('وصف العقار'));
    expect(description.controller!.text, contains('tentative words'));
    expect((recovery.snapshot!['fields'] as Map)['description'], (initial['fields'] as Map)['description']);
    expect(drafts.saves.any((p) => (p['fields'] as Map)['description'].toString().contains('tentative words')), isFalse);
    await finishWave6(tester);
  });

  testWidgets('D11 another field can autosave without accepting tentative speech', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final initial = editorSnapshot(), recovery = Wave6Recovery(editorSnapshot());
    final drafts = Wave6Drafts();
    addTearDown(voice.dispose);
    await pumpWave6(tester, const ListingEditorScreen(), voice: voice, recovery: recovery, drafts: drafts);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'tentative words'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    final description = tester.widget<TextField>(textField('وصف العقار'));
    final other = tester.widgetList<TextField>(find.byType(TextField))
        .firstWhere((field) => field.controller != description.controller && field.controller?.text.isNotEmpty == true);
    final original = other.controller!.text;
    final changed = RegExp(r'^\d+$').hasMatch(original) ? '${original}1' : '$original edited';
    other.controller!.text = changed;
    await tester.pump(const Duration(milliseconds: 700));
    expect((recovery.snapshot!['fields'] as Map).values, contains(changed));
    expect((recovery.snapshot!['fields'] as Map)['description'], (initial['fields'] as Map)['description']);
    expect(drafts.saves.any((p) => (p['fields'] as Map)['description'].toString().contains('tentative words')), isFalse);
    await finishWave6(tester);
  });

  testWidgets('D11 editing the visible hypothesis confirms the edited description', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final recovery = Wave6Recovery(editorSnapshot());
    addTearDown(voice.dispose);
    await pumpWave6(tester, const ListingEditorScreen(), voice: voice, recovery: recovery);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'tentative words'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    final description = tester.widget<TextField>(textField('وصف العقار'));
    description.controller!.text = '${description.controller!.text} edited';
    await tester.pump(const Duration(milliseconds: 700));
    expect((recovery.snapshot!['fields'] as Map)['description'], contains('tentative words edited'));
    await finishWave6(tester);
  });

  testWidgets('D11 retry replaces old tentative words and cancellation restores the base', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final initial = editorSnapshot();
    addTearDown(voice.dispose);
    await pumpWave6(tester, const ListingEditorScreen(), voice: voice,
        recovery: Wave6Recovery(editorSnapshot()));
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'old tentative'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'fresh words'));
    await tester.pump();
    final description = tester.widget<TextField>(textField('وصف العقار'));
    expect(description.controller!.text, contains('fresh words'));
    expect(description.controller!.text, isNot(contains('old tentative')));
    await tester.ensureVisible(find.byKey(const ValueKey('voice-cancel')));
    await tester.tap(find.byKey(const ValueKey('voice-cancel')));
    await tester.pump();
    expect(description.controller!.text, (initial['fields'] as Map)['description']);
    await finishWave6(tester);
  });

  testWidgets('D11 explicit draft save confirms the visible tentative description', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false);
    final recovery = Wave6Recovery(editorSnapshot()), drafts = Wave6Drafts();
    addTearDown(voice.dispose);
    await pumpWave6(tester, Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => const ListingEditorScreen())),
      child: const Text('Open voice editor'),
    ))), voice: voice, recovery: recovery, drafts: drafts);
    await tester.tap(find.text('Open voice editor'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice')));
    await tester.pump();
    voice.latest.emit(const VoiceEvent('mode', code: 'dictation'));
    voice.latest.emit(const VoiceEvent('ready'));
    voice.latest.emit(const VoiceEvent('partial', text: 'tentative words'));
    voice.latest.emit(const VoiceEvent('speech_end'));
    await tester.pump(const Duration(seconds: 12));
    final description = tester.widget<TextField>(textField('وصف العقار'));
    final other = tester.widgetList<TextField>(find.byType(TextField))
        .firstWhere((field) => field.controller != description.controller && field.controller?.text.isNotEmpty == true);
    other.controller!.text = '${other.controller!.text} edited';
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-exit-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-exit-save')));
    await tester.pumpAndSettle();
    expect((recovery.snapshot!['fields'] as Map)['description'], contains('tentative words'));
    expect(drafts.saves.any((p) => (p['fields'] as Map)['description'].toString().contains('tentative words')), isTrue);
    await finishWave6(tester);
  });

  testWidgets('D01 D06 description displays live hypotheses but only saves finalized speech', (tester) async {
    final voice = Wave3VoiceFake(autoComplete: false), recovery = Wave6Recovery(editorSnapshot()), drafts = Wave6Drafts(); addTearDown(voice.dispose);
    await pumpWave6(tester, const ListingEditorScreen(), voice: voice, recovery: recovery, drafts: drafts);
    await tester.ensureVisible(find.byKey(const ValueKey('listing-description-voice')));
    await tester.tap(find.byKey(const ValueKey('listing-description-voice'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('ready')); voice.latest.emit(const VoiceEvent('partial', text: 'مدخل مستقل')); await tester.pump();
    expect(tester.widget<TextField>(textField('وصف العقار')).controller!.text, 'وصف كتبه الدلال مدخل مستقل');
    await tester.pump(const Duration(seconds: 1));
    expect(drafts.saves.any((p) => (p['fields'] as Map)['description'].toString().contains('مدخل مستقل')), isFalse);
    await tester.ensureVisible(find.byKey(const ValueKey('voice-finish'))); await tester.tap(find.byKey(const ValueKey('voice-finish'))); await tester.pump();
    voice.latest.emit(const VoiceEvent('final', text: 'مدخل مستقل')); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(textField('وصف العقار')).controller!.text, 'وصف كتبه الدلال مدخل مستقل');
    await finishWave6(tester);
  });
}
