import 'dart:async';
import 'package:flutter/widgets.dart';
import 'voice_input.dart';

enum VoicePhase { idle, preparing, listening, processing }

class VoiceCaptureController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceCaptureController(this.input) { WidgetsBinding.instance.addObserver(this); }
  final VoiceInput input;
  VoicePhase phase = VoicePhase.idle;
  String transcript = '';
  String preview = '';
  bool liveDictation = false;
  String? error;
  double level = 0;
  VoiceRecording? _recording;
  StreamSubscription<VoiceEvent>? _subscription;
  Timer? _timeout;
  Timer? _clock;
  Duration elapsed = Duration.zero;
  Completer<String?>? _completion;
  bool _disposed = false;
  int _generation = 0;
  bool _stopRequested = false;
  bool get active => phase != VoicePhase.idle;
  bool get canRetry => !active && _recording is RetryableVoiceRecording && (_recording! as RetryableVoiceRecording).canRetry;

  Future<String?> start({bool wholeRecording = false}) {
    if (active || _disposed) return Future.value();
    if (canRetry) cancel();
    final generation = ++_generation;
    final completion = Completer<String?>();
    _completion = completion;
    _stopRequested = false;
    phase = VoicePhase.preparing; transcript = ''; preview = ''; liveDictation = false; error = null; level = 0;
    elapsed = Duration.zero;
    notifyListeners();
    try {
      _recording = wholeRecording && input is SystemVoiceInput ? (input as SystemVoiceInput).startWholeRecording() : input.start();
      _subscription = _recording!.events.listen((event) {
        if (_disposed || generation != _generation || !active) return;
        switch (event.type) {
          case 'ready':
            if (phase != VoicePhase.processing) {
              phase = VoicePhase.listening;
              _clock ??= Timer.periodic(const Duration(seconds: 1), (timer) {
                if (!_disposed && phase == VoicePhase.listening) { elapsed = Duration(seconds: timer.tick); notifyListeners(); }
              });
            }
          case 'level': if (phase == VoicePhase.listening) level = event.level.clamp(0, 1).toDouble();
          case 'mode': liveDictation = event.code == 'dictation';
          case 'partial':
            if (phase != VoicePhase.listening || _stopRequested) return;
            if (event.text.length > 5000) {
              error = _message('SPEECH_TOO_LONG');
              final recording = _recording; _finish(null); unawaited(recording?.cancel() ?? Future.value()); return;
            }
            preview = event.text;
          case 'processing': if (!_stopRequested) return; phase = VoicePhase.processing; level = 0;
          case 'final':
            if (!_stopRequested) return;
            transcript = event.text.trim();
            if (transcript.length > 5000) { error = _message('SPEECH_TOO_LONG'); _finish(null); return; }
            _finish(transcript.isEmpty ? null : transcript); return;
          case 'error': error = _message(event.code); _finish(null); return;
          case 'retryable_error':
            error = 'تعذّر تفريغ الصوت. التسجيل محفوظ؛ أعد محاولة التفريغ.';
            _finish(null, retainRecording: true); return;
          case 'cancelled': transcript = ''; preview = ''; _finish(null); return;
        }
        notifyListeners();
      }, onError: (_) { if (generation == _generation && active) { error = _message(''); _finish(null); } },
      onDone: () { if (generation == _generation && active) { error = _message(''); _finish(null); } });
    } catch (_) { error = _message(''); _finish(null); }
    return completion.future;
  }

  String _message(String code) => switch (code) {
    'SPEECH_PERMISSION' => 'اسمح باستخدام الميكروفون من إعدادات التطبيق، أو اكتب طلبك هنا.',
    'SPEECH_NO_MATCH' => 'لم نلتقط كلامًا واضحًا. حاول مرة أخرى أو اكتب طلبك.',
    'SPEECH_NETWORK' => 'تعذّر تفريغ الصوت. تحقق من الاتصال أو اكتب طلبك.',
    'SPEECH_TOO_LARGE' || 'SPEECH_TOO_LONG' => 'التسجيل أطول من الحد الذي يمكن معالجته. لم ننفذ جزءًا منه؛ اختصر الطلب وأعد التسجيل.',
    'SPEECH_BUSY' => 'الميكروفون مشغول الآن. حاول مرة أخرى بعد قليل.',
    _ => 'الصوت غير متاح الآن. يمكنك كتابة طلبك هنا.',
  };

  void _finish(String? result, {bool retainRecording = false}) {
    phase = VoicePhase.idle; level = 0;
    _timeout?.cancel(); _timeout = null;
    _clock?.cancel(); _clock = null;
    final completion = _completion; _completion = null;
    if (!retainRecording) {
      _recording = null;
      unawaited(_subscription?.cancel() ?? Future.value()); _subscription = null;
    }
    if (completion != null && !completion.isCompleted) completion.complete(result);
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    if (!active && !canRetry) return;
    ++_generation;
    final recording = _recording;
    transcript = ''; preview = ''; error = null; _finish(null);
    unawaited(recording?.cancel() ?? Future.value());
  }

  void stop() {
    if (phase != VoicePhase.listening || _stopRequested) return;
    _stopRequested = true;
    phase = VoicePhase.processing; level = 0;
    _clock?.cancel(); _clock = null;
    _armTimeout();
    notifyListeners();
    unawaited(_recording?.stop() ?? Future.value());
  }

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(minutes: 3), () {
      if (!active) return;
      final saved = _recording;
      if (saved is RetryableVoiceRecording && saved.canRetry) {
        saved.interruptTranscription();
        error = 'استغرق التفريغ وقتًا طويلًا. التسجيل محفوظ؛ أعد المحاولة.';
        _finish(null, retainRecording: true); return;
      }
      error = 'تعذّر إكمال تفريغ التسجيل. لم تُطبّق أي معلومات؛ يمكنك إعادة التسجيل أو كتابة التفاصيل.';
      final recording = _recording; _finish(null); unawaited(recording?.cancel() ?? Future.value());
    });
  }

  Future<String?> retryTranscription() {
    if (!canRetry || _disposed) return Future.value();
    final recording = _recording! as RetryableVoiceRecording;
    final completion = Completer<String?>();
    _completion = completion; _stopRequested = true;
    phase = VoicePhase.processing; error = null; level = 0;
    _armTimeout(); notifyListeners();
    unawaited(recording.retryTranscription());
    return completion.future;
  }
  void clearError() { error = null; if (!_disposed) notifyListeners(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (const [AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.detached].contains(state) && phase != VoicePhase.preparing) cancel();
  }

  @override
  void dispose() {
    _disposed = true; cancel(); _timeout?.cancel(); _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
}
