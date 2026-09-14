import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Save actual Flutter rendering with real shadows, restoring test globals
/// before the binding checks its invariants. Never alters production rendering.
Future<void> captureDesign(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CI'] != 'true') return;
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final previous = debugDisableShadows;
  try {
    debugDisableShadows = false;
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }
    repaint(boundary);
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/ui-qa')..createSync(recursive: true);
        await File('${directory.path}/$name.png').writeAsBytes(
          bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
  } finally {
    debugDisableShadows = previous;
  }
}
