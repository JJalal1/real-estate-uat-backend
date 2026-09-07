import 'package:flutter/material.dart';

/// Accepted Arabic-first scale; line heights are expressed as size ratios.
/// Leave fontFamily unset until W3B2 bundles and activates the target family.
abstract final class AppTypography {
  static const fontFamilyFallback = <String>['Arial', 'sans-serif'];

  static const headlineLarge = TextStyle(
    fontSize: 28,
    height: 40 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const headlineMedium = TextStyle(
    fontSize: 24,
    height: 36 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const headlineSmall = TextStyle(
    fontSize: 22,
    height: 32 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleLarge = TextStyle(
    fontSize: 20,
    height: 32 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleMedium = TextStyle(
    fontSize: 18,
    height: 28 / 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleSmall = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 28 / 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 24 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodySmall = TextStyle(
    fontSize: 12,
    height: 20 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelLarge = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelMedium = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const labelSmall = TextStyle(
    fontSize: 12,
    height: 20 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );

  static const textTheme = TextTheme(
    // No separate display scale is specified in W3A. Reuse the headlines so
    // inherited Material display styles cannot introduce Arabic tracking.
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
