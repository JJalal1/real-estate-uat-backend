import 'package:flutter/services.dart';

class Stage5MediaPicker {
  const Stage5MediaPicker();

  static const MethodChannel _channel = MethodChannel('real_estate/media');

  Future<List<String>> pickImages() async {
    final result = await _channel.invokeListMethod<String>('pickImages');
    return (result ?? const <String>[])
        .where((path) => path.trim().isNotEmpty)
        .take(12)
        .toList(growable: false);
  }

  Future<void> clearTemporaryFiles(Iterable<String> paths) async {
    final values = paths
        .where((path) => path.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (values.isEmpty) return;

    await _channel.invokeMethod<void>(
      'clearTemporaryFiles',
      <String, dynamic>{'paths': values},
    );
  }
}
