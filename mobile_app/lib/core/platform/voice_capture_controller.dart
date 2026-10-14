import 'dart:async';
import 'package:flutter/widgets.dart';
import 'voice_input.dart';

enum VoicePhase { idle, preparing, listening, processing }

class VoiceCaptureController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceCaptureController(this.input) { WidgetsBinding.instance.addObserver(this); }
  final VoiceInput input;
  VoicePhase phase = VoicePhase.idle;
  String transcript = '';
  String? error;
  double level = 0;
  VoiceRecording? _recording;
  StreamSubscription<VoiceEvent>? _subscription;
  Timer? _timeout;
  Completer<String?>? _completion;
  bool _disposed = false;
  int _generation = 0;
  bool get active => phase != VoicePhase.idle;

  Future<String?> start() {
    if (active || _disposed) return Future.value();
    final generation = ++_generation;
    final completion = Completer<String?>();
    _completion = completion;
    phase = VoicePhase.preparing; transcript = ''; error = null; level = 0;
    notifyListeners();
    try {
      _recording = input.start();
      _subscription = _recording!.events.listen((event) {
        if (_disposed || generation != _generation || !active) return;
        switch (event.type) {
          case 'ready': if (phase != VoicePhase.processing) phase = VoicePhase.listening;
          case 'level': if (phase == VoicePhase.listening) level = event.level.clamp(0, 1).toDouble();
          case 'partial': transcript = _bounded(event.text);
          case 'processing': phase = VoicePhase.processing; level = 0;
          case 'final':
            transcript = _bounded(event.text);
            _finish(transcript.isEmpty ? null : transcript); return;
          case 'error': error = _message(event.code); _finish(null); return;
          case 'cancelled': transcript = ''; _finish(null); return;
        }
        notifyListeners();
      }, onError: (_) { if (generation == _generation && active) { error = _message(''); _finish(null); } },
      onDone: () { if (generation == _generation && active) { error = _message(''); _finish(null); } });
      _timeout = Timer(const Duration(seconds: 45), () {
        if (generation != _generation || !active) return;
        error = 'انتهى وقت الاستماع. اضغط المايك للمحاولة مرة أخرى.';
        final recording = _recording; _finish(null); unawaited(recording?.cancel() ?? Future.value());
      });
    } catch (_) { error = _message(''); _finish(null); }
    return completion.future;
  }

  String _bounded(String text) { final value = text.trim(); return value.length > 1500 ? value.substring(0, 1500) : value; }
  String _message(String code) => switch (code) {
    'SPEECH_PERMISSION' => 'اسمح باستخدام الميكروفون من إعدادات التطبيق، أو اكتب طلبك هنا.',
    'SPEECH_NO_MATCH' => 'لم نلتقط كلامًا واضحًا. حاول مرة أخرى أو اكتب طلبك.',
    'SPEECH_NETWORK' => 'تعذّر تفريغ الصوت. تحقق من الاتصال أو اكتب طلبك.',
    'SPEECH_BUSY' => 'الميكروفون مشغول الآن. حاول مرة أخرى بعد قليل.',
    _ => 'الصوت غير متاح الآن. يمكنك كتابة طلبك هنا.',
  };

  void _finish(String? result) {
    phase = VoicePhase.idle; level = 0;
    _timeout?.cancel(); _timeout = null;
    final completion = _completion; _completion = null;
    _recording = null;
    unawaited(_subscription?.cancel() ?? Future.value()); _subscription = null;
    if (completion != null && !completion.isCompleted) completion.complete(result);
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    if (!active) return;
    ++_generation;
    final recording = _recording;
    transcript = ''; error = null; _finish(null);
    unawaited(recording?.cancel() ?? Future.value());
  }

  void stop() { if (phase == VoicePhase.listening) unawaited(_recording?.stop() ?? Future.value()); }
  void clearError() { error = null; if (!_disposed) notifyListeners(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (const [AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.detached].contains(state) && phase != VoicePhase.preparing) cancel();
  }

  @override
  void dispose() {
    _disposed = true; cancel(); _timeout?.cancel();
    WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
}
