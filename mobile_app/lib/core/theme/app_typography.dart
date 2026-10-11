import 'package:flutter/material.dart';

/// Manrope PrimaryFont and 1.3 line height from the purchased eBroker source.
/// Bundled Arabic fallback supports the existing Arabic product language.
abstract final class AppTypography {
  static const fontFamily = 'PrimaryFont';
  static const fontFamilyFallback = <String>['NotoSansArabic', 'Arial', 'sans-serif'];

  static const headlineLarge = TextStyle(
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const headlineMedium = TextStyle(
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const headlineSmall = TextStyle(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleLarge = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleMedium = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleSmall = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodySmall = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelLarge = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelMedium = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelSmall = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );

  static const textTheme = TextTheme(
    displayLarge: headlineLarge,
    displayMedium: headlineMedium,
    displaySmall: headlineSmall,
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );
}
