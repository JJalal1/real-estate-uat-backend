import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_query_summary.dart';

void main() {
  for (final largeDark in [false, true]) {
    testWidgets('multi-type summary keeps editable choices and map/budget scope${largeDark ? ' at RTL320 dark2.4' : ''}', (tester) async {
      tester.view.physicalSize = Size(largeDark ? 320 : 412, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var filters = SmartSearchFilters.fromMap({
        'types': ['apartment', 'villa'], 'purpose': 'rent', 'max_price': 200000,
        'south': 15.3, 'west': 44.1, 'north': 15.4, 'east': 44.2,
      });
      final edits = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: largeDark ? Brightness.dark : Brightness.light),
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(
          body: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(largeDark ? 2.4 : 1)),
            child: StatefulBuilder(builder: (context, update) => SingleChildScrollView(
              child: SmartSearchQuerySummary(filters: filters, onEdit: edits.add,
                onRemove: (key) => update(() => filters = filters.without(key))),
            )),
          ),
        )),
      ));
      expect(find.byKey(const ValueKey('smart-chip-type:apartment')), findsOneWidget);
      expect(find.byKey(const ValueKey('smart-chip-type:villa')), findsOneWidget);
      expect(find.text('أو'), findsOneWidget);
      expect(find.text('ابحث عن عقارات'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('smart-chip-edit-type:villa')));
      expect(edits, ['type']);
      await tester.tap(find.byKey(const ValueKey('smart-chip-remove-type:villa')));
      await tester.pump();
      expect(filters.selectedTypes, ['apartment']);
      expect(find.byKey(const ValueKey('smart-chip-type')), findsOneWidget);
      expect(find.byKey(const ValueKey('smart-chip-type:villa')), findsNothing);
      expect(filters.values['max_price'], 200000);
      expect(filters.values['south'], 15.3);
      expect(find.byKey(const ValueKey('smart-chip-map_area')), findsOneWidget);
      expect(find.byKey(const ValueKey('smart-chip-budget')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('smart-chip-remove-type')));
      await tester.pump();
      expect(filters.selectedTypes, isEmpty);
      expect(filters.values['purpose'], 'rent');
      expect(filters.hasMapArea, isTrue);
      expect(find.text('ابحث عن عقارات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
