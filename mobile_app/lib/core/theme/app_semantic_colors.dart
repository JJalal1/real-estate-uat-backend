import 'package:flutter/material.dart';

/// Presentation tones, not domain statuses or authorization decisions.
/// Pair each tone with its container and a visible text/icon state cue.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.info,
    required this.infoContainer,
    required this.neutral,
    required this.neutralContainer,
    required this.disabledContainer,
    required this.onDisabledContainer,
    required this.disabledOutline,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  /// W3A specifies these roles without hex values. These light defaults reuse
  /// the accepted green/blue/neutral palette, with readable warning tones.
  /// The enabled tone/container pairs meet 4.5:1 text contrast.
  static const light = AppSemanticColors(
    success: Color(0xFF075B39),
    successContainer: Color(0xFFE5F5EC),
    warning: Color(0xFF805600),
    warningContainer: Color(0xFFFFF4D6),
    info: Color(0xFF0D4D75),
    infoContainer: Color(0xFFE7F2FA),
    neutral: Color(0xFF505B65),
    neutralContainer: Color(0xFFF0F3F4),
    disabledContainer: Color(0xFFE7ECEF),
    onDisabledContainer: Color(0xFF78858F),
    disabledOutline: Color(0xFFC9D2D7),
    skeletonBase: Color(0xFFE7ECEF),
    skeletonHighlight: Color(0xFFF5F7F8),
  );

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color info;
  final Color infoContainer;
  final Color neutral;
  final Color neutralContainer;
  final Color disabledContainer;
  final Color onDisabledContainer;
  final Color disabledOutline;
  final Color skeletonBase;
  final Color skeletonHighlight;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? info,
    Color? infoContainer,
    Color? neutral,
    Color? neutralContainer,
    Color? disabledContainer,
    Color? onDisabledContainer,
    Color? disabledOutline,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      disabledContainer: disabledContainer ?? this.disabledContainer,
      onDisabledContainer: onDisabledContainer ?? this.onDisabledContainer,
      disabledOutline: disabledOutline ?? this.disabledOutline,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;

    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
      disabledContainer:
          Color.lerp(disabledContainer, other.disabledContainer, t)!,
      onDisabledContainer:
          Color.lerp(onDisabledContainer, other.onDisabledContainer, t)!,
      disabledOutline: Color.lerp(disabledOutline, other.disabledOutline, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight:
          Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
    );
  }
}
