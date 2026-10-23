import '../../account/data/auth_controller.dart';
import '../../app_shell/presentation/listing_creation_menu.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../properties/presentation/property_compare_actions.dart';

/// A presentation preference only; it never contains search or account data.
class AssistantHintStore {
  bool _taken = false;
  Future<bool> take() async {
    if (_taken) return false;
    _taken = true;
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/smart_search_hint_seen_v1');
      if (await file.exists()) return false;
      await file.writeAsString('seen', flush: true);
    } catch (_) { /* A local preference failure never blocks browsing. */ }
    return true;
  }
}

final brokerAssistantMenuProvider = StateProvider<bool>((ref) {
  ref.watch(authControllerProvider.select((state) => (state.asData?.value?.id, state.asData?.value?.hasVerifiedProfessionalProfile)));
  return false;
});

final assistantHintStoreProvider = Provider<AssistantHintStore>((ref) => AssistantHintStore());

/// Install only on public browsing bodies, above their bottom navigation.
/// Physical left placement is intentional for the Arabic product reference.
class SmartSearchAssistantLayer extends ConsumerStatefulWidget {
  const SmartSearchAssistantLayer({required this.child, this.onPressed, this.bottom = 20, this.enabled = true, this.showComparisonTray = true, super.key});
  final Widget child;
  final VoidCallback? onPressed;
  final double bottom;
  final bool enabled, showComparisonTray;

  @override
  ConsumerState<SmartSearchAssistantLayer> createState() => _AssistantLayerState();
}

class _AssistantLayerState extends ConsumerState<SmartSearchAssistantLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  Timer? _pulse, _hintTimer;
  bool _hint = false, _openingAction = false;

  Future<void> _brokerAction(bool search) async {
    if (_openingAction) return;
    ref.read(brokerAssistantMenuProvider.notifier).state = false;
    _openingAction = true;
    try { await context.push(search ? '/smart-search' : '/add-property?assistant=1'); } finally { _openingAction = false; }
  }

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _pulse = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted && widget.enabled && TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context) && ModalRoute.of(context)?.isCurrent != false) {
        _motion.forward(from: 0);
      }
    });
    Future<void>.microtask(() async {
      if (!mounted || !widget.enabled || !await ref.read(assistantHintStoreProvider).take() || !mounted) return;
      setState(() => _hint = true);
      _hintTimer = Timer(const Duration(seconds: 6), _dismissHint);
    });
  }

  void _dismissHint() { if (mounted && _hint) setState(() => _hint = false); }

  @override
  void dispose() { _pulse?.cancel(); _hintTimer?.cancel(); _motion.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final broker = ref.watch(authControllerProvider).asData?.value?.hasVerifiedProfessionalProfile == true;
    final menuOpen = broker && ref.watch(brokerAssistantMenuProvider);
    return Stack(fit: StackFit.expand, children: [
      ExcludeSemantics(excluding: menuOpen, child: widget.child),
      if (broker) ListingCreationMenu(isOpen: menuOpen, onClose: () => ref.read(brokerAssistantMenuProvider.notifier).state = false,
        onSelected: _brokerAction, manualLabel: 'إضافة عقار بالذكاء', assistedLabel: 'بحث عن عقار بالذكاء',
        leftAligned: true, baseBottom: widget.bottom + 64, scrimOpacity: .35),
      if (widget.enabled && widget.showComparisonTray && MediaQuery.viewInsetsOf(context).bottom == 0) Positioned(right: 12, bottom: widget.bottom,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 100), child: const PropertyCompareTray())),
      if (widget.enabled && MediaQuery.viewInsetsOf(context).bottom == 0)
        Positioned(left: 16, bottom: widget.bottom, child: Column(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (_hint && !menuOpen) Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(
            elevation: 3, color: scheme.surface, borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 48), child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text('جرّب البحث الذكي', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600))),
                IconButton(key: const ValueKey('assistant-hint-close'), onPressed: _dismissHint, tooltip: 'إغلاق التلميح', icon: const Icon(Icons.close, size: 18)),
              ]),
            )),
          )),
          AnimatedBuilder(animation: _motion, builder: (context, child) => Transform.rotate(
            angle: math.sin(_motion.value * math.pi * 2) * .055,
            child: Transform.scale(scale: 1 + math.sin(_motion.value * math.pi) * .035, child: child),
          ), child: Material(
            color: scheme.surface, elevation: 5, shadowColor: scheme.primary.withValues(alpha: .24), shape: const CircleBorder(),
            child: InkWell(key: const ValueKey('floating-smart-search'), customBorder: const CircleBorder(),
              onTap: () { _dismissHint(); if (broker) { ref.read(brokerAssistantMenuProvider.notifier).state = !menuOpen; return; } if (widget.onPressed != null) { widget.onPressed!(); } else { context.push('/smart-search'); } },
              child: Tooltip(message: menuOpen ? 'إغلاق المساعد' : broker ? 'مساعد العقار' : 'بحث ذكي', child: Semantics(button: true, label: menuOpen ? 'إغلاق المساعد' : broker ? 'فتح مساعد العقار' : 'فتح مساعد البحث الذكي',
                child: Padding(padding: const EdgeInsets.all(10), child: menuOpen ? Icon(Icons.close, size: 38, color: scheme.primary) : const SmartSearchRobotIcon(size: 38)))),
            ),
          )),
        ])),
    ]);
  }
}

/// A small vector mascot in the app palette, shared by the chip and launcher.
class SmartSearchRobotIcon extends StatelessWidget {
  const SmartSearchRobotIcon({this.size = 24, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: CustomPaint(
    size: Size.square(size), painter: _RobotPainter(Theme.of(context).colorScheme.primary),
  ));
}

class _RobotPainter extends CustomPainter {
  const _RobotPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save(); canvas.scale(size.width / 40, size.height / 40);
    final paint = Paint()..color = color;
    canvas.drawCircle(const Offset(20, 3), 2, paint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(19, 4, 2, 5), const Radius.circular(1)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(1, 16, 4, 12), const Radius.circular(2)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(35, 16, 4, 12), const Radius.circular(2)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5, 8, 30, 26), const Radius.circular(10)), paint..color = color.withValues(alpha: .13));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(8, 11, 24, 20), const Radius.circular(9)), paint..color = color);
    paint.color = Colors.white;
    canvas.drawOval(const Rect.fromLTWH(13, 16, 3.5, 5), paint);
    canvas.drawOval(const Rect.fromLTWH(23.5, 16, 3.5, 5), paint);
    canvas.drawArc(const Rect.fromLTWH(16, 19, 8, 7), .25, math.pi - .5, false, paint..style = PaintingStyle.stroke..strokeWidth = 1.3..strokeCap = StrokeCap.round);
    paint..style = PaintingStyle.fill..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, 35, 12, 3), const Radius.circular(1.5)), paint);
    canvas.restore();
  }
  @override
  bool shouldRepaint(_RobotPainter oldDelegate) => oldDelegate.color != color;
}
