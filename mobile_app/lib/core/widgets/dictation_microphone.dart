import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../platform/voice_capture_controller.dart';
import 'ebroker_widgets.dart';

class DictationMicrophone extends StatelessWidget {
  const DictationMicrophone({
    required this.capture,
    required this.buttonKey,
    required this.ringKey,
    required this.idleLabel,
    required this.enabled,
    required this.onStart,
    required this.onCancelPreparing,
    this.compact = false,
    super.key,
  });

  final VoiceCaptureController capture;
  final Key buttonKey, ringKey;
  final String idleLabel;
  final bool enabled, compact;
  final VoidCallback onStart, onCancelPreparing;

  @override
  Widget build(BuildContext context) {
    final phase = capture.phase;
    return SizedBox.square(
      dimension: compact ? 48 : 56,
      child: Stack(alignment: Alignment.center, children: [
        if (phase == VoicePhase.listening)
          Positioned.fill(child: IgnorePointer(child: CustomPaint(
            key: ringKey,
            painter: _VoiceRingPainter(Theme.of(context).colorScheme.primary, capture.level),
          ))),
        IconButton.filledTonal(
          key: buttonKey,
          tooltip: switch (phase) {
            VoicePhase.idle => idleLabel,
            VoicePhase.preparing || VoicePhase.listening => 'إيقاف الإملاء',
            VoicePhase.processing => 'جارٍ تفريغ الصوت',
          },
          onPressed: enabled ? switch (phase) {
            VoicePhase.idle => onStart,
            VoicePhase.preparing => onCancelPreparing,
            VoicePhase.listening => capture.stop,
            VoicePhase.processing => null,
          } : null,
          icon: const EbrokerIcon(Icons.mic_none_outlined, size: 22),
        ),
      ]),
    );
  }
}

class DictationFeedback extends StatelessWidget {
  const DictationFeedback({
    required this.capture,
    required this.onRetry,
    required this.retryKey,
    super.key,
  });

  final VoiceCaptureController capture;
  final VoidCallback? onRetry;
  final Key retryKey;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    if (capture.phase == VoicePhase.listening) {
      final elapsed = capture.elapsed;
      final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
      final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          Text('$minutes:$seconds', textDirection: TextDirection.ltr, style: style),
          Text('اضغط الميكروفون مرة أخرى أو توقّف عن الكلام ٣ ثوانٍ.', style: style),
        ]),
      );
    }
    if (capture.phase == VoicePhase.processing) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('جارٍ تفريغ الصوت…', style: style),
      );
    }
    if (capture.canRetry) {
      return TextButton(key: retryKey, onPressed: onRetry, child: const Text('إعادة محاولة التفريغ'));
    }
    return const SizedBox.shrink();
  }
}

class _VoiceRingPainter extends CustomPainter {
  const _VoiceRingPainter(this.color, this.level);

  final Color color;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = 2;
    for (var i = 0; i < 18; i++) {
      final angle = i * math.pi / 9;
      final variation = .5 + .5 * math.sin(i * 1.8 + level * math.pi);
      final offset = Offset(math.cos(angle), math.sin(angle));
      paint.color = color.withValues(alpha: .5 + .5 * level * variation);
      canvas.drawLine(center + offset * (radius - 5),
        center + offset * (radius - 2.5 + level * variation * 1.5), paint);
    }
  }

  @override
  bool shouldRepaint(_VoiceRingPainter oldDelegate) =>
      oldDelegate.level != level || oldDelegate.color != color;
}
