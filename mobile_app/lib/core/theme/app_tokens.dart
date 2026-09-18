import 'package:flutter/animation.dart';

abstract final class AppSpacing {
  static const double none = 0;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;
}

abstract final class AppLayout {
  static const double compactPageGutter = AppSpacing.s16;
  static const double widePageGutter = AppSpacing.s24;
  static const double narrowBreakpoint = 360;
  static const double wideBreakpoint = 600;
  static const double contentMaxWidth = 760;
  static const double sectionGap = AppSpacing.s28;
  static const double groupGap = AppSpacing.s20;
  static const double itemGap = AppSpacing.s12;
  static const double fieldGap = AppSpacing.s16;
  static const double inlineGap = AppSpacing.s8;
  static const double surfacePadding = AppSpacing.s16;
  static const double compactSurfacePadding = AppSpacing.s12;
  static const double dialogPadding = AppSpacing.s24;
}

abstract final class AppRadii {
  static const double small = 10;
  static const double control = 16;
  static const double card = 20;
  static const double modal = 28;
  static const double pill = 999;
}

abstract final class AppBorderWidths {
  static const double standard = 1;
  static const double emphasized = 2;
}

abstract final class AppElevation {
  static const double flat = 0;
  static const double raised = 1;
  static const double floating = 3;
  static const double modal = 6;
}

abstract final class AppSizes {
  static const double touchTarget = 48;
  static const double buttonMinHeight = 54;
  static const double fieldMinHeight = 56;
  static const double chipMinHeight = 34;
  static const double badgeMinHeight = 28;
  static const double appBarMinHeight = 60;
  static const double navigationMinHeight = 70;
}

abstract final class AppMotion {
  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration relaxed = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;
}

abstract final class AppOpacity {
  static const double transparent = 0;
  static const double hover = 0.08;
  static const double focus = 0.10;
  static const double pressed = 0.10;
  static const double dragged = 0.16;
  static const double scrim = 0.40;
  static const double mediaScrim = 0.60;
  static const double opaque = 1;
}
