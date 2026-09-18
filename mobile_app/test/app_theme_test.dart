import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';

void main() {
  test('P02 revision implements the accepted real-estate color contract', () {
    final theme = AppTheme.light;
    final scheme = theme.colorScheme;
    expect(theme.useMaterial3, isTrue);
    expect(scheme.brightness, Brightness.light);

    final roles = <(Color, int)>[
      (scheme.primary, 0xFF123C4A),
      (scheme.primaryContainer, 0xFFE8F1F3),
      (scheme.onPrimaryContainer, 0xFF0A2933),
      (scheme.secondary, 0xFF0B7D78),
      (scheme.secondaryContainer, 0xFFE3F3F1),
      (scheme.onSecondaryContainer, 0xFF075E5B),
      (scheme.tertiary, 0xFFC99A3D),
      (scheme.tertiaryContainer, 0xFFFFF4D9),
      (scheme.onSurface, 0xFF142126),
      (scheme.onSurfaceVariant, 0xFF617077),
      (scheme.surfaceContainerLow, 0xFFF6F8FA),
      (scheme.surfaceContainer, 0xFFF0F4F6),
      (scheme.surfaceContainerHigh, 0xFFE8EEF1),
      (scheme.surfaceContainerHighest, 0xFFE0E8EB),
      (scheme.outline, 0xFF849197),
      (scheme.outlineVariant, 0xFFD8E0E4),
      (scheme.error, 0xFFB42318),
      (scheme.errorContainer, 0xFFFDECEA),
      (scheme.onErrorContainer, 0xFF7A271A),
      (scheme.inverseSurface, 0xFF1E2D33),
    ];
    for (final (actual, expected) in roles) {
      expect(actual, Color(expected));
    }

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF6F8FA));
    expect(theme.extension<AppSemanticColors>(), AppSemanticColors.light);
    expect(theme.progressIndicatorTheme.color, scheme.secondary);
    expect(scheme.primary, AppTheme.brandSeed);
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
  });

  test('P02 Arabic type scale favors quick scanning and safe fallback', () {
    final text = AppTheme.light.textTheme;
    final scale = <(TextStyle?, double, double, FontWeight)>[
      (text.headlineLarge, 30, 1.35, FontWeight.w700),
      (text.headlineMedium, 25, 1.40, FontWeight.w700),
      (text.headlineSmall, 22, 1.42, FontWeight.w700),
      (text.titleLarge, 19, 1.45, FontWeight.w700),
      (text.titleMedium, 17, 1.45, FontWeight.w700),
      (text.titleSmall, 15, 1.45, FontWeight.w600),
      (text.bodyLarge, 16, 1.65, FontWeight.w400),
      (text.bodyMedium, 14, 1.65, FontWeight.w400),
      (text.bodySmall, 12.5, 1.60, FontWeight.w400),
      (text.labelLarge, 15.5, 1.40, FontWeight.w700),
      (text.labelMedium, 13.5, 1.40, FontWeight.w700),
      (text.labelSmall, 11.5, 1.40, FontWeight.w600),
    ];
    for (final (style, size, height, weight) in scale) {
      expect(style!.fontSize, size);
      expect(style.height, closeTo(height, 0.000001));
      expect(style.fontWeight, weight);
      expect(style.letterSpacing, 0);
      expect(style.fontFamilyFallback, ['Arial', 'sans-serif']);
      expect(style.color, const Color(0xFF142126));
    }
    expect(AppTypography.bodyLarge.fontFamily, isNull);
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

  test('theme constants remain usable in const expressions', () {
    const palette = [
      AppTheme.brand,
      AppTheme.brandStrong,
      AppTheme.brandSoft,
      AppTheme.accent,
      AppTheme.accentSoft,
      AppTheme.highlight,
      AppTheme.page,
      AppTheme.surface,
      AppTheme.outlineSoft,
      AppTheme.textStrong,
      AppTheme.textMuted,
      AppTheme.warning,
    ];
    expect(palette, const [
      Color(0xFF123C4A),
      Color(0xFF0A2933),
      Color(0xFFE8F1F3),
      Color(0xFF0B7D78),
      Color(0xFFE3F3F1),
      Color(0xFFC99A3D),
      Color(0xFFF6F8FA),
      Colors.white,
      Color(0xFFD8E0E4),
      Color(0xFF142126),
      Color(0xFF617077),
      Color(0xFFB56D00),
    ]);
  });

  testWidgets('theme reaches an RTL subtree without suppressing text scaling',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: Scaffold(body: Builder(builder: (context) {
        expect(Directionality.of(context), TextDirection.rtl);
        expect(MediaQuery.textScalerOf(context).scale(16), 32);
        expect(Theme.of(context).extension<AppSemanticColors>(), isNotNull);
        return Text(
          'تفاصيل العقار',
          style: Theme.of(context).textTheme.bodyLarge,
        );
      })),
    ));

    final text = tester.widget<Text>(find.text('تفاصيل العقار'));
    expect(text.textDirection, isNull);
    expect(
      Directionality.of(tester.element(find.text('تفاصيل العقار'))),
      TextDirection.rtl,
    );
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
