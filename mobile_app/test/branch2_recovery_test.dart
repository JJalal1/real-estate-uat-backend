import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/presentation/add_property_wizard_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_entry_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, finishWave6, editorSnapshot, textField, previewWave6;

class Drafts extends Wave6Drafts {
  int lists = 0, retired = 0;
  bool failRetire = false;
  @override
  Future<List<ListingAccountDraft>> list() { lists++; return super.list(); }
  @override
  Future<void> retireRecovery(String key, int revision) async {
    retired++;
    if (failRetire) throw const SocketException('Synthetic disconnected network');
    await super.retireRecovery(key, revision);
  }
}
Map<String, dynamic> recovery({String kind = 'recovery'}) => {
  ...editorSnapshot(), 'editor_version': 10, 'draft_kind': kind, 'entry_method': 'manual',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);
  test('A05 unknown older checkpoints and property-linked work are protected', () {
    expect(ListingAccountDraft(key: newListingDraftKey(), revision: 1, payload: editorSnapshot()).isRecovery, isFalse);
    expect(ListingAccountDraft(key: newListingDraftKey(), revision: 1, payload: recovery()).isRecovery, isTrue);
    expect(ListingAccountDraft(key: newListingDraftKey(), revision: 1, payload: recovery(), propertyId: 7).isRecovery, isFalse);
    expect(ListingAccountDraft(key: newListingDraftKey(), revision: 1, payload: recovery(kind: 'saved')).isRecovery, isFalse);
  });
  test('A05 A06 saved device photos and fields survive clearing recovery and starting another account attempt', () async {
    final dir = await Directory.systemTemp.createTemp('branch2-private-recovery-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/source.png')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
    final store = ListingRecoveryStore(directory: () async => Directory('${dir.path}/support'));
    final key = newListingDraftKey(), photo = newListingDraftKey();
    await store.write(1, null, {...recovery(kind: 'saved'), 'draft_key': key, 'image_tokens': {source.path: photo}}, [source.path]);
    await store.pinExplicitSave(1); await store.pinExplicitSave(1);
    await store.clear(1, null);
    await store.write(1, null, {...recovery(), 'draft_key': newListingDraftKey()}, []);
    final old = (await store.saved(1)).single;
    expect(old['draft_key'], key); expect((old['fields'] as Map)['description'], 'وصف كتبه الدلال');
    final file = File((old['image_paths'] as List).single as String);
    expect(await file.readAsBytes(), await source.readAsBytes());
    expect(await store.saved(2), isEmpty);
    expect((await store.read(1, null))!['draft_key'], isNot(key));
    await store.deleteSaved(1, key); expect(await store.saved(1), isEmpty);
    expect(await store.read(1, null), isNotNull);
  });
  test('legacy device work receives a stable key on first read', () async {
    final root = await Directory.systemTemp.createTemp('legacy-draft-key-');
    addTearDown(() => root.delete(recursive: true));
    ListingRecoveryStore open() => ListingRecoveryStore(directory: () async => root);
    await open().write(7, null, {'fields': {'title': 'بيانات قديمة'}}, []);
    final key = (await open().read(7, null))!['draft_key'];
    expect(key, isA<String>());
    expect((await open().read(7, null))!['draft_key'], key);
    await open().pinExplicitSave(7, preserveUnclassified: true);
    expect((await open().saved(7)).single['draft_key'], key);
  });
  test('restart and seven-day expiry survive reopening the store', () async {
    final root = await Directory.systemTemp.createTemp('draft-retention-');
    addTearDown(() => root.delete(recursive: true));
    var now = DateTime.utc(2026, 11, 1);
    ListingRecoveryStore open() => ListingRecoveryStore(directory: () async => root, clock: () => now);
    final manualKey = newListingDraftKey(), autoKey = newListingDraftKey();
    final manual = {...recovery(kind: 'saved'), 'draft_key': manualKey};
    final automatic = {...recovery(), 'draft_key': autoKey, 'first_saved_at': now.toIso8601String()};
    await open().write(7, null, manual, []);
    await open().pinExplicitSave(7);
    await open().write(7, null, automatic, []);
    now = now.add(const Duration(days: 5));
    final revised = {...manual, 'first_saved_at': DateTime.utc(2026, 11, 1).toIso8601String()};
    await open().write(7, null, revised, []);
    expect((await open().read(7, null))!['draft_key'], autoKey);
    final reset = now.toIso8601String();
    await open().rememberRestart(7, reset);
    expect(await open().pendingRestart(7), reset);
    expect(await open().pendingRestart(8), isNull);
    expect(await open().read(7, null), isNull);
    expect((await open().saved(7)).single['draft_key'], manualKey);
    await open().acknowledgeRestart(7, reset);
    expect(await open().pendingRestart(7), isNull);
    await expectLater(open().write(7, null, automatic, []), throwsStateError);
    now = now.add(const Duration(days: 2));
    expect(await open().saved(7), isEmpty);
    await expectLater(open().write(7, null, revised, []), throwsStateError);
  });
  testWidgets('saved drafts show one resume card and a manual menu with no thumbnails', (tester) async {
    final drafts = Drafts(), manual = newListingDraftKey(), latest = newListingDraftKey();
    drafts.drafts[manual] = ListingAccountDraft(key: manual, revision: 1, payload: {
      ...recovery(kind: 'saved'), 'fields': {'governorate': 'صنعاء', 'district': 'معين'}
    }, title: 'شقة محفوظة');
    drafts.drafts[latest] = ListingAccountDraft(key: latest, revision: 1, payload: recovery(),
      title: 'إعلان تلقائي', progress: 65);
    await pumpWave6(tester, const ListingDraftEntryScreen(showSavedDrafts: true), drafts: drafts);
    expect(find.text('أكمل آخر إعلان'), findsOneWidget);
    expect(find.text('اكتمال البيانات 65٪'), findsOneWidget);
    expect(find.text('المسودات اليدوية'), findsOneWidget);
    expect(find.text('صنعاء، معين'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await tester.tap(find.byTooltip('خيارات المسودة')); await tester.pumpAndSettle();
    expect(find.text('حذف المسودة'), findsOneWidget);
    await finishWave6(tester);
  });
  testWidgets('A01 choosing creation method precedes any account-recovery request', (tester) async {
    final drafts = Drafts();
    await pumpWave6(tester, const AddPropertyWizardScreen(), drafts: drafts);
    expect(drafts.lists, 0); expect(find.byKey(const ValueKey('listing-method-choice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-method-manual'))); await tester.pumpAndSettle();
    expect(drafts.lists, 1); expect(find.byType(ListingEditorScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('listing-recovery-choice')), findsNothing);
    await finishWave6(tester);
  });
  for (final scale in [1.0, 2.4]) {
    testWidgets('A02 A03 centered recovery resumes the existing stage at text $scale', (tester) async {
      final drafts = Drafts(), key = newListingDraftKey(), boundary = GlobalKey();
      drafts.drafts[key] = ListingAccountDraft(key: key, revision: 2, payload: recovery(), title: 'مسودة صناعية للتجربة', progress: 60);
      await pumpWave6(tester, const ListingDraftEntryScreen(), drafts: drafts, scale: scale, boundary: boundary);
      final box = tester.getRect(find.byType(Dialog));
      expect((box.center.dy - 457.5).abs(), lessThan(30));
      expect(find.byKey(const ValueKey('listing-draft-choice')), findsNothing);
      await previewWave6(tester, boundary, 'branch2-recovery-$scale');
      await tester.ensureVisible(find.byKey(const ValueKey('listing-recovery-resume')));
      await tester.tap(find.byKey(const ValueKey('listing-recovery-resume'))); await tester.pumpAndSettle();
      expect(tester.widget<TextField>(textField('وصف العقار (اختياري)')).controller!.text, 'وصف كتبه الدلال');
      expect(drafts.drafts[key]!.revision, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull); await finishWave6(tester);
    });
  }
  testWidgets('A04 A05 failure never claims retirement and retry preserves manually saved work', (tester) async {
    final drafts = Drafts()..failRetire = true;
    final autoKey = newListingDraftKey(), savedKey = newListingDraftKey();
    drafts.drafts[autoKey] = ListingAccountDraft(key: autoKey, revision: 1, payload: recovery(), title: 'التقدم التلقائي');
    drafts.drafts[savedKey] = ListingAccountDraft(key: savedKey, revision: 1, payload: recovery(kind: 'saved'), title: 'محفوظة صراحة');
    await pumpWave6(tester, const ListingDraftEntryScreen(), drafts: drafts);
    await tester.tap(find.byKey(const ValueKey('listing-recovery-new'))); await tester.pumpAndSettle();
    expect(drafts.retired, 0);
    await tester.tap(find.byKey(const ValueKey('listing-confirm-discard'))); await tester.pumpAndSettle();
    expect(find.byType(ListingEditorScreen), findsNothing); expect(drafts.drafts.containsKey(autoKey), isTrue);
    expect(find.textContaining('لم يكتمل إلغاء'), findsOneWidget);
    drafts.failRetire = false;
    await tester.tap(find.byKey(const ValueKey('listing-recovery-new'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('listing-confirm-discard'))); await tester.pumpAndSettle();
    expect(drafts.drafts.containsKey(autoKey), isFalse); expect(drafts.drafts.containsKey(savedKey), isTrue);
    expect(find.byType(ListingEditorScreen), findsOneWidget); await finishWave6(tester);
  });
}
