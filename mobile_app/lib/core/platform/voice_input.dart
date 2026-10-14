import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoiceEvent {
  const VoiceEvent(this.type, {this.text = '', this.level = 0, this.code = ''});
  final String type, text, code;
  final double level;
}

abstract class VoiceRecording {
  Stream<VoiceEvent> get events;
  Future<void> cancel();
  Future<void> stop();
}

abstract class VoiceInput {
  VoiceRecording start();
}

class SystemVoiceInput implements VoiceInput {
  @override
  VoiceRecording start() => _NativeVoiceRecording();
}

class _NativeVoiceRecording implements VoiceRecording {
  static const _channel = MethodChannel('real_estate/speech');
  static int _sequence = 0;
  static _NativeVoiceRecording? _active;
  final int _id = ++_sequence;
  late final _events = StreamController<VoiceEvent>(onListen: () => unawaited(_start()));
  bool _ended = false;
  @override
  Stream<VoiceEvent> get events => _events.stream;

  Future<void> _start() async {
    if (_ended) return;
    if (_active != null) { _finish(const VoiceEvent('error', code: 'SPEECH_BUSY')); return; }
    _active = this;
    _channel.setMethodCallHandler((call) async {
      final raw = call.arguments;
      final current = _active;
      if (call.method != 'event' || raw is! Map || current == null || raw['id'] != current._id) return;
      final event = VoiceEvent(raw['type']?.toString() ?? '',
        text: raw['text']?.toString() ?? '', code: raw['code']?.toString() ?? '',
        level: (raw['level'] is num ? (raw['level'] as num).toDouble() : 0).clamp(0, 1).toDouble());
      if (const ['final', 'error', 'cancelled'].contains(event.type)) { current._finish(event); }
      else if (!current._ended) { current._events.add(event); }
    });
    try { await _channel.invokeMethod<void>('start', {'id': _id}); }
    on PlatformException catch (error) { _finish(VoiceEvent('error', code: error.code)); }
    catch (_) { _finish(const VoiceEvent('error', code: 'SPEECH_UNAVAILABLE')); }
  }

  void _finish(VoiceEvent event) {
    if (_ended) return;
    _ended = true;
    if (identical(_active, this)) _active = null;
    _events.add(event);
    unawaited(_events.close());
  }

  @override
  Future<void> cancel() async {
    if (_ended) return;
    final owned = identical(_active, this);
    _finish(const VoiceEvent('cancelled'));
    if (owned) { try { await _channel.invokeMethod<void>('cancel', {'id': _id}); } catch (_) {} }
  }

  @override
  Future<void> stop() async {
    if (_ended || !identical(_active, this)) return;
    try { await _channel.invokeMethod<void>('stop', {'id': _id}); }
    catch (_) { await cancel(); }
  }
}

final voiceInputProvider = Provider<VoiceInput>((ref) => SystemVoiceInput());
