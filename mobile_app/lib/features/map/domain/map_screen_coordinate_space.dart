import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class MapScreenCoordinateSpace {
  const MapScreenCoordinateSpace._();

  static math.Point<num> logicalToPlatformPixels(
    Offset logicalPoint,
    double devicePixelRatio,
  ) {
    final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    return math.Point<num>(
      logicalPoint.dx * ratio,
      logicalPoint.dy * ratio,
    );
  }

  static Offset platformPixelsToLogical(
    math.Point<num> platformPoint,
    double devicePixelRatio,
  ) {
    final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    return Offset(
      platformPoint.x.toDouble() / ratio,
      platformPoint.y.toDouble() / ratio,
    );
  }
}
