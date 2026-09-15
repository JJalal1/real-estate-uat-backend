import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/map/presentation/discovery_filter_panel.dart';
import 'package:real_estate_mobile/features/map/presentation/discovery_map_dock.dart';

import 'support/capture_design.dart';
import 'support/design_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDesignTestFonts);

  for (final viewport in [
    (const Size(320, 568), 1.0),
    (const Size(320, 568), 2.4),
    (const Size(412, 915), 2.4),
    (const Size(600, 280), 2.4),
  ]) {
    testWidgets('map dock ${viewport.$1} / ${viewport.$2} retains all actions',
        (tester) async {
      final size = viewport.$1;
      final mapMode = size.height > 300;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureKey = GlobalKey();
      final canvasKey = GlobalKey();
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(viewport.$2)),
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: canvasKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => calls.add('map'),
                    child: const ColoredBox(color: Color(0xFFEFF4F0)),
                  ),
                ),
                PositionedDirectional(
                  top: AppSpacing.s8,
                  start: AppSpacing.s8,
                  end: AppSpacing.s8,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: size.height * AppLayout.mapFilterMaxHeightFraction),
                    child: SingleChildScrollView(
                      child: DiscoveryFilterPanel(
                        purpose: 'rent',
                        type: 'apartment',
                        filterCount: 0,
                        searchText: '',
                        onPurpose: (_) {},
                        onType: (_) {},
                        onSearch: () {},
                        onMore: () {},
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(AppSpacing.s8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * AppLayout.mapDockMaxHeightFraction,
                          ),
                          child: DiscoveryMapDock(
                            controls: AppButton(label: 'حفظ البحث', onPressed: () => calls.add('save')),
                            error: AppSurface(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const AppInlineMessage(message: 'تعذر تحميل العقارات', tone: AppStatusTone.error),
                                  AppButton(label: 'إعادة', onPressed: () => calls.add('retry')),
                                ],
                              ),
                            ),
                            preview: DiscoveryPropertyPreview(
                              title: 'عقار مختار بعنوان عربي طويل في صنعاء ومنطقة حدة',
                              price: '12,500,000',
                              currency: 'YER',
                              location: 'صنعاء، حدة — مبنى ABC-123',
                              favorite: false,
                              onFavorite: () => calls.add('favorite'),
                              onDetails: () => calls.add('details'),
                              onClose: () => calls.add('close'),
                            ),
                            message: const AppInlineMessage(message: 'تم تحديث منطقة البحث'),
                            modeBar: DiscoveryModeBar(
                              countText: 'تعذر الاتصال',
                              mapMode: mapMode,
                              onSwitch: () => calls.add('switch'),
                              onAdd: () => calls.add('add'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(canvasKey)), Offset.zero & size);
      await tester.tapAt(Offset(20, size.height * 0.45));
      expect(calls, ['map'], reason: 'Overlay must not absorb exposed map input.');
      for (final target in [
        find.text('حفظ البحث'),
        find.text('إعادة'),
        find.text('عقار مختار بعنوان عربي طويل في صنعاء ومنطقة حدة'),
        find.byTooltip('إغلاق'),
        find.text('حفظ في المفضلة'),
        find.text(mapMode ? 'قائمة' : 'خريطة'),
        find.text('إضافة'),
      ]) {
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(target);
      }
      expect(calls, ['map', 'save', 'retry', 'details', 'close', 'favorite', 'switch', 'add']);
      expect(tester.takeException(), isNull);
      final addLabel = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.text('إضافة'), matching: find.byType(RichText),
      ));
      expect(addLabel.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 5)),
          hasLength(1), reason: 'The Arabic action word must not split across lines.');
      await captureDesign(tester, captureKey, 'map-mode-${size.width.toInt()}-${size.height.toInt()}-${viewport.$2}');
      await tester.ensureVisible(find.text('عقار مختار بعنوان عربي طويل في صنعاء ومنطقة حدة'));
      await tester.pumpAndSettle();
      await captureDesign(tester, captureKey, 'map-dock-${size.width.toInt()}-${size.height.toInt()}-${viewport.$2}');
    });
  }
}
