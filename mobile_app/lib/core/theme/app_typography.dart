import 'package:flutter/material.dart';

/// Bundled Cairo typography for Arabic and mixed Arabic/Latin text.
abstract final class AppTypography {
  static const fontFamily = 'Cairo';
  static const fontFamilyFallback = <String>['NotoSansArabic', 'PrimaryFont', 'sans-serif'];

  static const screenTitle = TextStyle(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const sectionTitle = TextStyle(
    fontSize: 19,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const titleSmall = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyLarge = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    fontFamilyFallback: fontFamilyFallback,
  );
  static const bodyMedium = TextStyle(
    fontSize: 15,
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

  static const propertyPrice = TextStyle(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );
  static const propertyName = TextStyle(
    fontSize: 17,
    height: 1.45,
    fontWeight: FontWeight.w600,
  );
  static const propertySecondary = TextStyle(
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
  static const dealBadge = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const headlineLarge = screenTitle;
  static const headlineMedium = screenTitle;
  static const headlineSmall = screenTitle;
  static const titleLarge = sectionTitle;
  static const titleMedium = sectionTitle;

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
