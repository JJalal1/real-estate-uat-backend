import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';

void main() {
  test('spacing and layout match the P02 simplified scale', () {
    expect([
      AppSpacing.none,
      AppSpacing.s4,
      AppSpacing.s8,
      AppSpacing.s12,
      AppSpacing.s16,
      AppSpacing.s20,
      AppSpacing.s24,
      AppSpacing.s32,
      AppSpacing.s40,
      AppSpacing.s48,
      AppSpacing.s64,
    ], [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64]);
    expect([
      AppLayout.compactPageGutter,
      AppLayout.widePageGutter,
      AppLayout.narrowBreakpoint,
      AppLayout.wideBreakpoint,
      AppLayout.contentMaxWidth,
      AppLayout.sectionGap,
      AppLayout.groupGap,
      AppLayout.itemGap,
      AppLayout.fieldGap,
      AppLayout.inlineGap,
      AppLayout.surfacePadding,
      AppLayout.compactSurfacePadding,
      AppLayout.dialogPadding,
    ], [16, 24, 360, 600, 760, 28, 20, 12, 16, 8, 16, 12, 24]);
  });

  test('shape and elevation match the P02 redesigned scale', () {
    expect([
      AppRadii.small,
      AppRadii.control,
      AppRadii.card,
      AppRadii.modal,
      AppRadii.pill,
    ], [10, 16, 20, 28, 999]);
    expect([AppBorderWidths.standard, AppBorderWidths.emphasized], [1, 2]);
    expect([
      AppElevation.flat,
      AppElevation.raised,
      AppElevation.floating,
      AppElevation.modal,
    ], [0, 1, 3, 6]);
  });

  test('minimum sizes preserve comfortable touch targets', () {
    expect([
      AppSizes.touchTarget,
      AppSizes.buttonMinHeight,
      AppSizes.fieldMinHeight,
      AppSizes.chipMinHeight,
      AppSizes.badgeMinHeight,
      AppSizes.appBarMinHeight,
      AppSizes.navigationMinHeight,
    ], [48, 54, 56, 34, 28, 60, 70]);
    final theme = AppTheme.light;
    for (final style in [
      theme.filledButtonTheme.style!,
      theme.outlinedButtonTheme.style!,
    ]) {
      for (final states in [<WidgetState>{}, {WidgetState.disabled}]) {
        final size = style.minimumSize!.resolve(states)!;
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    }
  });

  test('motion and state layers match the P02 foundation', () {
    expect(AppMotion.instant, Duration.zero);
    expect(AppMotion.fast, const Duration(milliseconds: 120));
    expect(AppMotion.standard, const Duration(milliseconds: 180));
    expect(AppMotion.relaxed, const Duration(milliseconds: 260));
    expect(AppMotion.curve, Curves.easeOutCubic);
    expect([
      AppOpacity.transparent,
      AppOpacity.hover,
      AppOpacity.focus,
      AppOpacity.pressed,
      AppOpacity.dragged,
      AppOpacity.scrim,
      AppOpacity.mediaScrim,
      AppOpacity.opaque,
    ], [0, 0.08, 0.10, 0.10, 0.16, 0.40, 0.60, 1]);
  });
}
