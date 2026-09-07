import 'package:flutter/animation.dart';

/// Shared logical-pixel tokens from PHASE1_ACCEPTED_DESIGN_SYSTEM.md.
abstract final class AppSpacing {
  static const double none = 0;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;
}

/// Use directional insets/alignment when applying these layout values.
abstract final class AppLayout {
  static const double compactPageGutter = AppSpacing.s16;
  static const double widePageGutter = AppSpacing.s24;
  static const double narrowBreakpoint = 360;
  static const double wideBreakpoint = 600;
  static const double contentMaxWidth = 840;
  static const double sectionGap = AppSpacing.s32;
  static const double groupGap = AppSpacing.s24;
  static const double itemGap = AppSpacing.s12;
  static const double fieldGap = AppSpacing.s16;
  static const double inlineGap = AppSpacing.s8;
  static const double surfacePadding = AppSpacing.s16;
  static const double compactSurfacePadding = AppSpacing.s12;
  static const double dialogPadding = AppSpacing.s24;
}

abstract final class AppRadii {
  static const double small = 8;
  static const double control = 12;
  static const double card = 16;
  static const double modal = 24;
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

/// Minimums, never fixed heights for content-bearing surfaces.
abstract final class AppSizes {
  /// Applies to both width and height of every independent action.
  static const double touchTarget = 48;
  static const double buttonMinHeight = 48;

  /// Excludes helper and error text.
  static const double fieldMinHeight = 56;

  /// Visual height only; interactive chips still need [touchTarget].
  static const double chipMinHeight = 32;
  static const double badgeMinHeight = 28;

  /// Add the system inset; allow content to grow.
  static const double appBarMinHeight = 64;

  /// Add the system inset and grow for scaled or wrapped labels.
  static const double navigationMinHeight = 80;
}

/// Scaffolding defaults: W3A names motion but does not prescribe durations.
/// Consumers must use [none] when platform accessibility disables animations.
abstract final class AppMotion {
  static const Duration none = Duration.zero;
  static const Duration short = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration long = Duration(milliseconds: 350);
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Material state-layer defaults where W3A does not specify numeric opacity.
/// Use semantic disabled colors, rather than fading a whole content subtree.
abstract final class AppOpacity {
  static const double transparent = 0;
  static const double hover = 0.08;
  static const double focus = 0.12;
  static const double pressed = 0.12;
  static const double dragged = 0.16;
  static const double scrim = 0.32;
  static const double opaque = 1;
}
