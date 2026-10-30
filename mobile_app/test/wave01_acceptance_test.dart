import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/platform/voice_input.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/account_verification_repository.dart';
import 'package:real_estate_mobile/features/account/domain/account_verification.dart';
import 'package:real_estate_mobile/features/account/presentation/account_verification_screen.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/assisted_search_screen.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_search_panel.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_assistant.dart';
import 'package:real_estate_mobile/features/map/presentation/map_screen.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_entry_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart';
import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot, textField;

class _Verification implements AccountVerificationRepository {
  @override
  Future<AccountVerificationApplication> status() async => AccountVerificationApplication.fromJson({'user_id': 1});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Drafts extends Wave6Drafts {
  Completer<List<ListingAccountDraft>>? delayed;
  bool fail = false;
  int lists = 0, retired = 0, reads = 0;
  @override
  Future<List<ListingAccountDraft>> list() async {
    lists++;
    if (fail) { throw const SocketException('Synthetic offline source'); }
    return delayed?.future ?? super.list();
  }
  @override
  Future<ListingAccountDraft> get(String key) { reads++; return super.get(key); }
  @override
  Future<void> retireRecovery(String key, int revision) { retired++; return super.retireRecovery(key, revision); }
}

class _Device extends Wave6Recovery {
  _Device(super.snapshot);
  final savedRows = <Map<String, dynamic>>[];
  int deleted = 0;
  @override
  Future<List<Map<String, dynamic>>> saved(int userId) async => savedRows;
  @override
  Future<void> pinExplicitSave(int userId, {bool preserveUnclassified = false}) async {
    if (snapshot != null && !isAutomaticListingRecovery(snapshot!)) { savedRows.add(Map.of(snapshot!)); }
  }
  @override
  Future<void> deleteSaved(int userId, String key) async { deleted++; }
}

class _Legacy extends Wave6Properties {
  final property = PropertyDetails.fromJson({'id': 77, 'title': 'إعلان قديم محفوظ', 'description': 'وصف المسودة القديمة',
    'type': 'apartment', 'purpose': 'sale', 'price': 1000000, 'currency': 'YER', 'status': 'draft', 'review_status': 'draft',
    'latitude': 15.37, 'longitude': 44.19, 'address': 'صنعاء'});
  @override
  Future<List<PropertyDetails>> myListings() async => [property];
  @override
  Future<PropertyDetails> details(int id) async => property;
}

Map<String, dynamic> _payload(String key, {String kind = 'saved'}) => {
  ...editorSnapshot(), 'editor_version': 10, 'draft_key': key, 'draft_kind': kind, 'entry_method': 'manual',
};

Future<void> _tap(WidgetTester tester, String key, {bool settle = true}) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target); await tester.tap(target);
  if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(); }
}

