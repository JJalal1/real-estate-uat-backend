import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';

void main() {
  testWidgets('AppNavigationBar keeps full-size selected text and named RTL destinations at large scale',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: const SizedBox.expand(),
                bottomNavigationBar: AppNavigationBar(
                  destinations: const [
                    AppNavDestination(label: 'العقارات', icon: Icons.home_work_outlined),
                    AppNavDestination(label: 'الرسائل', icon: Icons.chat_bubble_outline),
                    AppNavDestination(label: 'المعاينات', icon: Icons.calendar_month_outlined),
                    AppNavDestination(label: 'حسابي', icon: Icons.person_outline),
                  ],
                  selectedIndex: selected,
                  onSelected: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('العقارات'), findsOneWidget);
    for (final label in ['العقارات', 'الرسائل', 'المعاينات', 'حسابي']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    // SVG rendering scales its vector canvas with a FittedBox internally.
    // Navigation text must never be fitted or shrink the user's text scale.
    expect(find.ancestor(
      of: find.descendant(of: find.byType(AppNavigationBar), matching: find.byType(Text)),
      matching: find.byType(FittedBox)), findsNothing);
    await tester.tap(find.byTooltip('الرسائل'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('الرسائل'), findsOneWidget);
    final selectedText = tester.element(find.text('الرسائل'));
    expect(MediaQuery.textScalerOf(selectedText).scale(12), closeTo(21.6, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPropertyCard preserves title price location and facts',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: AppPropertyCard(
                title: 'فيلا عائلية واسعة بعنوان عربي طويل لاختبار التفاف النص',
                price: '12,500,000',
                currency: 'YER',
                location: 'صنعاء، شارع حدة، بالقرب من جولة المصباحي',
                purposeLabel: 'للبيع',
                facts: const [
                  AppPropertyFact(icon: Icons.square_foot, label: '420 م²'),
                  AppPropertyFact(icon: Icons.bed_outlined, label: '5 غرف'),
                ],
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('فيلا عائلية'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text &&
            widget.textSpan?.toPlainText().contains('١٢٬٥٠٠٬٠٠٠ ريال') == true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('صنعاء'), findsOneWidget);
    expect(find.text('420 م²'), findsOneWidget);
    expect(find.text('5 غرف'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback primitives expose retry and unavailable copy',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AppErrorState(
              message: 'حدث خطأ في الاتصال',
              onRetry: () => retried = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('إعادة المحاولة'));
    expect(retried, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AppUnavailableState()),
        ),
      ),
    );
    expect(find.text('هذا العقار غير متاح حالياً'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
