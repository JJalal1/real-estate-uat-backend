import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_location_picker_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in <String, String>{
      'NotoSansArabic': 'assets/fonts/NotoSansArabic-Regular.ttf',
      'PrimaryFont': 'assets/ebroker/fonts/Manrope-Regular.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.4]) {
      for (final state in ['ready', 'loading', 'error', 'resolving']) {
        testWidgets('location controls stay separate and reachable $width/$scale/$state', (tester) async {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          addTearDown(semantics.dispose);
          var locations = 0, confirmations = 0, settings = 0;
          final enabled = state == 'ready' || state == 'error';
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light, locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(bottom: 24)), child: child!),
            home: Scaffold(body: Align(alignment: Alignment.bottomCenter,
              child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                child: PropertyLocationPickerControls(maxHeight: 604,
                  onLocate: enabled ? () { locations++; } : null,
                  onConfirm: enabled ? () { confirmations++; } : null,
                  onOpenSettings: state == 'error' ? () { settings++; } : null,
                  message: state == 'error'
                    ? 'إذن الموقع مرفوض نهائيًا. افتح الإعدادات أو اختر النقطة يدويًا على الخريطة.'
                    : state == 'resolving' ? 'ثبّتنا النقطة. نجلب اقتراح العنوان…' : null,
                  resolving: state == 'resolving',
                )))),
          ));
          await tester.pump();
          final locate = find.byKey(const ValueKey('property-picker-current-location'));
          final card = find.byKey(const ValueKey('property-picker-confirmation-card'));
          expect(tester.getRect(locate).bottom + 12, lessThanOrEqualTo(tester.getRect(card).top + .01));
          await tester.ensureVisible(locate);
          await tester.pump(const Duration(milliseconds: 300));
          final locateRect = tester.getRect(locate);
          expect(locateRect.top, greaterThanOrEqualTo(0));
          expect(locateRect.bottom, lessThanOrEqualTo(640));
          expect(find.bySemanticsLabel('موقعي الحالي'), findsOneWidget);
          if (enabled) {
            await tester.tap(locate);
            expect(locations, 1);
          } else {
            expect(tester.widget<FloatingActionButton>(locate).onPressed, isNull);
          }
          final confirm = find.text(state == 'resolving' ? 'جارٍ قراءة العنوان…' : 'تأكيد هذا الموقع');
          await tester.ensureVisible(confirm);
          await tester.pump(const Duration(milliseconds: 300));
          final confirmRect = tester.getRect(confirm);
          expect(confirmRect.top, greaterThanOrEqualTo(0));
          expect(confirmRect.bottom, lessThanOrEqualTo(640));
          if (enabled) {
            await tester.tap(confirm);
            expect(confirmations, 1);
          }
          if (state == 'error') {
            final action = find.text('فتح إعدادات الإذن');
            await tester.ensureVisible(action);
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(action);
            expect(settings, 1);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
