import 'package:flutter/material.dart';

import 'app_tokens.dart';

// October19 owner-authorized refresh. Retain original assets and brand recognition.
abstract final class EbrokerDesign {
  static const page = AppPalette.ivory;
  static const surface = AppPalette.paper;
  static const templateBrand = AppPalette.petrol;
  static const text = AppPalette.charcoal;
  static const textLight = AppPalette.slate;
  static const border = AppPalette.stone;
  static const controlRadius = AppRadii.control;
  static const cardRadius = AppRadii.card;
  static const pageGutter = 18.0;
}

// Copied device breakpoints/scales from utils/responsive_size.dart.
extension EbrokerSizing on num {
  double rh(BuildContext context) => this * _scale(context, 0.9, 1, 1.3, 1.5);
  double rw(BuildContext context) => rh(context);
  double rf(BuildContext context) => this * _scale(context, 0.75, 1, 1.2, 1.3);
  double rs(BuildContext context) => this * _scale(context, 0.9, 1, 1.5, 2.5);
  double _scale(BuildContext context, double small, double phone, double tablet, double large) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    return shortest >= 900 ? large : shortest >= 600 ? tablet : shortest >= 300 ? phone : small;
  }
}
