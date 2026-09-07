import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';

void main() {
  test('spacing and layout match the accepted scale', () {
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
    ], [16, 24, 360, 600, 840, 32, 24, 12, 16, 8, 16, 12, 24]);
  });

  test('shape and elevation match the accepted scale', () {
    expect([
      AppRadii.small,
      AppRadii.control,
      AppRadii.card,
      AppRadii.modal,
      AppRadii.pill,
    ], [8, 12, 16, 24, 999]);
    expect([AppBorderWidths.standard, AppBorderWidths.emphasized], [1, 2]);
    expect([
      AppElevation.flat,
      AppElevation.raised,
      AppElevation.floating,
      AppElevation.modal,
    ], [0, 1, 3, 6]);
  });

  test('minimum sizes and existing themed buttons preserve touch targets', () {
    expect([
      AppSizes.touchTarget,
      AppSizes.buttonMinHeight,
      AppSizes.fieldMinHeight,
      AppSizes.chipMinHeight,
      AppSizes.badgeMinHeight,
      AppSizes.appBarMinHeight,
      AppSizes.navigationMinHeight,
    ], [48, 48, 56, 32, 28, 64, 80]);
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

  test('motion and state layers provide bounded scaffolding defaults', () {
    expect(AppMotion.none, Duration.zero);
    expect([
      AppMotion.short.inMilliseconds,
      AppMotion.medium.inMilliseconds,
      AppMotion.long.inMilliseconds,
    ], [150, 250, 350]);
    for (final curve in [AppMotion.standard, AppMotion.enter, AppMotion.exit]) {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    }
    expect([
      AppOpacity.transparent,
      AppOpacity.hover,
      AppOpacity.focus,
      AppOpacity.pressed,
      AppOpacity.dragged,
      AppOpacity.scrim,
      AppOpacity.opaque,
    ], [0, 0.08, 0.12, 0.12, 0.16, 0.32, 1]);
  });
}
