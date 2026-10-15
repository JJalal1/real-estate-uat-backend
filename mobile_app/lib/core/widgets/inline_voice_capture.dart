import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../platform/voice_capture_controller.dart';
import 'ebroker_widgets.dart';

/// Rendered inside the existing search surface; never creates a route or popup.
class InlineVoiceCapture extends StatefulWidget {
  const InlineVoiceCapture({required this.capture, required this.onCancel, super.key});
  final VoiceCaptureController capture;
  final VoidCallback onCancel;
  @override
  State<InlineVoiceCapture> createState() => _InlineVoiceCaptureState();
}

class _InlineVoiceCaptureState extends State<InlineVoiceCapture> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _syncAnimation(); }
  @override
  void didUpdateWidget(InlineVoiceCapture oldWidget) { super.didUpdateWidget(oldWidget); _syncAnimation(); }
  void _syncAnimation() {
    if (!MediaQuery.disableAnimationsOf(context) && widget.capture.phase == VoicePhase.listening) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else { _pulse.stop(); _pulse.value = 0; }
  }
  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), capture = widget.capture;
    final listening = capture.phase == VoicePhase.listening;
    final label = switch (capture.phase) {
      VoicePhase.preparing => 'نجهّز الميكروفون…',
      VoicePhase.processing => 'نفرّغ التسجيل كاملًا…',
      _ => 'نستمع إليك الآن',
    };
    return Column(key: const ValueKey('inline-voice-capture'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(liveRegion: true, label: label, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
        AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(key: const ValueKey('voice-pulse'),
          width: 56, height: 56, margin: const EdgeInsetsDirectional.only(end: 12),
          decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary.withValues(alpha: .12),
            boxShadow: listening ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: .08 + .07 * _pulse.value),
              spreadRadius: 2 + 6 * _pulse.value, blurRadius: 4)] : const []),
          child: Transform.scale(scale: listening ? 1 + .08 * _pulse.value : 1,
            child: EbrokerIcon(Icons.mic_none, size: 28, color: theme.colorScheme.primary)))),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: theme.textTheme.titleSmall), const SizedBox(height: 7),
          ExcludeSemantics(child: SizedBox(height: 28, child: AnimatedBuilder(animation: _pulse, builder: (_, __) => Row(
            key: const ValueKey('voice-wave'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
              for (var i = 0; i < 13; i++) Container(width: 3, margin: const EdgeInsets.symmetric(horizontal: 2),
                height: listening ? 5 + 22 * (.2 + .8 * capture.level) * (.25 + .75 * math.sin(_pulse.value * math.pi + i * .6).abs()) : 5,
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: .45 + (i % 3) * .18), borderRadius: BorderRadius.circular(4))),
            ])))),
        ])),
      ]))),
      const SizedBox(height: 8),
      Container(key: const ValueKey('voice-transcript'), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(10)),
        child: Text(capture.transcript.isEmpty ? 'تحدث براحتك، ثم اضغط إنهاء التسجيل.' : capture.transcript,
          style: theme.textTheme.bodyMedium)),
      const SizedBox(height: 8),
      Wrap(spacing: 12, alignment: WrapAlignment.end, children: [
        TextButton.icon(key: const ValueKey('voice-cancel'), onPressed: widget.onCancel,
          icon: const EbrokerIcon(Icons.close, size: 18), label: const Text('إلغاء')),
        if (listening) TextButton(key: const ValueKey('voice-finish'), onPressed: capture.stop, child: const Text('إنهاء التسجيل')),
      ]),
    ]);
  }
}
