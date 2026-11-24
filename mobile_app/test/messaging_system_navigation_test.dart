import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/core/theme/messaging_system_navigation.dart';

void main() {
  testWidgets('Android messages navigation follows the system appearance', (tester) async {
    final platform = tester.binding.platformDispatcher;
    platform.platformBrightnessTestValue = Brightness.light;
    addTearDown(platform.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
      darkTheme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(viewPadding: const EdgeInsets.only(bottom: 24)),
        child: child!,
      ),
      home: const MessagingSystemNavigation(child: Scaffold(body: Text('الرسائل'))),
    ));

    final overlay = find.byWidgetPredicate((widget) =>
        widget is AnnotatedRegion<SystemUiOverlayStyle> &&
        widget.value.systemNavigationBarContrastEnforced == false);
    SystemUiOverlayStyle style() => tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(overlay).value;

    expect(style().systemNavigationBarColor, Colors.white);
    expect(style().systemNavigationBarIconBrightness, Brightness.dark);
    expect(tester.getSize(overlay).height, 24);

    platform.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    expect(style().systemNavigationBarColor, AppTheme.dark.colorScheme.surface);
    expect(style().systemNavigationBarIconBrightness, Brightness.light);
    expect(tester.getSize(overlay).height, 24);
    expect(find.text('الرسائل'), findsOneWidget);
  });
}
