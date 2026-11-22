import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';
import 'ebroker_design.dart';

export 'app_semantic_colors.dart';
export 'app_tokens.dart';
export 'app_typography.dart';

abstract final class AppTheme {
  static const brandSeed = AppPalette.petrol;
  static const brand = AppPalette.petrol;
  static const brandStrong = AppPalette.pressedPetrol;
  static const brandSoft = AppPalette.paleTurquoise;
  static const brandMint = Color(0xFF9FE4D9);
  static const accent = AppPalette.turquoise;
  static const accentSoft = AppPalette.paleTurquoise;
  static const page = AppPalette.ivory;
  static const surface = AppPalette.paper;
  static const outlineSoft = AppPalette.stone;
  static const textStrong = AppPalette.charcoal;
  static const textMuted = AppPalette.slate;
  static const warning = AppPalette.sand;

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
      onSecondaryContainer: brand,
      tertiary: AppPalette.coral,
      onTertiary: AppPalette.charcoal,
      tertiaryContainer: AppPalette.peach,
      onTertiaryContainer: AppPalette.copper,
      surface: surface,
      onSurface: textStrong,
      onSurfaceVariant: textMuted,
      surfaceContainerLowest: surface,
      surfaceContainerLow: page,
      surfaceContainer: const Color(0xFFF1EEE7),
      surfaceContainerHigh: AppPalette.mist,
      surfaceContainerHighest: outlineSoft,
      outline: AppPalette.inputBorder,
      outlineVariant: outlineSoft,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
      inverseSurface: AppPalette.petrol,
      onInverseSurface: Colors.white,
    );

    return _build(scheme, AppSemanticColors.light);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandSeed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF9BD8D2),
      onPrimary: AppPalette.pressedPetrol,
      primaryContainer: AppPalette.petrol,
      onPrimaryContainer: AppPalette.paleTurquoise,
      secondary: const Color(0xFF73D6CA),
      onSecondary: AppPalette.pressedPetrol,
      secondaryContainer: const Color(0xFF234C49),
      onSecondaryContainer: AppPalette.paleTurquoise,
      tertiary: AppPalette.coral,
      onTertiary: AppPalette.charcoal,
      tertiaryContainer: const Color(0xFF592D21),
      onTertiaryContainer: const Color(0xFFFFBAA6),
      surface: const Color(0xFF182728),
      onSurface: AppPalette.ivory,
      onSurfaceVariant: const Color(0xFFC0CDCA),
      surfaceContainerLowest: const Color(0xFF0E1C1D),
      surfaceContainerLow: const Color(0xFF132223),
      surfaceContainer: const Color(0xFF1C2D2E),
      surfaceContainerHigh: const Color(0xFF253839),
      surfaceContainerHighest: const Color(0xFF2D4243),
      outline: const Color(0xFF8FA39F),
      outlineVariant: const Color(0xFF465A58),
      inverseSurface: AppPalette.ivory,
      onInverseSurface: AppPalette.charcoal,
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
    );
    return _build(scheme, AppSemanticColors.dark);
  }

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final readableTextTheme = AppTypography.textTheme.apply(
      fontFamily: AppTypography.fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [semantic],
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      visualDensity: VisualDensity.standard,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary, selectionHandleColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: .28),
      ),
      fontFamily: AppTypography.fontFamily,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      fontFamilyFallback: AppTypography.fontFamilyFallback,
      textTheme: readableTextTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
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
          color: scheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w400,
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
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      listTileTheme: ListTileThemeData(textColor: scheme.onSurface, iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 52), backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary,
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
        selectedColor: scheme.secondary,
        side: BorderSide(color: scheme.outlineVariant),
        checkmarkColor: scheme.onSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EbrokerDesign.controlRadius),
        ),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s4),
        labelStyle: readableTextTheme.labelMedium?.copyWith(
          color: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.onSecondary : scheme.onSurface),
        ),
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
