import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class VoiceInput {
  Future<String?> recognize();
}

class SystemVoiceInput implements VoiceInput {
  static const _channel = MethodChannel('real_estate/speech');
  @override
  Future<String?> recognize() => _channel.invokeMethod<String>('recognize');
}

final voiceInputProvider = Provider<VoiceInput>((ref) => SystemVoiceInput());
