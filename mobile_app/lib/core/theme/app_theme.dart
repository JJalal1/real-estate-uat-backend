import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';
import 'ebroker_design.dart';

export 'app_semantic_colors.dart';
export 'app_tokens.dart';
export 'app_typography.dart';

abstract final class AppTheme {
  // Teal identity with ink accents and soft layered surfaces.
  static const brandSeed = Color(0xFF087C7C);
  static const brand = brandSeed;
  static const brandStrong = Color(0xFF065858);
  static const brandSoft = Color(0xFFE6F2F2);
  static const accent = Color(0xFF203A56);
  static const accentSoft = Color(0xFFEAF0F7);
  static const page = Color(0xFFF5F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const outlineSoft = Color(0xFFE3EAF1);
  static const textStrong = Color(0xFF192F48);
  static const textMuted = Color(0xFF64748B);
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
      onSecondaryContainer: accent,
      surface: surface,
      onSurface: EbrokerDesign.text,
      onSurfaceVariant: EbrokerDesign.textLight,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: EbrokerDesign.page,
      surfaceContainer: const Color(0xFFF0F4F8),
      surfaceContainerHigh: const Color(0xFFEAF0F5),
      surfaceContainerHighest: const Color(0xFFE3EAF1),
      outline: const Color(0xFF7A8797),
      outlineVariant: EbrokerDesign.border,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
      inverseSurface: const Color(0xFF192F48),
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
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: brand, selectionHandleColor: brand,
        selectionColor: Color(0x4D087C7C),
      ),
      fontFamily: AppTypography.fontFamily,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      textTheme: readableTextTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: EbrokerDesign.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: readableTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
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
        indicatorColor: Colors.transparent,
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
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
        prefixIconConstraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        suffixIconConstraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        labelStyle: readableTextTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: readableTextTheme.bodyLarge?.copyWith(
          color: EbrokerDesign.text.withValues(alpha: .7), fontSize: 14, fontWeight: FontWeight.w400,
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
            width: 1,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 52), backgroundColor: scheme.primary, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)))),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(AppSizes.touchTarget, 52),
          foregroundColor: scheme.onPrimary,
          textStyle: AppTypography.labelLarge.copyWith(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w500,
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
      popupMenuTheme: PopupMenuThemeData(color: scheme.surface, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: readableTextTheme.bodyMedium, elevation: 8),
      dropdownMenuTheme: DropdownMenuThemeData(menuStyle: MenuStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        backgroundColor: WidgetStatePropertyAll(scheme.surface), surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent))),
      tabBarTheme: TabBarThemeData(labelColor: scheme.primary, unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary, dividerColor: scheme.outlineVariant,
        labelStyle: readableTextTheme.labelLarge, indicatorSize: TabBarIndicatorSize.label),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        checkmarkColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EbrokerDesign.controlRadius),
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

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF75D5D0),
      onPrimary: const Color(0xFF003735),
      primaryContainer: const Color(0xFF084E4D),
      onPrimaryContainer: const Color(0xFFB2F1ED),
      secondary: const Color(0xFFB8CAE0),
      onSecondary: const Color(0xFF213547),
      surface: const Color(0xFF121B22),
      onSurface: const Color(0xFFE7EEF3),
      onSurfaceVariant: const Color(0xFFB7C4CC),
      surfaceContainerLowest: const Color(0xFF0D1419),
      surfaceContainerLow: const Color(0xFF162128),
      surfaceContainer: const Color(0xFF1C282F),
      surfaceContainerHigh: const Color(0xFF233038),
      surfaceContainerHighest: const Color(0xFF2A3841),
      outline: const Color(0xFF83939E),
      outlineVariant: const Color(0xFF43515A),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
    );
    final textTheme = AppTypography.textTheme.apply(
      fontFamily: AppTypography.fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      extensions: const [AppSemanticColors.dark],
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      fontFamily: AppTypography.fontFamily,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
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
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(AppSizes.touchTarget, 52),
          foregroundColor: scheme.onPrimary,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

}
