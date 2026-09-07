import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

export 'app_semantic_colors.dart';
export 'app_tokens.dart';
export 'app_typography.dart';

abstract final class AppTheme {
  static const brandSeed = Color(0xFF0B8A55);

  // Compatibility constants for existing call sites. New code should obtain
  // Material colors from Theme.of(context).colorScheme and custom tones from
  // its AppSemanticColors extension. Do not use brandSeed as an action color.
  static const brand = brandSeed;
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
      seedColor: brandSeed,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF0B7547),
      onPrimary: Colors.white,
      primaryContainer: brandSoft,
      onPrimaryContainer: brandStrong,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: accentSoft,
      onSecondaryContainer: const Color(0xFF0D4D75),
      surface: surface,
      onSurface: textStrong,
      onSurfaceVariant: textMuted,
      surfaceContainerLow: page,
      surfaceContainer: const Color(0xFFF0F3F4),
      surfaceContainerHigh: const Color(0xFFE7ECEF),
      surfaceContainerHighest: const Color(0xFFDDE4E8),
      outline: const Color(0xFF78858F),
      outlineVariant: outlineSoft,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
      inverseSurface: const Color(0xFF24313A),
      onInverseSurface: Colors.white,
    );

    final readableTextTheme = AppTypography.textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: const [AppSemanticColors.light],
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      visualDensity: VisualDensity.standard,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      textTheme: readableTextTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.raised,
        titleTextStyle: readableTextTheme.titleLarge,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: AppBorderWidths.standard,
        space: AppBorderWidths.standard,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsetsDirectional.all(AppLayout.surfacePadding),
        labelStyle: readableTextTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: readableTextTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.outline,
            width: AppBorderWidths.standard,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.outline,
            width: AppBorderWidths.standard,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: scheme.primary,
            width: AppBorderWidths.emphasized,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize:
              const Size(AppSizes.touchTarget, AppSizes.buttonMinHeight),
          foregroundColor: scheme.onPrimary,
          textStyle: AppTypography.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize:
              const Size(AppSizes.touchTarget, AppSizes.buttonMinHeight),
          foregroundColor: scheme.onSurface,
          side: BorderSide(
            color: scheme.outline,
            width: AppBorderWidths.standard,
          ),
          textStyle: AppTypography.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(
          color: scheme.outline,
          width: AppBorderWidths.standard,
        ),
        checkmarkColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        labelStyle: readableTextTheme.labelMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
