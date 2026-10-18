import 'package:flutter/material.dart';

// October19 owner-authorized refresh. Retain original assets and brand recognition.
abstract final class EbrokerDesign {
  static const page = Color(0xFFF5F7FA);
  static const surface = Colors.white;
  static const templateBrand = Color(0xFF087C7C);
  static const text = Color(0xFF192F48);
  static const textLight = Color(0xFF64748B);
  static const border = Color(0xFFE3EAF1);
  static const controlRadius = 16.0;
  static const cardRadius = 22.0;
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
