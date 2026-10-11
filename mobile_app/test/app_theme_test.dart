import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';

void main() {
  test('light theme implements the accepted Material role contract', () {
    final theme = AppTheme.light;
    final scheme = theme.colorScheme;
    expect(theme.useMaterial3, isTrue);
    expect(scheme.brightness, Brightness.light);
    final roles = <(Color, int)>[
      (scheme.primary, 0xFF087C7C),
      (scheme.primaryContainer, 0xFFE6F2F2),
      (scheme.onPrimaryContainer, 0xFF065858),
      (scheme.secondary, 0xFF087C7C),
      (scheme.secondaryContainer, 0xFFE6F2F2),
      (scheme.onSecondaryContainer, 0xFF065858),
      (scheme.onSurface, 0xFF4D5454),
      (scheme.onSurfaceVariant, 0x99000000),
      (scheme.surfaceContainerLow, 0xFFFAFAFA),
      (scheme.surfaceContainer, 0xFFF2F2F2),
      (scheme.surfaceContainerHigh, 0xFFEEEEEE),
      (scheme.surfaceContainerHighest, 0xFFE9E9E9),
      (scheme.outline, 0xFF909595),
      (scheme.outlineVariant, 0x99EEEEEE),
      (scheme.error, 0xFFB3261E),
      (scheme.errorContainer, 0xFFF9DEDC),
      (scheme.onErrorContainer, 0xFF410E0B),
      (scheme.inverseSurface, 0xFF2F3434),
    ];
    for (final (actual, expected) in roles) {
      expect(actual, Color(expected));
    }
    for (final color in [
      scheme.onPrimary,
      scheme.onSecondary,
      scheme.surface,
      scheme.onError,
      scheme.onInverseSurface,
    ]) {
      expect(color, Colors.white);
    }
    expect(theme.scaffoldBackgroundColor, scheme.surfaceContainerLow);
    expect(theme.extension<AppSemanticColors>(), AppSemanticColors.light);
    expect(theme.progressIndicatorTheme.color, scheme.primary);
    expect(scheme.primary, AppTheme.brandSeed);
  });

  test('purchased Manrope uses template 1.3 metrics and platform Arabic fallback', () {
    final text = AppTheme.light.textTheme;
    final scale = <(TextStyle?, double, double, FontWeight)>[
      (text.headlineLarge, 24, 31.2, FontWeight.w700),
      (text.headlineMedium, 24, 31.2, FontWeight.w700),
      (text.headlineSmall, 22, 28.6, FontWeight.w600),
      (text.titleLarge, 18, 23.4, FontWeight.w600),
      (text.titleMedium, 18, 23.4, FontWeight.w600),
      (text.titleSmall, 16, 20.8, FontWeight.w600),
      (text.bodyLarge, 16, 20.8, FontWeight.w400),
      (text.bodyMedium, 14, 18.2, FontWeight.w400),
      (text.bodySmall, 12, 15.6, FontWeight.w400),
      (text.labelLarge, 16, 20.8, FontWeight.w600),
      (text.labelMedium, 14, 18.2, FontWeight.w600),
      (text.labelSmall, 12, 15.6, FontWeight.w600),
    ];
    for (final (style, size, lineHeight, weight) in scale) {
      expect(style!.fontSize, size);
      expect(style.height! * size, closeTo(lineHeight, 0.000001));
      expect(style.fontWeight, weight);
      expect(style.letterSpacing, 0);
      expect(style.fontFamily, 'PrimaryFont');
      expect(style.fontFamilyFallback, ['sans-serif']);
      expect(style.color, const Color(0xFF4D5454));
    }
    expect(AppTypography.bodyLarge.fontFamily, isNull);
    for (final style in [
      text.displayLarge,
      text.displayMedium,
      text.displaySmall,
    ]) {
      expect(style!.letterSpacing, 0);
    }
  });

  test('enabled semantic and Material text pairs meet accepted contrast', () {
    final scheme = AppTheme.light.colorScheme;
    const semantic = AppSemanticColors.light;
    for (final (foreground, background) in [
      (scheme.onPrimary, scheme.primary),
      (scheme.onPrimaryContainer, scheme.primaryContainer),
      (scheme.onSecondary, scheme.secondary),
      (scheme.onSecondaryContainer, scheme.secondaryContainer),
      (scheme.onSurface, scheme.surface),
      (scheme.onSurfaceVariant, scheme.surface),
      (scheme.primary, scheme.surface),
      (scheme.onError, scheme.error),
      (scheme.onErrorContainer, scheme.errorContainer),
      (scheme.onInverseSurface, scheme.inverseSurface),
      (semantic.onSuccess, semantic.success),
      (semantic.onSuccessContainer, semantic.successContainer),
      (semantic.onWarning, semantic.warning),
      (semantic.onWarningContainer, semantic.warningContainer),
      (semantic.onInfo, semantic.info),
      (semantic.onInfoContainer, semantic.infoContainer),
      (semantic.onNeutral, semantic.neutral),
      (semantic.onNeutralContainer, semantic.neutralContainer),
    ]) {
      expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
    }
    expect(_contrast(scheme.outline, scheme.surface), greaterThanOrEqualTo(3));
  });

  test('semantic copyWith preserves omitted fields and replaces every role', () {
    const original = AppSemanticColors.light;
    expect(_semanticValues(original.copyWith()), _semanticValues(original));
    final warningOnly = original.copyWith(warning: Colors.black);
    expect(warningOnly.warning, Colors.black);
    final preserved = _semanticValues(original)..remove('warning');
    expect(_semanticValues(warningOnly)..remove('warning'), preserved);

    final replaced = original.copyWith(
      success: Colors.black,
      onSuccess: Colors.black,
      successContainer: Colors.black,
      onSuccessContainer: Colors.black,
      warning: Colors.black,
      onWarning: Colors.black,
      warningContainer: Colors.black,
      onWarningContainer: Colors.black,
      info: Colors.black,
      onInfo: Colors.black,
      infoContainer: Colors.black,
      onInfoContainer: Colors.black,
      neutral: Colors.black,
      onNeutral: Colors.black,
      neutralContainer: Colors.black,
      onNeutralContainer: Colors.black,
      disabledContainer: Colors.black,
      onDisabledContainer: Colors.black,
      disabledOutline: Colors.black,
      skeletonBase: Colors.black,
      skeletonHighlight: Colors.black,
    );
    expect(_semanticValues(replaced).values, everyElement(Colors.black));
  });

  test('ThemeData interpolation includes every semantic role', () {
    const original = AppSemanticColors.light;
    const target = AppSemanticColors(
      success: Colors.black,
      onSuccess: Colors.white,
      successContainer: Colors.white,
      onSuccessContainer: Colors.black,
      warning: Colors.black,
      onWarning: Colors.white,
      warningContainer: Colors.white,
      onWarningContainer: Colors.black,
      info: Colors.black,
      onInfo: Colors.white,
      infoContainer: Colors.white,
      onInfoContainer: Colors.black,
      neutral: Colors.black,
      onNeutral: Colors.white,
      neutralContainer: Colors.white,
      onNeutralContainer: Colors.black,
      disabledContainer: Colors.white,
      onDisabledContainer: Colors.black,
      disabledOutline: Colors.black,
      skeletonBase: Colors.black,
      skeletonHighlight: Colors.white,
    );
    expect(original.lerp(null, 0.5), same(original));
    final startTheme = AppTheme.light;
    final endTheme = startTheme.copyWith(extensions: [target]);
    for (final t in [0.0, 0.5, 1.0]) {
      final actual = _semanticValues(
        ThemeData.lerp(startTheme, endTheme, t).extension<AppSemanticColors>()!,
      );
      final start = _semanticValues(original);
      final end = _semanticValues(target);
      for (final role in start.keys) {
        expect(actual[role], Color.lerp(start[role], end[role], t), reason: role);
      }
    }
  });

  test('legacy theme constants remain usable in const expressions', () {
    const legacy = [
      AppTheme.brand,
      AppTheme.brandStrong,
      AppTheme.brandSoft,
      AppTheme.accent,
      AppTheme.accentSoft,
      AppTheme.page,
      AppTheme.surface,
      AppTheme.outlineSoft,
      AppTheme.textStrong,
      AppTheme.textMuted,
      AppTheme.warning,
    ];
    expect(legacy, const [
      Color(0xFF087C7C),
      Color(0xFF065858),
      Color(0xFFE6F2F2),
      Color(0xFF087C7C),
      Color(0xFFE6F2F2),
      Color(0xFFFAFAFA),
      Colors.white,
      Color(0x99EEEEEE),
      Color(0xFF4D5454),
      Color(0x99000000),
      Color(0xFFC88700),
    ]);
  });

  testWidgets('theme reaches an RTL subtree without suppressing text scaling',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: Scaffold(body: Builder(builder: (context) {
        expect(Directionality.of(context), TextDirection.rtl);
        expect(MediaQuery.textScalerOf(context).scale(16), 32);
        expect(Theme.of(context).extension<AppSemanticColors>(), isNotNull);
        return Text('تفاصيل العقار', style: Theme.of(context).textTheme.bodyLarge);
      })),
    ));

    final text = tester.widget<Text>(find.text('تفاصيل العقار'));
    expect(text.textDirection, isNull,
        reason: 'Text should inherit RTL from Directionality rather than force it.');
    expect(Directionality.of(tester.element(find.text('تفاصيل العقار'))),
        TextDirection.rtl);
    final richText = tester.widget<RichText>(find.descendant(
      of: find.text('تفاصيل العقار'),
      matching: find.byType(RichText),
    ));
    expect(richText.textScaler.scale(16), 32);
    expect(tester.takeException(), isNull);
  });
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

Map<String, Color> _semanticValues(AppSemanticColors colors) => {
      'success': colors.success,
      'onSuccess': colors.onSuccess,
      'successContainer': colors.successContainer,
      'onSuccessContainer': colors.onSuccessContainer,
      'warning': colors.warning,
      'onWarning': colors.onWarning,
      'warningContainer': colors.warningContainer,
      'onWarningContainer': colors.onWarningContainer,
      'info': colors.info,
      'onInfo': colors.onInfo,
      'infoContainer': colors.infoContainer,
      'onInfoContainer': colors.onInfoContainer,
      'neutral': colors.neutral,
      'onNeutral': colors.onNeutral,
      'neutralContainer': colors.neutralContainer,
      'onNeutralContainer': colors.onNeutralContainer,
      'disabledContainer': colors.disabledContainer,
      'onDisabledContainer': colors.onDisabledContainer,
      'disabledOutline': colors.disabledOutline,
      'skeletonBase': colors.skeletonBase,
      'skeletonHighlight': colors.skeletonHighlight,
    };
