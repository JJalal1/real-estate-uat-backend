import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_schema.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave6_fakes.dart';
import 'broker_experience_ui_test.dart' show BrokerTestAuth;
import 'wave6_product_ui_test.dart' show pumpWave6, finishWave6;

class SwitchingAuth extends BrokerTestAuth {
  void switchToAnotherAccount() {
    state = AsyncData(AuthUser.fromJson({
      'id': 2, 'name': 'Synthetic second account',
      'phone': '+967771234567', 'account_status': 'active',
      'phone_verified_at': '2026-10-21T00:00:00Z',
      'profile_completed_at': '2026-10-21T00:00:00Z',
      'verification_profile': {'type': 'broker', 'status': 'approved'},
    }));
  }
}

class CountingRecovery extends Wave6Recovery {
  CountingRecovery([super.snapshot]);
  int writes = 0;
  @override
  Future<void> write(int userId, int? listingId,
      Map<String, dynamic> data, List<String> paths) async {
    writes++;
    await super.write(userId, listingId, data, paths);
  }
}

class DelayedReconcileDrafts extends Wave6Drafts {
  final gate = Completer<void>();
  int gets = 0;
  @override
  Future<ListingAccountDraft> get(String key) async {
    gets++;
    await gate.future;
    return super.get(key);
  }
}

DioException revisionConflict() {
  final options = RequestOptions(path: '/synthetic-draft');
  return DioException(requestOptions: options, type: DioExceptionType.badResponse,
      response: Response(requestOptions: options, statusCode: 409,
          data: {'code': 'draft_revision_conflict'}));
}

class ConflictUploadDrafts extends Wave6Drafts {
  final gate = Completer<void>();
  int uploads = 0, gets = 0;
  bool advanceRevisionOnGet = false;
  @override
  Future<ListingAccountDraft> upload(String key, String imageKey, String path,
      int revision, {CancelToken? cancelToken, ProgressCallback? onSendProgress}) async {
    uploads++;
    if (uploads == 1) { throw revisionConflict(); }
    return super.upload(key, imageKey, path, revision,
        cancelToken: cancelToken, onSendProgress: onSendProgress);
  }
  @override
  Future<ListingAccountDraft> get(String key) async {
    gets++;
    await gate.future;
    if (advanceRevisionOnGet) {
      final old = drafts[key]!;
      drafts[key] = ListingAccountDraft(
        key: old.key, revision: old.revision + 1, payload: old.payload,
        images: old.images, propertyId: old.propertyId,
        title: old.title, progress: old.progress,
      );
    }
    return super.get(key);
  }
}

class ConflictRemoveDrafts extends Wave6Drafts {
  final gate = Completer<void>();
  int removes = 0, gets = 0;
  @override
  Future<ListingAccountDraft> removeImage(String key, String imageKey, int revision) async {
    removes++;
    if (removes == 1) { throw revisionConflict(); }
    return super.removeImage(key, imageKey, revision);
  }
  @override
  Future<ListingAccountDraft> get(String key) async {
    gets++;
    await gate.future;
    return super.get(key);
  }
}

