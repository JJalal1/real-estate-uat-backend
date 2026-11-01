import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_entry_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';

import 'support/owner_ux_fixtures.dart';
import 'support/wave6_fakes.dart';

class _DelayedSaiPolicy extends Wave6Properties {
  final requested = Completer<void>();
  final release = Completer<void>();

  @override
  Future<PropertySaiManagement> saiPolicy(String purpose) async {
    if (!requested.isCompleted) requested.complete();
    await release.future;
    return super.saiPolicy(purpose);
  }
}

class _PausedRecovery extends Wave6Recovery {
  final requested = Completer<void>();
  final release = Completer<Map<String, dynamic>?>();

  @override
  Future<Map<String, dynamic>?> read(int userId, int? listingId) {
    if (!requested.isCompleted) requested.complete();
    return release.future;
  }
}

class _CountingAi extends Wave6Ai {
  int prepareCalls = 0;
  Completer<Map<String, dynamic>>? pendingPrepare;

  @override
  Future<Map<String, dynamic>> prepareListing(String message,
      Map<String, dynamic> facts, {int? propertyId, String? draftKey}) {
    prepareCalls++;
    if (pendingPrepare case final pending?) return pending.future;
    return super.prepareListing(message, facts,
        propertyId: propertyId, draftKey: draftKey);
  }
}

