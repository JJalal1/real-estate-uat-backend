import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

export 'app_semantic_colors.dart';
export 'app_tokens.dart';
export 'app_typography.dart';

abstract final class AppTheme {
  // P02 revision palette:
  // deep navy = trust/stability, teal = modern real-estate accent,
  // warm gold = restrained attention color. Neutral surfaces carry the UI.
  static const brandSeed = Color(0xFF123C4A);
  static const brand = Color(0xFF123C4A);
  static const brandStrong = Color(0xFF0A2933);
  static const brandSoft = Color(0xFFE8F1F3);
  static const accent = Color(0xFF0B7D78);
  static const accentStrong = Color(0xFF075E5B);
  static const accentSoft = Color(0xFFE3F3F1);
  static const highlight = Color(0xFFC99A3D);
  static const highlightSoft = Color(0xFFFFF4D9);

  static const page = Color(0xFFF6F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF0F4F6);
  static const outlineSoft = Color(0xFFD8E0E4);
  static const textStrong = Color(0xFF142126);
  static const textMuted = Color(0xFF617077);
  static const warning = Color(0xFFB56D00);

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
      onSecondaryContainer: accentStrong,
      tertiary: highlight,
      onTertiary: const Color(0xFF2C210A),
      tertiaryContainer: highlightSoft,
      onTertiaryContainer: const Color(0xFF5B430D),
      surface: surface,
      onSurface: textStrong,
      onSurfaceVariant: textMuted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: page,
      surfaceContainer: surfaceSoft,
      surfaceContainerHigh: const Color(0xFFE8EEF1),
      surfaceContainerHighest: const Color(0xFFE0E8EB),
      outline: const Color(0xFF849197),
      outlineVariant: outlineSoft,
      error: const Color(0xFFB42318),
      onError: Colors.white,
      errorContainer: const Color(0xFFFDECEA),
      onErrorContainer: const Color(0xFF7A271A),
      inverseSurface: const Color(0xFF1E2D33),
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
      scaffoldBackgroundColor: page,
      canvasColor: page,
      visualDensity: VisualDensity.standard,
      fontFamily: AppTypography.fontFamily,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      textTheme: readableTextTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: page,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: readableTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return readableTextTheme.labelSmall?.copyWith(
            color: selected ? scheme.secondary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.secondary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: readableTextTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: readableTextTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
        ),
        prefixIconColor: scheme.secondary,
        suffixIconColor: scheme.onSurfaceVariant,
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
          borderSide: BorderSide(color: scheme.secondary, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(AppSizes.touchTarget, 54),
          backgroundColor: scheme.primary,
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
          minimumSize: const Size(AppSizes.touchTarget, 54),
          foregroundColor: scheme.primary,
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
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.secondary,
          textStyle: AppTypography.labelMedium.copyWith(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.secondaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        checkmarkColor: scheme.secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
        labelStyle: readableTextTheme.labelMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: scheme.onInverseSurface,
          fontFamily: AppTypography.fontFamily,
          fontWeight: FontWeight.w600,
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
