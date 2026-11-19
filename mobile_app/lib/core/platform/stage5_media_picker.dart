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

  Future<String?> takePhoto() async {
    final path = await _channel.invokeMethod<String>('takePhoto');
    if (path == null || path.trim().isEmpty) return null;
    return path;
  }

  Future<Map<String, double>> labelListingPhoto(String path) async {
    final labels = await _channel.invokeMapMethod<String, double>(
      'labelListingPhoto',
      <String, dynamic>{'path': path},
    );
    if (labels == null) {
      throw PlatformException(code: 'LISTING_PHOTO_CHECK_UNAVAILABLE');
    }
    return labels;
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
