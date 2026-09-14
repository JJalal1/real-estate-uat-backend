import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/map/presentation/discovery_filter_panel.dart';

import 'support/design_test_fonts.dart';
import 'support/capture_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);

  for (final size in [const Size(320, 568), const Size(412, 915)]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('discovery entry ${size.width} / $scale preserves filter actions',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final captureKey = GlobalKey();
        final purposes = <String?>[];
        final types = <String?>[];
        var searches = 0;
        var filters = 0;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
          home: RepaintBoundary(
            key: captureKey,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsetsDirectional.all(AppSpacing.s16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height * 0.4),
                  child: SingleChildScrollView(
                    child: DiscoveryFilterPanel(
                      purpose: 'rent',
                      type: 'apartment',
                      filterCount: 2,
                      searchText: 'صنعاء، حدة',
                      onPurpose: purposes.add,
                      onType: types.add,
                      onSearch: () => searches++,
                      onMore: () => filters++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('صنعاء، حدة'));
        await tester.tap(find.byTooltip('المزيد من الفلاتر (2)'));
        expect(searches, 1);
        expect(filters, 1);

        for (final label in ['للإيجار', 'للإيجار', 'للبيع']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
        }
        expect(purposes, ['rent', 'rent', 'sale'],
            reason: 'The parent retains its original toggle semantics.');
        for (final label in ['الكل', 'شقة', 'فيلا', 'منزل', 'أرض', 'محل', 'مكتب']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
        }
        expect(types, [null, 'apartment', 'villa', 'house', 'land', 'shop', 'office']);
        await tester.ensureVisible(find.text('المزيد (2)'));
        await tester.tap(find.text('المزيد (2)'));
        expect(filters, 2);
        expect(tester.takeException(), isNull);

        // Capture the initial panel and its first RTL category after scrolling.
        await tester.ensureVisible(find.text('الكل'));
        await tester.ensureVisible(find.text('صنعاء، حدة'));
        await tester.pumpAndSettle();
        await captureDesign(
          tester,
          captureKey,
          'discovery-entry-${size.width.toInt()}-$scale',
        );
      });
    }
  }

  test('map retains default navigation and gesture wiring', () {
    // Runtime contract tests cover the API/domain layer; these anchors keep
    // presentation extraction from disconnecting the existing entry points.
    final source = File('lib/features/map/presentation/map_screen.dart').readAsStringSync();
    expect(source, contains('bool _listMode = false;'));
    expect(source, contains('onPurpose: _setQuickPurpose'));
    expect(source, contains('onType: _setQuickType'));
    expect(source, contains('onMore: _showFilters'));
    expect(source, contains('Positioned.fill(child: _buildMap())'));
    expect(source, contains('onPanStart: _startAreaStroke'));
    expect(source, contains('onPanUpdate: _updateAreaStroke'));
    expect(source, contains('onPanEnd: _finishAreaStroke'));
  });
}
