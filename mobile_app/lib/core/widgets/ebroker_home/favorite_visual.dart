// Transplanted from eBroker 1.8.0; see docs/WAVE3_HOME_SOURCE_MAP.json.
import 'package:flutter/material.dart';
import '../ebroker_widgets.dart';

class EbrokerHomeFavoriteVisual extends StatefulWidget {
  const EbrokerHomeFavoriteVisual({required this.selected, required this.busy, this.onPressed, super.key});
  final bool selected, busy;
  final Future<void> Function()? onPressed;
  @override
  State<EbrokerHomeFavoriteVisual> createState() => _EbrokerHomeFavoriteVisualState();
}
class _EbrokerHomeFavoriteVisualState extends State<EbrokerHomeFavoriteVisual> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _activating = false;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(begin: 1, end: 1.4),
            weight: 50,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.4, end: 1),
            weight: 50,
          ),
        ]).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
        );
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  Future<void> _activate() async {
    if (_activating || widget.onPressed == null) return;
    _activating = true;
    if (!MediaQuery.disableAnimationsOf(context)) _controller.forward(from: 0);
    try { await widget.onPressed!(); } finally { _activating = false; }
  }
  @override
  Widget build(BuildContext context) => Semantics(button: true, selected: widget.selected,
    label: widget.selected ? 'إزالة من المفضلة' : 'حفظ في المفضلة',
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onPressed == null ? null : _activate,
      child: SizedBox.square(dimension: 48, child: Center(child: Container(
        width: 34, height: 34, alignment: Alignment.center,
        decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
        child: widget.busy ? const SizedBox.square(dimension: 15,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : ScaleTransition(scale: _scaleAnimation, child: EbrokerImage(
            widget.selected ? 'heart_filled' : 'heart', size: 24, color: Colors.white)),
      )))));
}
