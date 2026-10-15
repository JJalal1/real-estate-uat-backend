import 'dart:async';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
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

typedef VoiceTranscriber = Future<String> Function(String path, CancelToken token);

class SystemVoiceInput implements VoiceInput {
  SystemVoiceInput({this.transcribe});
  final VoiceTranscriber? transcribe;
  @override
  VoiceRecording start() => _NativeVoiceRecording(transcribe);
}

class _NativeVoiceRecording implements VoiceRecording {
  _NativeVoiceRecording(this._transcribe);
  final VoiceTranscriber? _transcribe;
  final _cancelToken = CancelToken();
  bool _stopping = false, _transcribing = false;
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
      if (raw['type'] == 'recorded') {
        if (current._stopping && !current._transcribing && raw['path'] is String) unawaited(current._completeClip(raw['path'] as String));
        return;
      }
      if (raw['type'] == 'partial' || raw['type'] == 'final') return;
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

  Future<void> _completeClip(String path) async {
    if (_ended || _transcribing || !_stopping) return;
    _transcribing = true;
    _events.add(const VoiceEvent('processing'));
    VoiceEvent outcome;
    try {
      if (_transcribe == null) throw StateError('Transcription not configured');
      final text = (await _transcribe!(path, _cancelToken)).trim();
      outcome = text.isEmpty ? const VoiceEvent('error', code: 'SPEECH_NO_MATCH') : VoiceEvent('final', text: text);
    } on DioException catch (error) {
      outcome = VoiceEvent('error', code: error.response?.statusCode == 413 ? 'SPEECH_TOO_LARGE' : 'SPEECH_NETWORK');
    } catch (_) { outcome = const VoiceEvent('error', code: 'SPEECH_UNAVAILABLE'); }
    finally { try { await _channel.invokeMethod<void>('release', {'id': _id}); } catch (_) {} }
    if (!_ended) _finish(outcome);
  }

  void _finish(VoiceEvent event) {
    if (_ended) return;
    _ended = true;
    if (event.type != 'final') _cancelToken.cancel('Recording ended');
    if (identical(_active, this)) _active = null;
    _events.add(event);
    unawaited(_events.close());
  }

  @override
  Future<void> cancel() async {
    if (_ended) return;
    final owned = identical(_active, this);
    _cancelToken.cancel('Voice cancelled');
    _finish(const VoiceEvent('cancelled'));
    if (owned) { try { await _channel.invokeMethod<void>('cancel', {'id': _id}); } catch (_) {} }
  }

  @override
  Future<void> stop() async {
    if (_ended || !identical(_active, this) || _stopping) return;
    _stopping = true;
    try { await _channel.invokeMethod<void>('stop', {'id': _id}); }
    catch (_) { await cancel(); }
  }
}

final voiceInputProvider = Provider<VoiceInput>((ref) {
  final dio = ref.watch(dioProvider);
  return SystemVoiceInput(transcribe: (path, token) async {
    final audio = await MultipartFile.fromFile(path, filename: 'speech.m4a');
    final response = await dio.post<Map<String, dynamic>>('/ai/transcribe',
      data: FormData.fromMap({'audio': audio}), cancelToken: token,
      options: Options(sendTimeout: const Duration(seconds: 90), receiveTimeout: const Duration(seconds: 90)));
    final data = response.data?['data'];
    if (data is! Map || data['transcript'] is! String || data['complete'] != true) throw StateError('Incomplete transcription');
    return data['transcript'] as String;
  });
});
