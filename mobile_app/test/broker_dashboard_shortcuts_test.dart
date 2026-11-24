import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/local/listing_recovery_store.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/broker/data/broker_repository.dart';
import 'package:real_estate_mobile/features/broker/presentation/broker_dashboard_shortcuts.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/add_property_wizard_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/router/app_deep_links.dart';

import 'broker_experience_ui_test.dart' show BrokerTestAuth, BrokerTestRepository;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot, finishWave6, pumpWave6;

class _Listings extends Wave6Properties {
  int reads = 0;

  @override
  Future<List<PropertyDetails>> myListings() async {
    reads++;
    return [
      _property(11),
      _property(12, status: 'draft'),
      _property(13, availability: 'sold'),
      _property(14, owner: false),
    ];
  }

  PropertyDetails _property(int id, {String status = 'published',
    String availability = 'available', bool owner = true}) => PropertyDetails.fromJson({
      'id': id,
      'title': 'عقار الاختبار $id',
      'type': 'apartment',
      'purpose': 'sale',
      'price': 9000000,
      'currency': 'YER',
      'status': status,
      'availability_status': availability,
      'review_status': status == 'draft' ? 'draft' : 'approved',
      'is_owner': owner,
    });
}

void main() {
  testWidgets('direct resume opens the newer account step without restarting AI',
      (tester) async {
    final key = newListingDraftKey();
    final draft = ListingAccountDraft(
      key: key,
      revision: 5,
      updatedAt: DateTime.utc(2026, 11, 24, 10),
      payload: {
        ...editorSnapshot(),
        'editor_version': 11,
        'draft_kind': 'saved',
        'entry_method': 'assistant',
        'step': 2,
      },
    );
    final drafts = Wave6Drafts()..drafts[key] = draft;
    final device = Wave6Recovery({
      ...editorSnapshot(),
      'draft_key': key,
      'saved_at': '2026-11-24T09:00:00Z',
      'server_revision': 4,
      'step': 1,
    });
    await pumpWave6(tester, const AddPropertyWizardScreen(resumeLatest: true),
      drafts: drafts, recovery: device);
    expect(find.byType(ListingAiSheet), findsNothing);
    expect(find.text('3/4'), findsOneWidget);
    expect(tester.widget<ListingEditorScreen>(find.byType(ListingEditorScreen)).accountDraft, draft);
    await finishWave6(tester);
  });

  testWidgets('direct resume preserves a newer unsynced device step',
      (tester) async {
    final key = newListingDraftKey();
    final draft = ListingAccountDraft(
      key: key,
      revision: 3,
      updatedAt: DateTime.utc(2026, 11, 24, 9),
      payload: {...editorSnapshot(), 'step': 1},
    );
    final drafts = Wave6Drafts()..drafts[key] = draft;
    final device = Wave6Recovery({
      ...editorSnapshot(),
      'draft_key': key,
      'saved_at': '2026-11-24T10:00:00Z',
      'server_revision': 3,
      'step': 3,
    });
    await pumpWave6(tester, const AddPropertyWizardScreen(resumeLatest: true),
      drafts: drafts, recovery: device);
    expect(find.text('4/4'), findsOneWidget);
    expect(tester.widget<ListingEditorScreen>(find.byType(ListingEditorScreen)).localRecovery,
      device.snapshot);
    await finishWave6(tester);
  });

  testWidgets('shortcuts hide absent drafts and share only available owned listings',
      (tester) async {
    final listings = _Listings();
    const channel = MethodChannel('real_estate/share');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => BrokerTestAuth()),
        brokerRepositoryProvider.overrideWithValue(BrokerTestRepository()),
        propertyRepositoryProvider.overrideWithValue(listings),
        listingRecoveryStoreProvider.overrideWithValue(Wave6Recovery()),
        listingAccountDraftRepositoryProvider.overrideWithValue(Wave6Drafts()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: BrokerDashboardShortcuts()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('broker-shortcut-resume-draft')), findsNothing);
    expect(listings.reads, 0);
    await tester.tap(find.byKey(const ValueKey('broker-shortcut-share-listing')));
    await tester.pumpAndSettle();
    expect(listings.reads, 1);
    for (final id in [12, 13, 14]) {
      expect(find.byKey(ValueKey('broker-share-listing-$id')), findsNothing);
    }
    await tester.tap(find.byKey(const ValueKey('broker-share-listing-11')));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'shareText');
    expect(calls.single.arguments['text'], contains(propertyPublicShareLink(11).toString()));
  });
}
