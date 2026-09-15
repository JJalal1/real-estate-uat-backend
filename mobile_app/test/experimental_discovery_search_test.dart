import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';
import 'package:real_estate_mobile/features/map/presentation/discovery_search_sheet.dart';

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
    testWidgets('search with keyboard ${viewport.$1} / ${viewport.$2} submits unchanged input',
        (tester) async {
      String? result;
      final captureKey = GlobalKey();
      await _open(tester,
        size: viewport.$1,
        scale: viewport.$2,
        inset: viewport.$1.height < 300 ? 100 : 180,
        captureKey: captureKey,
        initial: '  صنعاء، شارع حدة ABC-123  ',
        onResult: (value) => result = value,
      );
      expect(tester.takeException(), isNull);
      final submit = find.text('عرض النتائج');
      await Scrollable.ensureVisible(tester.element(submit), alignment: 0.5);
      await tester.pumpAndSettle();
      await captureDesign(tester, captureKey,
          'discovery-search-${viewport.$1.width.toInt()}-${viewport.$1.height.toInt()}-${viewport.$2}');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(result, '  صنعاء، شارع حدة ABC-123  ',
          reason: 'Normalization remains in the existing map handler.');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search suggestions retain case-insensitive matching and six-result limit',
      (tester) async {
    String? result;
    await _open(tester,
      initial: 'abC',
      suggestions: List.generate(7, (index) => 'ABC-${index + 1}'),
      onResult: (value) => result = value,
    );
    expect(find.byType(AppListRow), findsNWidgets(6));
    expect(find.text('ABC-7'), findsNothing);
    final last = find.text('ABC-6');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(result, 'ABC-6');
  });

  testWidgets('recent search is hidden while typing and returns its original value',
      (tester) async {
    String? result;
    const recent = 'صنعاء، شارع طويل بالقرب من جولة المصباحي';
    await _open(tester,
      initial: 'حدة',
      recent: const [recent],
      onResult: (value) => result = value,
    );
    expect(find.text('بحثت مؤخراً'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('بحثت مؤخراً'), findsOneWidget);
    await tester.ensureVisible(find.text(recent));
    await tester.pumpAndSettle();
    await tester.tap(find.text(recent));
    await tester.pumpAndSettle();
    expect(result, recent);
  });

  testWidgets('clear returns the existing empty-string result', (tester) async {
    String? result;
    await _open(tester, initial: 'حدة', onResult: (value) => result = value);
    await tester.ensureVisible(find.text('مسح البحث'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مسح البحث'));
    await tester.pumpAndSettle();
    expect(result, '');
  });

  testWidgets('keyboard search action returns the entered query', (tester) async {
    String? result;
    await _open(tester, onResult: (value) => result = value);
    await tester.enterText(find.byType(TextField), 'تعز');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(result, 'تعز');
  });
}

Future<void> _open(WidgetTester tester, {
  required ValueChanged<String?> onResult,
  Size size = const Size(412, 915),
  double scale = 1,
  double inset = 0,
  String initial = '',
  List<String> suggestions = const [],
  List<String> recent = const [],
  GlobalKey? captureKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => RepaintBoundary(
      key: captureKey,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: inset),
        ),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
    ),
    home: Builder(builder: (context) => Scaffold(
      body: Center(child: TextButton(
        onPressed: () async => onResult(await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => DiscoverySearchSheet(
            initialValue: initial,
            suggestions: suggestions,
            recentSearches: recent,
          ),
        )),
        child: const Text('فتح البحث'),
      )),
    )),
  ));
  await tester.tap(find.text('فتح البحث'));
  await tester.pumpAndSettle();
}
