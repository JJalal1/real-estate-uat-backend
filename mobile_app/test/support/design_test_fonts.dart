import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Real bundled Arabic and Material glyphs, plus the SDK's Roboto as the
/// Android Latin fallback. Flutter widget tests otherwise use Ahem squares.
/// Nothing here adds a font or a dependency to the application bundle.
Future<void> loadDesignTestFonts() async {
  final arabic = FontLoader('NotoSansArabic')
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
  await arabic.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();

  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final flutter = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'flutter');
  final packageDirectory = Directory.fromUri(
    configFile.uri.resolve(flutter['rootUri'] as String),
  );
  final sdkDirectory = packageDirectory.parent.parent;
  final latinFile = File(
    '${sdkDirectory.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  );
  final latin = ByteData.sublistView(await latinFile.readAsBytes());
  for (final family in ['Arial', 'sans-serif']) {
    final loader = FontLoader(family)..addFont(Future.value(latin));
    await loader.load();
  }
}
