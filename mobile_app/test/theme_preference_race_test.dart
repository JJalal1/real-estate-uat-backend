import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/theme/theme_controller.dart';

void main() {
  test('a delayed startup read cannot override an explicit theme choice', () async {
    final restore = Completer<String?>();
    final controller = AppThemeModeController(
      loadPreference: () => restore.future,
      savePreference: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.setMode(ThemeMode.dark);
    restore.complete('light');
    await Future<void>.delayed(Duration.zero);

    expect(controller.debugState, ThemeMode.dark);
  });

  test('writes are ordered and a failed save does not prevent later choices', () async {
    final first = Completer<void>();
    final started = Completer<void>();
    final saved = <String>[];
    var calls = 0;
    final controller = AppThemeModeController(
      loadPreference: () async => null,
      savePreference: (value) async {
        saved.add(value);
        calls++;
        if (calls == 1) {
          started.complete();
          await first.future;
          throw const FileSystemException('synthetic write failure');
        }
      },
    );
    addTearDown(controller.dispose);

    final one = controller.setMode(ThemeMode.light);
    await started.future;
    final two = controller.setMode(ThemeMode.dark);
    expect(saved, ['light']);
    first.complete();
    await Future.wait([one, two]);

    expect(saved, ['light', 'dark']);
    expect(controller.debugState, ThemeMode.dark);
  });
}
