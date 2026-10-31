import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/property_schema.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, finishWave6;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);

  test('automatic save starts at 50 percent and preserves a started draft', () {
    expect(DynamicPropertySchema.canBeginAutomaticSave(49), isFalse);
    expect(DynamicPropertySchema.canBeginAutomaticSave(50), isTrue);
    expect(DynamicPropertySchema.canBeginAutomaticSave(51), isTrue);
    final incomplete = <String, dynamic>{
      'editor_version': 11, 'type': 'apartment', 'purpose': 'sale',
      'fields': {'title': 'Synthetic apartment'},
    };
    expect(DynamicPropertySchema.draftProgress(incomplete), lessThan(50));
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

  testWidgets('previous recovery keeps saving after progress falls below 50', (tester) async {
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
    expect(recovery.writes, greaterThan(0));
    expect(drafts.saves, isNotEmpty);
    await finishWave6(tester);
  });
}
