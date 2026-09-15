import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/design/app_design.dart';

import 'support/design_test_fonts.dart';
import 'support/capture_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadDesignTestFonts);

  testWidgets('tonal button rendered text meets contrast against its surface',
      (tester) async {
    await tester.pumpWidget(_app(
      scale: 1,
      child: Scaffold(
        body: AppButton(
          label: 'للإيجار',
          style: AppButtonStyle.tonal,
          onPressed: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final label = tester.widget<RichText>(find.descendant(
      of: find.text('للإيجار'),
      matching: find.byType(RichText),
    ));
    final material = tester.widget<Material>(find.descendant(
      of: find.byType(FilledButton),
      matching: find.byType(Material),
    ));
    final foreground = label.text.style!.color!.computeLuminance();
    final background = material.color!.computeLuminance();
    final contrast = foreground > background
        ? (foreground + 0.05) / (background + 0.05)
        : (background + 0.05) / (foreground + 0.05);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });

  for (final width in [320.0, 360.0, 412.0, 600.0]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('Arabic foundation $width / $scale preserves every action',
          (tester) async {
        _viewport(tester, Size(width, 915));
        final captureKey = GlobalKey();
        var searches = 0;
        var filters = 0;
        var sections = 0;
        await tester.pumpWidget(_app(
          scale: scale,
          child: RepaintBoundary(
            key: captureKey,
            child: Scaffold(
              body: SingleChildScrollView(
                child: AppContentFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppPageHeading(
                        eyebrow: 'عقارات حولك',
                        title: 'اعثر على المساحة التي تناسبك',
                        subtitle: 'اختبار مكونات معزول — لا يمثل بيانات عقارات حقيقية',
                      ),
                      AppSearchEntry(
                        label: 'ابحث باسم المنطقة أو وصف العقار',
                        onTap: () => searches++,
                        onFilter: () => filters++,
                      ),
                      const SizedBox(height: AppSpacing.s24),
                      AppSectionCard(
                        title: 'تفاصيل العقار والمعلومات المتاحة',
                        subtitle: 'صنعاء · رقم مرجعي ABC-123',
                        actionLabel: 'عرض جميع التفاصيل والمواصفات',
                        onAction: () => sections++,
                        child: const AppPropertyFacts(facts: [
                          AppPropertyFact(
                            icon: Icons.square_foot,
                            label: '420 م² — مساحة الأرض والمبنى حسب الإعلان',
                          ),
                          AppPropertyFact(icon: Icons.bed_outlined, label: '5 غرف'),
                        ]),
                      ),
                      const SizedBox(height: AppSpacing.s24),
                      const AppPropertyPrice(price: '12,500,000', currency: 'YER'),
                      const SizedBox(height: AppSpacing.s24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(FittedBox), findsNothing);
        final search = find.text('ابحث باسم المنطقة أو وصف العقار');
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.tap(search);
        final filter = find.byTooltip('تصفية النتائج');
        await tester.tap(filter);
        expect(searches, 1);
        expect(filters, 1);
        expect(tester.getSize(find.byType(AppIconButton)).shortestSide,
            greaterThanOrEqualTo(AppSizes.touchTarget));
        final action = find.text('عرض جميع التفاصيل والمواصفات');
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        expect(sections, 1);
        final price = find.byType(AppPropertyPrice);
        await tester.ensureVisible(price);
        await tester.pumpAndSettle();
        expect(Directionality.of(tester.element(price)), TextDirection.rtl);
        expect(tester.takeException(), isNull);

        // Artifacts are evidence of real Flutter rendering, not replacement
        // golden assertions or a claim of authenticated Android screen QA.
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 3000));
        await tester.pumpAndSettle();
        await captureDesign(tester, captureKey, 'foundation-${width.toInt()}-$scale');
      });
    }
  }

  testWidgets('short viewport keeps large Arabic retry reachable by scrolling',
      (tester) async {
    _viewport(tester, const Size(320, 280));
    var retries = 0;
    await tester.pumpWidget(_app(
      scale: 2.4,
      child: Scaffold(
        body: AppErrorState(
          title: 'تعذر تحميل المعلومات المطلوبة الآن',
          message: 'تحقق من الاتصال ثم حاول مرة أخرى للاطلاع على بيانات العقار.',
          onRetry: () => retries++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final retry = find.text('إعادة المحاولة');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback embedded in a list leaves scrolling to its parent',
      (tester) async {
    _viewport(tester, const Size(320, 568));
    await tester.pumpWidget(_app(
      scale: 2.4,
      child: const Scaffold(
        body: SingleChildScrollView(
          child: AppEmptyState(
            title: 'لا توجد نتائج مطابقة',
            message: 'يمكن تعديل معايير البحث والمحاولة مرة أخرى.',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final inner = find.descendant(
      of: find.byType(AppEmptyState),
      matching: find.byType(Scrollable),
    );
    expect(tester.state<ScrollableState>(inner).position.maxScrollExtent, 0,
        reason: 'The inner viewport must not compete with its enclosing list.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sliver feedback supports intrinsic sizing and retry interaction',
      (tester) async {
    _viewport(tester, const Size(320, 280));
    var retries = 0;
    await tester.pumpWidget(_app(
      scale: 2.4,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s48)),
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorState(
                message: 'تعذر تحميل المحادثات. تحقق من الاتصال ثم حاول مرة أخرى.',
                onRetry: () => retries++,
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final retry = find.text('إعادة المحاولة');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading copy can scroll in a short large-text viewport',
      (tester) async {
    _viewport(tester, const Size(320, 180));
    await tester.pumpWidget(_app(
      scale: 2.4,
      child: const Scaffold(
        body: AppLoadingState(label: 'جارٍ تحميل معلومات العقار والبيانات المرتبطة به...'),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.textContaining('جارٍ تحميل معلومات'));
    // The progress indicator intentionally animates continuously.
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app({required double scale, required Widget child}) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: child,
    );
