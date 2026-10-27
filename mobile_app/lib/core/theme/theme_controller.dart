import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final appThemeModeProvider =
    StateNotifierProvider<AppThemeModeController, ThemeMode>((ref) {
  return AppThemeModeController();
});

class AppThemeModeController extends StateNotifier<ThemeMode> {
  AppThemeModeController({
    Future<String?> Function()? loadPreference,
    Future<void> Function(String)? savePreference,
  })  : _loadPreference = loadPreference ?? _readPreference,
        _savePreference = savePreference ?? _writePreference,
        super(ThemeMode.system) {
    unawaited(_load());
  }

  final Future<String?> Function() _loadPreference;
  final Future<void> Function(String) _savePreference;

  int _selectionRevision = 0;
  Future<void> _pendingWrite = Future<void>.value();

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/aqer_theme_mode.txt');
  }

  static Future<String?> _readPreference() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return (await file.readAsString()).trim();
  }

  static Future<void> _writePreference(String value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  Future<void> _load() async {
    final revision = _selectionRevision;
    try {
      final value = await _loadPreference();
      // An old disk read must never undo a choice made since startup.
      if (!mounted || _selectionRevision != revision) return;
      state = switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Keep the current choice when preference storage is unavailable.
    }
  }

  Future<void> setMode(ThemeMode mode) {
    if (!mounted) return Future<void>.value();
    _selectionRevision++;
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };

    // Serialize saves so a slow earlier write cannot overwrite a later choice.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await _savePreference(value);
      } catch (_) {
        // An IO error must neither block the UI nor poison subsequent writes.
      }
    });
    return _pendingWrite;
  }
}