void main() {
  setUpAll(loadUxFixtures);

  for (final dark in [false, true]) {
    testWidgets('T01 T02 live voice appends once and executes only one final query dark=$dark', (tester) async {
      final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), properties = Wave3PropertiesFake(), boundary = GlobalKey();
      addTearDown(voice.dispose);
      final scope = uxContainer(extra: [voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai),
        propertyRepositoryProvider.overrideWithValue(properties)]);
      await pumpUx(tester, scope, const AssistedSearchScreen(), dark: dark, boundary: boundary);
      final input = find.byKey(const ValueKey('smart-search-description'));
      await tester.enterText(input, 'فلل');
      await _tap(tester, 'smart-search-voice', settle: false);
      voice.latest.emit(const VoiceEvent('mode', code: 'dictation')); voice.latest.emit(const VoiceEvent('ready'));
      voice.latest.emit(const VoiceEvent('partial', text: 'في صنعاء')); await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, 'فلل في صنعاء');
      expect(ai.requests, isEmpty);
      voice.latest.emit(const VoiceEvent('speech_end')); await tester.pump(const Duration(milliseconds: 1500));
      expect(ai.requests, isEmpty); expect(voice.latest.stops, 0);
      await uxPreview(tester, boundary, 'wave01-voice-$dark-live');
      await _tap(tester, 'voice-finish', settle: false);
      expect(find.text('نثبّت آخر كلماتك…'), findsOneWidget);
      expect(ai.requests, isEmpty);
      voice.latest.emit(const VoiceEvent('final', text: 'في صنعاء')); await tester.pumpAndSettle();
      expect(ai.requests.single.message, 'فلل في صنعاء');
      expect(properties.queries, hasLength(1));
      expect(tester.widget<TextField>(input).controller!.text, 'فلل في صنعاء');
      voice.latest.emit(const VoiceEvent('final', text: 'نتيجة متأخرة مكررة')); await tester.pump();
      await _tap(tester, 'smart-search-send');
      expect(ai.requests, hasLength(1));
      expect(find.text('تسجيل مقطع كامل (بديل)'), findsNothing);
      await uxPreview(tester, boundary, 'wave01-voice-$dark-final');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  for (final outcome in ['cancel', 'error', 'empty', 'account']) {
    testWidgets('T03 T12 $outcome never submits partial text or an obsolete final', (tester) async {
      final voice = Wave3VoiceFake(autoComplete: false), ai = Wave3AiFake(), auth = UxAuth(uxUser(id: 1));
      addTearDown(voice.dispose);
      final scope = uxContainer(auth: auth, extra: [voiceInputProvider.overrideWithValue(voice), aiRepositoryProvider.overrideWithValue(ai)]);
      await pumpUx(tester, scope, const AssistedSearchScreen());
      final input = find.byKey(const ValueKey('smart-search-description'));
      await tester.enterText(input, 'كتبت هذا');
      await _tap(tester, 'smart-search-voice', settle: false);
      final old = voice.latest;
      old.emit(const VoiceEvent('mode', code: 'dictation')); old.emit(const VoiceEvent('ready'));
      old.emit(const VoiceEvent('partial', text: 'كلام مؤقت')); await tester.pump();
      if (outcome == 'cancel') { await _tap(tester, 'voice-cancel'); }
      if (outcome == 'error') { old.emit(const VoiceEvent('error', code: 'SPEECH_NETWORK')); await tester.pump(); }
      if (outcome == 'empty') {
        await _tap(tester, 'voice-finish', settle: false);
        old.emit(const VoiceEvent('final', text: '')); await tester.pump();
      }
      if (outcome == 'account') {
        auth.change(uxUser(id: 2)); await tester.pumpAndSettle();
        auth.change(uxUser(id: 1)); await tester.pumpAndSettle();
      }
      old.emit(const VoiceEvent('final', text: 'طلب قديم')); await tester.pumpAndSettle();
      expect(ai.requests, isEmpty);
      expect(tester.widget<TextField>(input).controller!.text, outcome == 'account' ? '' : 'كتبت هذا');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  testWidgets('T08 collapse, drag, pan and reopen preserve criteria without a new query', (tester) async {
    var pans = 0;
    final properties = Wave6Properties();
    final scope = uxContainer(extra: [
      propertyRepositoryProvider.overrideWithValue(properties),
      sharedSearchMapBuilderProvider.overrideWithValue((context, rows, select, viewport) => GestureDetector(
        key: const ValueKey('wave01-map'), behavior: HitTestBehavior.opaque,
        onPanUpdate: (_) => pans++, child: const ColoredBox(color: Color(0xffd5e4dd)))),
    ]);
    // This probe uses the actual shared controller; synthetic touch handling is
    // explicitly separate from native MapLibre/device acceptance.
    await pumpUx(tester, scope, const MarketplaceSearchMapScreen());
    await tester.pumpAndSettle();
    final controller = scope.read(marketplaceSearchControllerProvider.notifier);
    controller.applyFilters(SmartSearchFilters.fromMap({'types': ['apartment', 'villa'], 'purpose': 'rent', 'max_price': 250000}));
    await tester.pumpAndSettle();
    final before = scope.read(marketplaceMapResultsProvider).revision;
    final queries = properties.queries.length;
    final filters = scope.read(marketplaceMapResultsProvider).filters;
    await _tap(tester, 'map-filter-panel-toggle');
    final collapsed = tester.getRect(find.byKey(const ValueKey('map-search-panel-surface')));
    final map = tester.getRect(find.byKey(const ValueKey('wave01-map')));
    expect(collapsed.top - map.top, greaterThan(150));
    final free = Offset(map.center.dx, map.top + 70);
    await tester.dragFrom(free, const Offset(35, 20)); await tester.pumpAndSettle();
    expect(pans, greaterThan(0));
    final oldPans = pans;
    await tester.drag(find.byKey(const ValueKey('map-results-handle')), const Offset(0, -240)); await tester.pumpAndSettle();
    expect(pans, oldPans);
    expect(tester.getRect(find.byKey(const ValueKey('map-search-panel-surface'))).top, lessThan(collapsed.top));
    expect(scope.read(marketplaceMapResultsProvider).revision, before);
    expect(scope.read(marketplaceMapResultsProvider).filters.sameAs(filters), isTrue);
    expect(properties.queries.length, queries);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('T09 independent map button is above the assistant and duplicate taps open once', (tester) async {
    final opened = Completer<void>(); var maps = 0, robots = 0;
    final scope = uxContainer();
    await pumpUx(tester, scope, Scaffold(body: SmartSearchAssistantLayer(showComparisonTray: false,
      onOpenMap: () { maps++; return opened.future; }, onPressed: () => robots++, child: const SizedBox.expand())), size: const Size(320, 568), scale: 2.4);
    final map = find.byKey(const ValueKey('floating-map-search')), robot = find.byKey(const ValueKey('floating-smart-search'));
    expect(tester.getRect(map).bottom, lessThan(tester.getRect(robot).top));
    expect(tester.getSize(map).width, greaterThanOrEqualTo(48));
    await tester.tap(map); await tester.pump(); await tester.tap(map); await tester.pump();
    expect(maps, 1); expect(robots, 0);
    opened.complete(); await tester.pump();
    await tester.tap(robot); await tester.pump(); expect(robots, 1);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  for (final source in ['server', 'local', 'legacy']) {
    testWidgets('T10 saved $source work keeps a stable choice until the user resumes', (tester) async {
      final key = newListingDraftKey(), drafts = _Drafts(), device = _Device(null);
      if (source == 'server') { drafts.drafts[key] = ListingAccountDraft(key: key, revision: 1, title: 'مسودة محفوظة صراحة', payload: _payload(key)); }
      if (source == 'local') { device.savedRows.add(_payload(key)); }
      final scope = uxContainer(user: uxUser(type: 'broker'), extra: [listingAccountDraftRepositoryProvider.overrideWithValue(drafts),
        listingRecoveryStoreProvider.overrideWithValue(device), aiRepositoryProvider.overrideWithValue(Wave6Ai()),
        if (source == 'legacy') propertyRepositoryProvider.overrideWithValue(_Legacy())]);
      await pumpUx(tester, scope, const ListingDraftEntryScreen()); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listing-recovery-choice')), findsOneWidget);
      expect(find.byType(ListingEditorScreen), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(find.byKey(const ValueKey('listing-recovery-choice')), findsOneWidget);
      await _tap(tester, 'listing-recovery-resume');
      expect(find.byType(ListingEditorScreen), findsOneWidget);
      expect(drafts.retired, 0); expect(device.deleted, 0);
      expect(tester.widget<TextField>(textField('وصف العقار')).controller!.text,
        source == 'legacy' ? 'وصف المسودة القديمة' : 'وصف كتبه الدلال');
      expect(tester.takeException(), isNull); await closeUx(tester);
    });
  }

  testWidgets('T11 repeated new presses share one confirmation and cancel preserves all saved work', (tester) async {
    final key = newListingDraftKey(), saved = newListingDraftKey(), drafts = _Drafts(), device = _Device(null);
    drafts.drafts[key] = ListingAccountDraft(key: key, revision: 1, payload: _payload(key, kind: 'recovery'));
    drafts.drafts[saved] = ListingAccountDraft(key: saved, revision: 2, payload: _payload(saved));
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [listingAccountDraftRepositoryProvider.overrideWithValue(drafts),
      listingRecoveryStoreProvider.overrideWithValue(device), aiRepositoryProvider.overrideWithValue(Wave6Ai())]);
    await pumpUx(tester, scope, const ListingDraftEntryScreen()); await tester.pumpAndSettle();
    final action = tester.widget<TextButton>(find.byKey(const ValueKey('listing-recovery-new'))).onPressed!;
    action(); action(); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget); expect(drafts.retired, 0);
    await tester.tap(find.text('رجوع').last); await tester.pumpAndSettle();
    expect(drafts.drafts.keys, containsAll([key, saved])); expect(drafts.retired, 0);
    await _tap(tester, 'listing-recovery-new'); await _tap(tester, 'listing-confirm-discard');
    expect(drafts.retired, 1); expect(drafts.drafts.containsKey(saved), isTrue); expect(device.deleted, 0);
    expect(find.byType(ListingEditorScreen), findsOneWidget);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('T12 offline and delayed draft sources never imply absence or remove local recovery', (tester) async {
    final key = newListingDraftKey(), drafts = _Drafts()..delayed = Completer<List<ListingAccountDraft>>(), device = _Device(_payload(key, kind: 'recovery'));
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [listingAccountDraftRepositoryProvider.overrideWithValue(drafts),
      listingRecoveryStoreProvider.overrideWithValue(device), aiRepositoryProvider.overrideWithValue(Wave6Ai())]);
    await pumpUx(tester, scope, const ListingDraftEntryScreen());
    await tester.pump(const Duration(seconds: 16)); await tester.pump();
    expect(find.byType(ListingEditorScreen), findsNothing);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('listing-recovery-new'))).onPressed, isNull);
    expect(device.snapshot!['draft_key'], key);
    drafts.delayed!.complete([]); drafts.delayed = null; drafts.fail = true;
    await tester.tap(find.text('إعادة المحاولة')); await tester.pumpAndSettle();
    expect(find.byType(ListingEditorScreen), findsNothing); expect(drafts.retired, 0);
    drafts.fail = false;
    await tester.tap(find.text('إعادة المحاولة')); await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('listing-recovery-new'))).onPressed, isNotNull);
    expect(device.snapshot!['draft_key'], key);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('T05 actual Arabic account roles remain whole in 320dp dark=$dark scale=$scale', (tester) async {
        final scope = uxContainer(user: uxUser(), extra: [accountVerificationRepositoryProvider.overrideWithValue(_Verification())]);
        final boundary = GlobalKey();
        await pumpUx(tester, scope, const AccountVerificationScreen(), dark: dark, scale: scale, size: const Size(320, 700), boundary: boundary);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('مكتب عقارات')); await tester.pumpAndSettle();
        for (final label in ['مالك', 'دلال', 'مكتب عقارات']) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
          expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width + 1), reason: label);
        }
        await uxPreview(tester, boundary, 'wave01-roles-$dark-$scale');
        expect(tester.takeException(), isNull); await closeUx(tester);
      });

      testWidgets('T05 T10 recovery dialog is stable and readable in 320dp dark=$dark scale=$scale', (tester) async {
        final key = newListingDraftKey(), drafts = _Drafts(), boundary = GlobalKey();
        drafts.drafts[key] = ListingAccountDraft(key: key, revision: 1, title: 'إعلان محفوظ للاختبار', payload: _payload(key), progress: 60);
        final scope = uxContainer(user: uxUser(type: 'broker'), extra: [listingAccountDraftRepositoryProvider.overrideWithValue(drafts),
          listingRecoveryStoreProvider.overrideWithValue(_Device(null))]);
        await pumpUx(tester, scope, const ListingDraftEntryScreen(), dark: dark, scale: scale, size: const Size(320, 568), boundary: boundary);
        await tester.pumpAndSettle(); await tester.pump(const Duration(seconds: 10));
        await tester.ensureVisible(find.byKey(const ValueKey('listing-recovery-new'))); await tester.pumpAndSettle();
        expect(find.byType(ListingEditorScreen), findsNothing);
        await uxPreview(tester, boundary, 'wave01-drafts-$dark-$scale');
        expect(tester.takeException(), isNull); await closeUx(tester);
      });
    }
  }

  testWidgets('T05 switching the shared theme retains the focused field and its text', (tester) async {
    final text = TextEditingController(), focus = FocusNode(), mode = ValueNotifier(ThemeMode.light);
    addTearDown(text.dispose); addTearDown(focus.dispose); addTearDown(mode.dispose);
    await tester.pumpWidget(ValueListenableBuilder(valueListenable: mode, builder: (_, selected, __) => MaterialApp(
      theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: selected,
      home: Scaffold(body: TextField(controller: text, focusNode: focus)))));
    await tester.enterText(find.byType(TextField), 'بيانات لم أحفظها بعد'); focus.requestFocus(); await tester.pump();
    mode.value = ThemeMode.dark; await tester.pumpAndSettle();
    expect(text.text, 'بيانات لم أحفظها بعد'); expect(focus.hasFocus, isTrue);
    expect(Theme.of(tester.element(find.byType(TextField))).brightness, Brightness.dark);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });
}
