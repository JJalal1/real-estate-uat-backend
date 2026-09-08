import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';

const _roleLabels = <String, List<String>>{
  'anonymous': ['العقارات', 'حسابي'],
  'regular': ['العقارات', 'الرسائل', 'المعاينات', 'حسابي'],
  'advertiser': ['العقارات', 'إعلاناتي', 'الرسائل', 'المعاينات', 'حسابي'],
  'agent': ['لوحة الدعم', 'الوارد', 'مهامي', 'الرسائل', 'حسابي'],
  'manager': ['لوحة الدعم', 'الأعمال', 'الفريق', 'حسابي'],
  'platform': ['لوحة الإدارة', 'المراجعات', 'المستخدمون', 'المنصة', 'حسابي'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Use the shipped Arabic font, not Ahem, for realistic label wrapping.
    final loader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
    await loader.load();
  });

  for (final role in _roleLabels.entries) {
    for (final size in [const Size(320, 568), const Size(412, 915)]) {
      for (final scale in [1.0, 1.8, 2.4]) {
        testWidgets(
          '${role.key} ${size.width} scale $scale leaves a visible interactive page',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            var selected = 0;
            var bodyTaps = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    padding: const EdgeInsets.only(top: 24, bottom: 24),
                    viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: child!,
                  ),
                ),
                home: StatefulBuilder(
                  builder: (context, setState) => Scaffold(
                    body: IndexedStack(
                      index: selected,
                      children: List.generate(
                        role.value.length,
                        (index) => SizedBox.expand(
                          key: ValueKey('page-$index'),
                          child: Center(
                            child: TextButton(
                              onPressed: () => bodyTaps++,
                              child: Text('صفحة ${index + 1}'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomNavigationBar: AppNavigationBar(
                      destinations: role.value
                          .map((label) => AppNavDestination(
                                label: label,
                                icon: Icons.home_outlined,
                              ))
                          .toList(growable: false),
                      selectedIndex: selected,
                      onSelected: (index) => setState(() => selected = index),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final nav = tester.getRect(find.byType(AppNavigationBar));
            expect(nav.height, lessThan(size.height * 0.45),
                reason: 'The bottom bar must not consume the body viewport.');
            expect(nav.bottom, closeTo(size.height, 0.1));
            expect(tester.getSize(find.byKey(const ValueKey('page-0'))).height,
                greaterThan(size.height * 0.5));

            // Presence/selection alone passed with the old full-screen bar.
            // Require visible, hit-testable page content after EVERY selection.
            for (var index = 0; index < role.value.length; index++) {
              await tester.tap(find.text(role.value[index]));
              await tester.pumpAndSettle();
              expect(selected, index);
              final action = find.text('صفحة ${index + 1}').hitTestable();
              expect(action, findsOneWidget);
              await tester.tap(action);
              expect(bodyTaps, index + 1);
              expect(tester.takeException(), isNull);
            }

            final firstLabel = tester.getCenter(find.text(role.value.first));
            final lastLabel = tester.getCenter(find.text(role.value.last));
            expect(firstLabel.dx, greaterThan(lastLabel.dx),
                reason: 'Destination order must remain RTL.');
          },
        );
      }
    }
  }
}
