import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/presentation/add_property_wizard_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_ai_sheet.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';

import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show editorSnapshot, finishWave6, pumpWave6;

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
}
