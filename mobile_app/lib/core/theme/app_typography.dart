import 'package:flutter/material.dart';

/// Arabic-first type scale tuned for mobile readability and quick scanning.
/// The bundled family is retained so no network font is required.
abstract final class AppTypography {
  static const fontFamily = 'NotoSansArabic';
  static const fontFamilyFallback = <String>['Arial', 'sans-serif'];

  static const headlineLarge = TextStyle(
    fontSize: 30,
    height: 1.35,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const headlineMedium = TextStyle(
    fontSize: 25,
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const headlineSmall = TextStyle(
    fontSize: 22,
    height: 1.42,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleLarge = TextStyle(
    fontSize: 19,
    height: 1.45,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleMedium = TextStyle(
    fontSize: 17,
    height: 1.45,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleSmall = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.65,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.65,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodySmall = TextStyle(
    fontSize: 12.5,
    height: 1.6,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelLarge = TextStyle(
    fontSize: 15.5,
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelMedium = TextStyle(
    fontSize: 13.5,
    height: 1.4,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelSmall = TextStyle(
    fontSize: 11.5,
    height: 1.4,
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
