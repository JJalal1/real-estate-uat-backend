import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

export 'app_semantic_colors.dart';
export 'app_tokens.dart';
export 'app_typography.dart';

abstract final class AppTheme {
  // Calm, high-trust marketplace palette. Green is reserved for brand/action;
  // neutral surfaces carry most of the visual weight.
  static const brandSeed = Color(0xFF0C7A50);
  static const brand = brandSeed;
  static const brandStrong = Color(0xFF075338);
  static const brandSoft = Color(0xFFE8F5EF);
  static const accent = Color(0xFF2C6EAA);
  static const accentSoft = Color(0xFFEAF2F9);
  static const page = Color(0xFFF8F9F7);
  static const surface = Color(0xFFFFFFFF);
  static const outlineSoft = Color(0xFFDCE2DF);
  static const textStrong = Color(0xFF15201B);
  static const textMuted = Color(0xFF5F6B65);
  static const warning = Color(0xFFC88700);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.light,
    ).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      primaryContainer: brandSoft,
      onPrimaryContainer: brandStrong,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: accentSoft,
      onSecondaryContainer: const Color(0xFF174E79),
      surface: surface,
      onSurface: textStrong,
      onSurfaceVariant: textMuted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: page,
      surfaceContainer: const Color(0xFFF2F5F3),
      surfaceContainerHigh: const Color(0xFFEBEFEC),
      surfaceContainerHighest: const Color(0xFFE3E8E5),
      outline: const Color(0xFF89948E),
      outlineVariant: outlineSoft,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
      inverseSurface: const Color(0xFF24312B),
      onInverseSurface: Colors.white,
    );

    final readableTextTheme = AppTypography.textTheme.apply(
      fontFamily: AppTypography.fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: const [AppSemanticColors.light],
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      visualDensity: VisualDensity.standard,
      fontFamily: AppTypography.fontFamily,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      textTheme: readableTextTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.raised,
        titleTextStyle: readableTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: AppElevation.raised,
        height: AppSizes.navigationMinHeight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return readableTextTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.modal)),
        ),
        showDragHandle: true,
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
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: scheme.outlineVariant),
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
          minimumSize: const Size(AppSizes.touchTarget, 52),
          foregroundColor: scheme.onPrimary,
          textStyle: AppTypography.labelLarge.copyWith(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(AppSizes.touchTarget, 52),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: AppTypography.labelLarge.copyWith(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        checkmarkColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s4),
        labelStyle: readableTextTheme.labelMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: scheme.onInverseSurface,
          fontFamily: AppTypography.fontFamily,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
