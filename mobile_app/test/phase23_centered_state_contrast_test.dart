import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance(), b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  const message = 'شرح حالة اصطناعية واضح لقراءة المحتوى والمتابعة.';

  for (final dark in [false, true]) {
    for (final error in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'} ${error ? 'error' : 'empty'} helper text meets normal-text contrast', (tester) async {
        final theme = dark ? AppTheme.dark : AppTheme.light;
        await tester.pumpWidget(MaterialApp(theme: theme,
          home: Directionality(textDirection: TextDirection.rtl,
            child: Scaffold(body: error
              ? AppErrorState(message: message, onRetry: () {})
              : const AppEmptyState(title: 'لا توجد بيانات', message: message)))));
        await tester.pumpAndSettle();

        final text = tester.widget<Text>(find.text(message));
        final context = tester.element(find.text(message));
        final foreground = text.style?.color ?? DefaultTextStyle.of(context).style.color!;
        final background = Theme.of(context).scaffoldBackgroundColor;
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5),
          reason: 'Normal-size helper text must remain readable on its actual page background.');
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [320.0, 412.0]) {
      testWidgets('${dark ? 'dark' : 'light'} error retry remains reachable at width $width and scale 2.4', (tester) async {
        tester.view.physicalSize = Size(width, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var retries = 0;
        await tester.pumpWidget(MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.4)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!)),
          home: Scaffold(body: AppErrorState(
            message: message, onRetry: () => retries++))));
        await tester.pumpAndSettle();

        final retry = find.text('إعادة المحاولة');
        await tester.ensureVisible(retry);
        await tester.pumpAndSettle();
        expect(retry.hitTestable(), findsOneWidget);
        await tester.tap(retry.hitTestable());
        await tester.pump();
        expect(retries, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
