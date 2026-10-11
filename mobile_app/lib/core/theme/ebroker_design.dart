import 'package:flutter/material.dart';

// Exact design values from reference/ebroker-1.8.0, ui/theme/theme.dart.
// Brand green is the one identity substitution requested by the owner.
abstract final class EbrokerDesign {
  static const page = Color(0xFFFAFAFA);
  static const surface = Colors.white;
  static const templateBrand = Color(0xFF087C7C);
  static const text = Color(0xFF4D5454);
  static const textLight = Color(0x99000000);
  static const border = Color(0x99EEEEEE);
  static const controlRadius = 4.0;
  static const cardRadius = 8.0;
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
