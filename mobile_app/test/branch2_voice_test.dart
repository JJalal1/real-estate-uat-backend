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
    expect(find.byKey(const ValueKey('listing-voice-clip')), findsOneWidget);
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