Map<String, dynamic> nearThresholdSnapshot() => {
  'editor_version': 11, 'draft_kind': 'recovery', 'step': 0,
  'type_confirmed': true, 'purpose_confirmed': true,
  'type': 'apartment', 'purpose': 'sale', 'tenure_type': 'freehold',
  'latitude': 15.37, 'longitude': 44.19,
  'fields': {'title': 'Synthetic listing', 'area': '120', 'bedrooms': '2'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);

  test('automatic save requires current progress of at least 50 percent', () {
    expect(DynamicPropertySchema.canBeginAutomaticSave(49), isFalse);
    expect(DynamicPropertySchema.canBeginAutomaticSave(50), isTrue);
    expect(DynamicPropertySchema.canBeginAutomaticSave(51), isTrue);
    final incomplete = <String, dynamic>{
      'editor_version': 11, 'type': 'apartment', 'purpose': 'sale',
      'fields': {'title': 'Synthetic apartment'},
    };
    expect(DynamicPropertySchema.draftProgress(incomplete), lessThan(50));
  });

  test('central progress crosses the threshold for every listing type', () {
    for (final type in [
      'apartment', 'building', 'house', 'villa',
      'land', 'shop', 'office', 'farm',
    ]) {
      final fields = <String, dynamic>{'title': 'Synthetic listing'};
      final snapshot = <String, dynamic>{
        'editor_version': 11, 'type': type, 'purpose': 'sale',
        'latitude': 15.37, 'longitude': 44.19, 'fields': fields,
      };
      final required = DynamicPropertySchema.required(snapshot);
      for (final key in required) {
        switch (key) {
          case 'area_value': fields['area'] = '120'; break;
          case 'has_parking': snapshot['parking'] = 'no'; break;
          case 'building_facade': snapshot['facade'] = 'north'; break;
          case 'tenure_type': snapshot[key] = 'freehold'; break;
          case 'units_per_floor': snapshot[key] = ['1']; break;
          case 'bedrooms' || 'bathrooms' || 'floors_count' ||
                'shop_openings': fields[key] = '2'; break;
          default: fields[key] = 'Synthetic value'; break;
        }
      }
      expect(DynamicPropertySchema.draftProgress(snapshot), 100, reason: type);
      for (final key in ['title', 'latitude', 'longitude', ...required]) {
        if (key == 'area_value') { fields.remove('area'); }
        else if (key == 'has_parking') { snapshot.remove('parking'); }
        else if (key == 'building_facade') { snapshot.remove('facade'); }
        else { snapshot.remove(key); fields.remove(key); }
        if (DynamicPropertySchema.draftProgress(snapshot) < 50) { break; }
      }
      expect(DynamicPropertySchema.draftProgress(snapshot), lessThan(50),
          reason: type);
    }
  });

  testWidgets('fresh partial editor creates neither device nor account checkpoint', (tester) async {
    final recovery = CountingRecovery(), drafts = Wave6Drafts();
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery, drafts: drafts);
    await tester.enterText(find.byType(TextField).first, 'Synthetic apartment');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(recovery.writes, 0);
    expect(drafts.saves, isEmpty);
    await finishWave6(tester);
    expect(recovery.writes, 0);
  });

  testWidgets('account switch cannot checkpoint a fresh draft below 50 percent', (tester) async {
    final recovery = CountingRecovery(), drafts = Wave6Drafts();
    await pumpWave6(tester, ProviderScope(
      overrides: [authControllerProvider.overrideWith(SwitchingAuth.new)],
      child: const ListingEditorScreen(),
    ), recovery: recovery, drafts: drafts);
    await tester.enterText(find.byType(TextField).first, 'Synthetic apartment');
    final scope = ProviderScope.containerOf(tester.element(find.byType(ListingEditorScreen)));
    (scope.read(authControllerProvider.notifier) as SwitchingAuth).switchToAnotherAccount();
    await tester.pumpAndSettle();
    expect(recovery.writes, 0);
    expect(drafts.saves, isEmpty);
    await finishWave6(tester);
    expect(recovery.writes, 0);
  });

  testWidgets('previous recovery is retained without new writes below 50 percent', (tester) async {
    final recovery = CountingRecovery({
      'editor_version': 11, 'draft_kind': 'recovery', 'step': 0,
      'type': 'apartment', 'purpose': 'sale',
      'fields': {'title': 'Earlier saved title'},
    });
    final drafts = Wave6Drafts();
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery, drafts: drafts);
    await tester.enterText(find.byType(TextField).first, 'Changed title');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(recovery.writes, 0);
    expect(drafts.saves, isEmpty);
    expect((recovery.snapshot!['fields'] as Map)['title'], 'Earlier saved title');
    await finishWave6(tester);
  });

  testWidgets('scheduled save is cancelled when current progress falls below 50', (tester) async {
    final original = nearThresholdSnapshot();
    expect(DynamicPropertySchema.draftProgress(original), 55);
    final recovery = CountingRecovery(original), drafts = Wave6Drafts();
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery, drafts: drafts);
    final priorDeviceWrites = recovery.writes, priorAccountWrites = drafts.saves.length;
    final title = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.controller?.text == 'Synthetic listing');
    expect(title, findsOneWidget);
    final titleController = tester.widget<TextField>(title).controller!;
    await tester.enterText(title, 'Changed synthetic listing');
    titleController.clear();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(recovery.writes, priorDeviceWrites);
    expect(drafts.saves.length, priorAccountWrites);
    await finishWave6(tester);
  });

  testWidgets('automatic writes start above 50 then stop after a drop', (tester) async {
    final recovery = CountingRecovery(nearThresholdSnapshot()), drafts = Wave6Drafts();
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery, drafts: drafts);
    final title = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.controller?.text == 'Synthetic listing');
    expect(title, findsOneWidget);
    final titleController = tester.widget<TextField>(title).controller!;
    await tester.enterText(title, 'Changed synthetic listing');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(recovery.writes, greaterThan(0));
    expect(drafts.saves, isNotEmpty);
    final deviceWrites = recovery.writes, accountWrites = drafts.saves.length;
    titleController.clear();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(recovery.writes, deviceWrites);
    expect(drafts.saves.length, accountWrites);
    await finishWave6(tester);
    expect(recovery.writes, deviceWrites);
  });

  testWidgets('existing account draft stays intact without auto writes below 50', (tester) async {
    final payload = <String, dynamic>{
      'editor_version': 11, 'draft_kind': 'saved', 'step': 0,
      'type': 'apartment', 'purpose': 'sale',
      'fields': {'title': 'Saved partial title'},
    };
    final accountDraft = ListingAccountDraft(
      key: 'wave02-synthetic-account-draft', revision: 1,
      payload: payload, title: 'Saved partial title', progress: 25,
    );
    final recovery = CountingRecovery(), drafts = Wave6Drafts();
    await pumpWave6(tester, ListingEditorScreen(accountDraft: accountDraft),
        recovery: recovery, drafts: drafts);
    await tester.enterText(find.byType(TextField).first, 'Changed partial title');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(recovery.writes, 0);
    expect(drafts.saves, isEmpty);
    expect(accountDraft.payload['fields'], {'title': 'Saved partial title'});
    await finishWave6(tester);
  });

  testWidgets('manual save queued during auto reconciliation survives a drop', (tester) async {
    const key = 'wave02-delayed-reconcile', checkpoint = 'wave02-known-checkpoint';
    final snapshot = {
      ...nearThresholdSnapshot(),
      'draft_key': key, 'server_revision': 1,
      'account_checkpoint_key': checkpoint,
    };
    final recovery = CountingRecovery(snapshot), drafts = DelayedReconcileDrafts();
    drafts.drafts[key] = ListingAccountDraft(
      key: key, revision: 1,
      payload: {...snapshot, 'checkpoint_key': checkpoint},
      title: 'Synthetic listing', progress: 55,
    );
    await pumpWave6(tester, Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => const ListingEditorScreen())),
      child: const Text('Open delayed editor'),
    ))), recovery: recovery, drafts: drafts);
    await tester.tap(find.text('Open delayed editor'));
    await tester.pumpAndSettle();
    final title = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.controller?.text == 'Synthetic listing');
    expect(title, findsOneWidget);
    final titleController = tester.widget<TextField>(title).controller!;
    await tester.enterText(title, 'Changed synthetic listing');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(drafts.gets, 1);
    expect(drafts.saves, isEmpty);
    titleController.clear();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-exit-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-exit-save')));
    await tester.pump();
    drafts.gate.complete();
    await tester.pumpAndSettle();
    expect(drafts.saves, hasLength(1));
    expect((drafts.saves.single['fields'] as Map)['title'], '');
    await finishWave6(tester);
  });

  testWidgets('upload conflict cannot retry after progress falls below 50', (tester) async {
    const path = 'C:/synthetic-wave02-image-that-does-not-exist.png';
    final snapshot = {
      ...nearThresholdSnapshot(),
      'image_paths': [path],
      'image_tokens': {path: 'synthetic-photo'},
      'image_order': ['synthetic-photo'],
    };
    final recovery = CountingRecovery(snapshot), drafts = ConflictUploadDrafts();
    await pumpWave6(tester, const ListingEditorScreen(), recovery: recovery, drafts: drafts);
    final title = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.controller?.text == 'Synthetic listing');
    final titleController = tester.widget<TextField>(title).controller!;
    await tester.enterText(title, 'Changed synthetic listing');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(drafts.uploads, 1);
    expect(drafts.gets, 1);
    final deviceWrites = recovery.writes, accountWrites = drafts.saves.length;
    titleController.clear();
    await tester.pump();
    drafts.gate.complete();
    await tester.pumpAndSettle();
    expect(drafts.uploads, 1);
    expect(recovery.writes, deviceWrites);
    expect(drafts.saves.length, accountWrites);
    await finishWave6(tester);
  });

  testWidgets('manual save uses the latest revision after auto upload conflict', (tester) async {
    const path = 'C:/synthetic-wave02-concurrent-image-that-does-not-exist.png';
    final snapshot = {
      ...nearThresholdSnapshot(),
      'image_paths': [path],
      'image_tokens': {path: 'synthetic-concurrent-photo'},
      'image_order': ['synthetic-concurrent-photo'],
    };
    final recovery = CountingRecovery(snapshot);
    final drafts = ConflictUploadDrafts()..advanceRevisionOnGet = true;
    await pumpWave6(tester, Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => const ListingEditorScreen())),
      child: const Text('Open conflicting editor'),
    ))), recovery: recovery, drafts: drafts);
    await tester.tap(find.text('Open conflicting editor'));
    await tester.pumpAndSettle();
    final title = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.controller?.text == 'Synthetic listing');
    final titleController = tester.widget<TextField>(title).controller!;
    await tester.enterText(title, 'Changed synthetic listing');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(drafts.uploads, 1);
    expect(drafts.gets, 1);
    titleController.clear();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-exit-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-exit-save')));
    await tester.pump();
    drafts.gate.complete();
    await tester.pumpAndSettle();
    expect(drafts.uploads, 2); // The second write is the explicit user Save.
    expect(drafts.saves, hasLength(2));
    expect((drafts.saves.last['fields'] as Map)['title'], '');
    await finishWave6(tester);
  });

  testWidgets('remove conflict cannot retry after progress falls below 50', (tester) async {
    const key = 'wave02-remote-image-draft', imageKey = 'synthetic-remote-photo';
    final snapshot = {
      ...nearThresholdSnapshot(),
      'draft_kind': 'saved',
      'removed_image_keys': [imageKey],
    };
    final accountDraft = ListingAccountDraft(
      key: key, revision: 1, payload: snapshot,
      images: {imageKey: 'https://fixture.invalid/private-synthetic-photo'},
      title: 'Synthetic listing', progress: 55,
    );
    final recovery = CountingRecovery(), drafts = ConflictRemoveDrafts();
    drafts.drafts[key] = accountDraft;
    await pumpWave6(tester, ListingEditorScreen(accountDraft: accountDraft),
        recovery: recovery, drafts: drafts);
    final title = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.controller?.text == 'Synthetic listing');
    final titleController = tester.widget<TextField>(title).controller!;
    await tester.enterText(title, 'Changed synthetic listing');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(drafts.removes, 1);
    expect(drafts.gets, 1);
    final deviceWrites = recovery.writes, accountWrites = drafts.saves.length;
    titleController.clear();
    await tester.pump();
    drafts.gate.complete();
    await tester.pumpAndSettle();
    expect(drafts.removes, 1);
    expect(recovery.writes, deviceWrites);
    expect(drafts.saves.length, accountWrites);
    await finishWave6(tester);
  });

  testWidgets('explicit exit save remains available below 50 percent', (tester) async {
    final recovery = CountingRecovery(), drafts = Wave6Drafts();
    await pumpWave6(tester, Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => const ListingEditorScreen())),
      child: const Text('Open synthetic editor'),
    ))), recovery: recovery, drafts: drafts);
    await tester.tap(find.text('Open synthetic editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Synthetic partial listing');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-exit-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-exit-save')));
    await tester.pumpAndSettle();
    expect(recovery.writes, greaterThan(0));
    expect(drafts.saves, isNotEmpty);
    await finishWave6(tester);
  });
}
