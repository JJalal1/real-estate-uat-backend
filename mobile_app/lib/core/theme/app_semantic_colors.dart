import 'package:flutter/material.dart';

/// Presentation tones, not domain statuses or authorization decisions.
/// Pair each tone with its explicit foreground/container roles and a visible
/// text/icon state cue. Color never grants capability or workflow state.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.neutral,
    required this.onNeutral,
    required this.neutralContainer,
    required this.onNeutralContainer,
    required this.disabledContainer,
    required this.onDisabledContainer,
    required this.disabledOutline,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF176B3A),
    onSuccess: Colors.white,
    successContainer: Color(0xFFEAF6ED),
    onSuccessContainer: Color(0xFF14532D),
    warning: Color(0xFF805700),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFFF4D6),
    onWarningContainer: Color(0xFF663C00),
    info: Color(0xFF1778B8),
    onInfo: Colors.white,
    infoContainer: Color(0xFFE7F2FA),
    onInfoContainer: Color(0xFF0D4D75),
    neutral: Color(0xFF505B65),
    onNeutral: Colors.white,
    neutralContainer: Color(0xFFF0F3F4),
    onNeutralContainer: Color(0xFF505B65),
    disabledContainer: Color(0xFFE7ECEF),
    onDisabledContainer: Color(0xFF66737D),
    disabledOutline: Color(0xFFC9D2D7),
    skeletonBase: Color(0xFFE1E7EA),
    skeletonHighlight: Color(0xFFF0F3F4),
  );

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color neutral;
  final Color onNeutral;
  final Color neutralContainer;
  final Color onNeutralContainer;
  final Color disabledContainer;
  final Color onDisabledContainer;
  final Color disabledOutline;
  final Color skeletonBase;
  final Color skeletonHighlight;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? neutral,
    Color? onNeutral,
    Color? neutralContainer,
    Color? onNeutralContainer,
    Color? disabledContainer,
    Color? onDisabledContainer,
    Color? disabledOutline,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      neutral: neutral ?? this.neutral,
      onNeutral: onNeutral ?? this.onNeutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      onNeutralContainer: onNeutralContainer ?? this.onNeutralContainer,
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
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      onNeutral: Color.lerp(onNeutral, other.onNeutral, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
      onNeutralContainer:
          Color.lerp(onNeutralContainer, other.onNeutralContainer, t)!,
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