void main() {
  setUpAll(loadUxFixtures);

  testWidgets('AI entry hides the manual form until the assistant opens',
      (tester) async {
    final properties = _DelayedSaiPolicy();
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [
      propertyRepositoryProvider.overrideWithValue(properties),
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
      aiRepositoryProvider.overrideWithValue(Wave6Ai()),
    ]);

    await pumpUx(
        tester,
        scope,
        const ListingEditorScreen(
          startFresh: true,
          startWithAssistant: true,
        ));
    await properties.requested.future;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(ListingAiSheet), findsOneWidget);
    expect(
        find.byKey(const ValueKey('listing-draft-assistant-entry'),
            skipOffstage: false),
        findsNothing);
    properties.release.complete();
    await tester.pump();
    Navigator.of(tester.element(find.byType(ListingAiSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-draft-assistant-entry')),
        findsOneWidget);
    await closeUx(tester);
  });

  testWidgets('resuming an assistant draft opens AI before the manual form',
      (tester) async {
    final key = newListingDraftKey();
    final drafts = Wave6Drafts()
      ..drafts[key] = ListingAccountDraft(
        key: key,
        revision: 3,
        progress: 60,
        payload: {
          'draft_key': key,
          'draft_kind': 'saved',
          'editor_version': 11,
          'entry_method': 'assistant',
          'fields': {'title': 'Synthetic saved listing'}
        },
      );
    final properties = _DelayedSaiPolicy();
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [
      listingAccountDraftRepositoryProvider.overrideWithValue(drafts),
      propertyRepositoryProvider.overrideWithValue(properties),
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
      aiRepositoryProvider.overrideWithValue(Wave6Ai()),
    ]);

    await pumpUx(
        tester, scope, const ListingDraftEntryScreen(startWithAssistant: true));
    expect(
        find.byKey(const ValueKey('listing-recovery-choice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('listing-recovery-resume')));
    await tester.pump();
    await properties.requested.future;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(ListingAiSheet), findsOneWidget);
    expect(
        find.byKey(const ValueKey('listing-draft-assistant-entry'),
            skipOffstage: false),
        findsNothing);
    properties.release.complete();
    Navigator.of(tester.element(find.byType(ListingAiSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-draft-assistant-entry')),
        findsOneWidget);
    await closeUx(tester);
  });

  testWidgets('malformed recovery stays untouched and offers retry or back',
      (tester) async {
    final recovery = Wave6Recovery({
      'editor_version': 11,
      'draft_kind': 'saved',
      'units_per_floor': 'invalid saved shape',
    });
    final original = Map<String, dynamic>.from(recovery.snapshot!);
    final drafts = Wave6Drafts();
    final scope = uxContainer(user: uxUser(type: 'broker'), extra: [
      listingRecoveryStoreProvider.overrideWithValue(recovery),
      listingAccountDraftRepositoryProvider.overrideWithValue(drafts),
      propertyRepositoryProvider.overrideWithValue(Wave6Properties()),
      aiRepositoryProvider.overrideWithValue(Wave6Ai()),
    ]);
    await pumpUx(
        tester, scope, const ListingEditorScreen(startWithAssistant: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('listing-recovery-load-error')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('listing-recovery-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('listing-recovery-back')), findsOneWidget);
    expect(find.byType(ListingAiSheet), findsNothing);
    expect(recovery.snapshot, original);
    expect(drafts.saves, isEmpty);
    await tester.tap(find.byKey(const ValueKey('listing-recovery-retry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('listing-recovery-load-error')),
        findsOneWidget);
    expect(recovery.snapshot, original);
    recovery.snapshot =
        null; // Simulate the stored input being repaired before retry.
    await tester.tap(find.byKey(const ValueKey('listing-recovery-retry')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(ListingAiSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(ListingAiSheet))).pop();
    await tester.pumpAndSettle();
    await closeUx(tester);
  });

  testWidgets('account change during recovery cannot open the assistant',
      (tester) async {
    final auth = UxAuth(uxUser(id: 1, type: 'broker'));
    final recovery = _PausedRecovery();
    final scope = uxContainer(auth: auth, extra: [
      listingRecoveryStoreProvider.overrideWithValue(recovery),
      propertyRepositoryProvider.overrideWithValue(Wave6Properties()),
      aiRepositoryProvider.overrideWithValue(Wave6Ai()),
    ]);
    await pumpUx(
        tester, scope, const ListingEditorScreen(startWithAssistant: true));
    await recovery.requested.future;
    auth.change(uxUser(id: 2, type: 'broker'));
    recovery.release.complete(null);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ListingAiSheet), findsNothing);
    await closeUx(tester);
  });

  testWidgets('account change dismisses an open assistant sheet',
      (tester) async {
    final auth = UxAuth(uxUser(id: 1, type: 'broker'));
    final scope = uxContainer(auth: auth, extra: [
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
      propertyRepositoryProvider.overrideWithValue(Wave6Properties()),
      aiRepositoryProvider.overrideWithValue(Wave6Ai()),
    ]);
    await pumpUx(
        tester,
        scope,
        const ListingEditorScreen(
          startFresh: true,
          startWithAssistant: true,
        ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ListingAiSheet), findsOneWidget);
    auth.change(uxUser(id: 2, type: 'broker'));
    expect(scope.read(authControllerProvider).asData?.value?.id, 2);
    await tester.pumpAndSettle();
    expect(find.byType(ListingAiSheet), findsNothing);
    await closeUx(tester);
  });

  testWidgets('account change blocks an AI request before sheet dismissal',
      (tester) async {
    final auth = UxAuth(uxUser(id: 1, type: 'broker'));
    final ai = _CountingAi();
    final scope = uxContainer(auth: auth, extra: [
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
      propertyRepositoryProvider.overrideWithValue(Wave6Properties()),
      aiRepositoryProvider.overrideWithValue(ai),
    ]);
    await pumpUx(tester, scope, const ListingEditorScreen(
      startFresh: true, startWithAssistant: true,
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ListingAiSheet), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('listing-ai-brief')), 'Synthetic listing');
    await tester.pump();

    auth.change(uxUser(id: 2, type: 'broker'));
    // Tap in the gap before the next frame dismisses the old account's sheet.
    await tester.tap(find.byKey(const ValueKey('listing-ai-prepare')));
    expect(ai.prepareCalls, 0);
    await tester.pumpAndSettle();
    expect(find.byType(ListingAiSheet), findsNothing);
    await closeUx(tester);
  });

  testWidgets('new session with the same account cannot apply an old AI reply',
      (tester) async {
    final auth = UxAuth(uxUser(id: 1, type: 'broker'));
    final ai = _CountingAi()..pendingPrepare = Completer<Map<String, dynamic>>();
    final scope = uxContainer(auth: auth, extra: [
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
      propertyRepositoryProvider.overrideWithValue(Wave6Properties()),
      aiRepositoryProvider.overrideWithValue(ai),
    ]);
    await pumpUx(tester, scope, const ListingEditorScreen(
      startFresh: true, startWithAssistant: true,
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
        find.byKey(const ValueKey('listing-ai-brief')), 'Synthetic listing');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('listing-ai-prepare')));
    expect(ai.prepareCalls, 1);

    auth.change(uxUser(id: 1, type: 'broker'));
    ai.pendingPrepare!.complete({
      'fields': {'type': 'apartment'},
      'copy': {'title': 'Synthetic title', 'description': 'Synthetic copy'},
    });
    await tester.pumpAndSettle();
    expect(find.byType(ListingAiSheet), findsNothing);
    expect(find.byKey(const ValueKey('listing-ai-field-type')), findsNothing);
    await closeUx(tester);
  });

  testWidgets('new session with the same account blocks a request before pop',
      (tester) async {
    final auth = UxAuth(uxUser(id: 1, type: 'broker'));
    final ai = _CountingAi();
    final scope = uxContainer(auth: auth, extra: [
      listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
      propertyRepositoryProvider.overrideWithValue(Wave6Properties()),
      aiRepositoryProvider.overrideWithValue(ai),
    ]);
    await pumpUx(tester, scope, const ListingEditorScreen(
      startFresh: true, startWithAssistant: true,
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
        find.byKey(const ValueKey('listing-ai-brief')), 'Synthetic listing');
    await tester.pump();

    auth.change(uxUser(id: 1, type: 'broker'));
    await tester.tap(find.byKey(const ValueKey('listing-ai-prepare')));
    expect(ai.prepareCalls, 0);
    await tester.pumpAndSettle();
    expect(find.byType(ListingAiSheet), findsNothing);
    await closeUx(tester);
  });
}
