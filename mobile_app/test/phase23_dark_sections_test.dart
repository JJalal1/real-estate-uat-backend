import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_screen_sections.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance(), b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 412.0]) {
      testWidgets('informational panel remains readable in ${dark ? 'dark' : 'light'} at $width', (tester) async {
        final theme = dark ? AppTheme.dark : AppTheme.light;
        await tester.pumpWidget(MaterialApp(theme: theme, home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: const TextScaler.linear(2.4)),
          child: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SingleChildScrollView(
            child: SizedBox(width: width, child: const EbrokerSectionPanel(title: 'حول العقار',
              child: Text('وصف تجريبي واضح لاختبار التباين في الثيمين.')))))))));
        await tester.pumpAndSettle();
        final panel = find.byType(EbrokerSectionPanel);
        final box = tester.widget<Container>(find.descendant(of: panel, matching: find.byType(Container)).first);
        final decoration = box.decoration! as BoxDecoration;
        final title = tester.widget<Text>(find.text('حول العقار'));
        expect(decoration.color, theme.colorScheme.surface);
        expect(_contrast(title.style!.color!, decoration.color!), greaterThanOrEqualTo(4.5));
        final body = tester.element(find.text('وصف تجريبي واضح لاختبار التباين في الثيمين.'));
        expect(_contrast(DefaultTextStyle.of(body).style.color!, decoration.color!), greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('compact advertiser card shares the dark surface and readable text', (tester) async {
    final theme = AppTheme.dark;
    await tester.pumpWidget(MaterialApp(theme: theme, home: const Scaffold(body: EbrokerAdvertiserCard(
      name: 'معلن تجريبي', identity: 'دلال', rating: 4.8, ratingCount: 5, verified: true,
      onTap: _noop, compact: true))));
    await tester.pumpAndSettle();
    final surface = tester.widget<Material>(find.descendant(of: find.byType(EbrokerAdvertiserCard), matching: find.byType(Material)).first);
    expect(surface.color, theme.colorScheme.surface);
    final name = tester.widget<Text>(find.text('معلن تجريبي'));
    expect(_contrast(name.style!.color!, surface.color!), greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
