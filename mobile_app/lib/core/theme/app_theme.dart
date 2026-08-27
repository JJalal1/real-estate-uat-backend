import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const brand = Color(0xFF0B8A55);
  static const brandStrong = Color(0xFF075B39);
  static const brandSoft = Color(0xFFE5F5EC);
  static const accent = Color(0xFF1778B8);
  static const accentSoft = Color(0xFFE7F2FA);
  static const page = Color(0xFFF5F7F8);
  static const surface = Colors.white;
  static const outlineSoft = Color(0xFFC9D2D7);
  static const textStrong = Color(0xFF111820);
  static const textMuted = Color(0xFF505B65);
  static const warning = Color(0xFFD79B00);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: brand,
      secondary: accent,
      surface: surface,
      onSurface: textStrong,
      outline: outlineSoft,
    );

    final readableTextTheme = ThemeData.light().textTheme.apply(
          bodyColor: textStrong,
          displayColor: textStrong,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      visualDensity: VisualDensity.standard,
      fontFamilyFallback: const ['Arial', 'sans-serif'],
      textTheme: readableTextTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: surface,
        foregroundColor: textStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          color: textStrong,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outlineSoft,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle:
            const TextStyle(color: textMuted, fontWeight: FontWeight.w600),
        hintStyle:
            const TextStyle(color: textMuted, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: brand, width: 1.7),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: textStrong,
          side: const BorderSide(color: outlineSoft, width: 1.2),
          textStyle: const TextStyle(
            color: textStrong,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: brandSoft,
        side: const BorderSide(color: outlineSoft, width: 1.1),
        checkmarkColor: brandStrong,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        labelStyle: const TextStyle(
          color: textStrong,
          fontWeight: FontWeight.w800,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brand),
    );
  }
}
