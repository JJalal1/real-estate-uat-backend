import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/map/presentation/discovery_map_dock.dart';
import 'package:real_estate_mobile/features/map/presentation/discovery_results_layout.dart';

import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);
  for (final size in [const Size(320, 568), const Size(412, 915), const Size(600, 280)]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('results $size / $scale retain lazy scrolling and sort actions', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var sort = 0;
        var filters = 0;
        final changes = <int>[];
        final built = <int>{};
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
          home: StatefulBuilder(builder: (context, update) => Scaffold(
            appBar: AppBar(title: const Text('العقارات')),
            bottomNavigationBar: DiscoveryModeBar(
              countText: '40 نتيجة', mapMode: false, onSwitch: () {}, onAdd: () {},
            ),
            body: DiscoveryResultsLayout(
              header: DiscoverySortBar(
                sortMode: sort, filterCount: 2,
                onSort: (value) { changes.add(value); update(() => sort = value); },
                onFilters: () => filters++,
              ),
              results: ListView.builder(
                itemCount: 40,
                itemExtent: 96,
                itemBuilder: (context, index) {
                  built.add(index);
                  return Center(child: Text('عقار $index'));
                },
              ),
            ),
          )),
        ));
        await tester.pumpAndSettle();
        expect(built.length, lessThan(40), reason: 'Results must remain lazy.');
        for (final label in ['السعر', 'الأقرب', 'الأحدث']) {
          final chip = find.widgetWithText(FilterChip, label);
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
        }
        expect(changes, [1, 2, 0], reason: 'Selecting the current sort must not deselect it.');
        final filter = find.text('تصفية (2)');
        await tester.ensureVisible(filter);
        await tester.pumpAndSettle();
        await tester.tap(filter);
        expect(filters, 1);
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -800));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('عقار 39'), 400,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
        );
        await tester.pumpAndSettle();
        expect(find.text('عقار 39'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
