import 'package:flutter/animation.dart';

/// AQER's second visual identity, الفخامة الحيوية.
abstract final class AppPalette {
  static const petrol = Color(0xFF123F42);
  static const sand = Color(0xFFC5A46D);
  static const yellow = Color(0xFFF5CB53);
  static const paleYellow = Color(0xFFFFF3CA);
  static const ivory = Color(0xFFF7F4EE);
  static const turquoise = Color(0xFF0B817A);
  static const coral = Color(0xFFE86A43);
  static const peach = Color(0xFFFFEEE7);
  static const paleTurquoise = Color(0xFFE0F3F0);
  static const copper = Color(0xFFB4482C);
  static const paper = Color(0xFFFFFFFF);
  static const charcoal = Color(0xFF202C2D);
  static const slate = Color(0xFF5F6B6D);
  static const stone = Color(0xFFE3E0D8);
  static const pressedPetrol = Color(0xFF0B2D30);
  static const inputBorder = Color(0xFF7A8784);
  static const mist = Color(0xFFE7EFEC);
}

/// Shared logical-pixel tokens from PHASE1_ACCEPTED_DESIGN_SYSTEM.md.
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
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;
}

/// Use directional insets/alignment when applying these layout values.
abstract final class AppLayout {
  static const double compactPageGutter = 18;
  static const double widePageGutter = 18;
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
  static const double control = 10;
  static const double card = 12;
  static const double modal = 18;
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
  static const double buttonMinHeight = 52;

  /// Excludes helper and error text.
  static const double fieldMinHeight = 48;

  /// Visual height only; interactive chips still need [touchTarget].
  static const double chipMinHeight = 32;
  static const double badgeMinHeight = 28;

  /// Add the system inset; allow content to grow.
  static const double appBarMinHeight = 56;

  /// Add the system inset and grow for scaled or wrapped labels.
  static const double navigationMinHeight = 76;
}

/// Accepted interaction timing. Respect reduced-motion settings by using
/// [instant] when the platform requests reduced animation.
abstract final class AppMotion {
  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Curve curve = Curves.easeOutCubic;
}

/// Accepted Material state-layer and modal opacity values.
/// Use semantic disabled colors rather than fading a whole content subtree.
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
