import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';

void main() {
  testWidgets('AppNavigationBar keeps labels visible in RTL at large text scale',
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
    expect(find.text('الرسائل'), findsOneWidget);
    expect(find.text('المعاينات'), findsOneWidget);
    expect(find.text('حسابي'), findsOneWidget);
    expect(find.byType(FittedBox), findsNothing);
    await tester.tap(find.text('الرسائل'));
    await tester.pumpAndSettle();
    expect(selected, 1);
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
    expect(find.text('12,500,000'), findsOneWidget);
    expect(find.text('YER'), findsOneWidget);
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
