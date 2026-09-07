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
      (scheme.primary, 0xFF0B7547),
      (scheme.primaryContainer, 0xFFE5F5EC),
      (scheme.onPrimaryContainer, 0xFF075B39),
      (scheme.secondary, 0xFF1778B8),
      (scheme.secondaryContainer, 0xFFE7F2FA),
      (scheme.onSecondaryContainer, 0xFF0D4D75),
      (scheme.onSurface, 0xFF111820),
      (scheme.onSurfaceVariant, 0xFF505B65),
      (scheme.surfaceContainerLow, 0xFFF5F7F8),
      (scheme.surfaceContainer, 0xFFF0F3F4),
      (scheme.surfaceContainerHigh, 0xFFE7ECEF),
      (scheme.surfaceContainerHighest, 0xFFDDE4E8),
      (scheme.outline, 0xFF78858F),
      (scheme.outlineVariant, 0xFFC9D2D7),
      (scheme.error, 0xFFB3261E),
      (scheme.errorContainer, 0xFFF9DEDC),
      (scheme.onErrorContainer, 0xFF410E0B),
      (scheme.inverseSurface, 0xFF24313A),
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
    expect(scheme.primary, isNot(AppTheme.brandSeed));
  });

  test('accepted text scale uses explicit metrics and the safe fallback', () {
    final text = AppTheme.light.textTheme;
    final scale = <(TextStyle?, double, double, FontWeight)>[
      (text.headlineLarge, 28, 40, FontWeight.w700),
      (text.headlineMedium, 24, 36, FontWeight.w700),
      (text.headlineSmall, 22, 32, FontWeight.w600),
      (text.titleLarge, 20, 32, FontWeight.w600),
      (text.titleMedium, 18, 28, FontWeight.w600),
      (text.titleSmall, 16, 24, FontWeight.w600),
      (text.bodyLarge, 16, 28, FontWeight.w400),
      (text.bodyMedium, 14, 24, FontWeight.w400),
      (text.bodySmall, 12, 20, FontWeight.w400),
      (text.labelLarge, 16, 24, FontWeight.w600),
      (text.labelMedium, 14, 20, FontWeight.w600),
      (text.labelSmall, 12, 20, FontWeight.w600),
    ];
    for (final (style, size, lineHeight, weight) in scale) {
      expect(style!.fontSize, size);
      expect(style.height! * size, closeTo(lineHeight, 0.000001));
      expect(style.fontWeight, weight);
      expect(style.letterSpacing, 0);
      expect(style.fontFamilyFallback, ['Arial', 'sans-serif']);
      expect(style.color, const Color(0xFF111820));
    }
    // No unavailable family is configured by the foundation.
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
      (semantic.success, semantic.successContainer),
      (semantic.warning, semantic.warningContainer),
      (semantic.info, semantic.infoContainer),
      (semantic.neutral, semantic.neutralContainer),
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
      successContainer: Colors.black,
      warning: Colors.black,
      warningContainer: Colors.black,
      info: Colors.black,
      infoContainer: Colors.black,
      neutral: Colors.black,
      neutralContainer: Colors.black,
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
      successContainer: Colors.white,
      warning: Colors.black,
      warningContainer: Colors.white,
      info: Colors.black,
      infoContainer: Colors.white,
      neutral: Colors.black,
      neutralContainer: Colors.white,
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
      Color(0xFF0B8A55),
      Color(0xFF075B39),
      Color(0xFFE5F5EC),
      Color(0xFF1778B8),
      Color(0xFFE7F2FA),
      Color(0xFFF5F7F8),
      Colors.white,
      Color(0xFFC9D2D7),
      Color(0xFF111820),
      Color(0xFF505B65),
      Color(0xFFD79B00),
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
    final richText = tester.widget<RichText>(find.descendant(
      of: find.text('تفاصيل العقار'),
      matching: find.byType(RichText),
    ));
    expect(richText.textDirection, TextDirection.rtl);
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
      'successContainer': colors.successContainer,
      'warning': colors.warning,
      'warningContainer': colors.warningContainer,
      'info': colors.info,
      'infoContainer': colors.infoContainer,
      'neutral': colors.neutral,
      'neutralContainer': colors.neutralContainer,
      'disabledContainer': colors.disabledContainer,
      'onDisabledContainer': colors.onDisabledContainer,
      'disabledOutline': colors.disabledOutline,
      'skeletonBase': colors.skeletonBase,
      'skeletonHighlight': colors.skeletonHighlight,
    };
