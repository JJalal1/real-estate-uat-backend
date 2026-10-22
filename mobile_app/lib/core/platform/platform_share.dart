import 'package:flutter/services.dart';

class PlatformShare {
  PlatformShare._();

  static const MethodChannel _channel = MethodChannel('real_estate/share');

  static Future<void> text({
    required String text,
    String? subject,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await _channel.invokeMethod<void>('shareText', <String, dynamic>{
      'text': value,
      if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
    });
  }
}
