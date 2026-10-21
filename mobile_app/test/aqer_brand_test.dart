import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/branding/aqer_brand.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';

Future<Uint8List> _mark(WidgetTester tester, TextDirection direction) async {
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Center(
    child: RepaintBoundary(key: key, child: Directionality(textDirection: direction,
      child: const SizedBox.square(dimension: 144, child: AqerBrandMark(size: 144)))),
  )));
  await tester.pumpAndSettle();
  return tester.runAsync(() async {
    final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }).then((bytes) => bytes!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('approved house and Yemen identity renders identically in RTL and LTR', (tester) async {
    final ltr = await _mark(tester, TextDirection.ltr);
    final rtl = await _mark(tester, TextDirection.rtl);
    expect(rtl, orderedEquals(ltr));
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded account loading stays visible on narrow enlarged Arabic without a launch timer', (tester) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2.4)), child: child!),
      home: RepaintBoundary(key: key, child: const Scaffold(body: Directionality(
        textDirection: TextDirection.rtl, child: AqerAccountLoading())))));
    // The only animation is the existing progress state, so do not wait for idle.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AqerBrandWordmark), findsOneWidget);
    expect(find.bySemanticsLabel('عقار Aqer'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/wave2-preview/aqer-loading-2.4.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    } finally {
      // Flutter verifies semantics handles before addTearDown callbacks run.
      semantics.dispose();
    }
  });
}
