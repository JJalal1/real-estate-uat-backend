import 'package:flutter/material.dart';

import '../theme/ebroker_design.dart';
import 'app_components.dart';
import 'ebroker_widgets.dart';

// add_property/widgets/step_bottom_bar.dart: the wizard uses its own original
// 48px ElevatedButton / OutlinedButton, radius 6, 15px medium label.
class EbrokerStepButton extends StatelessWidget {
  const EbrokerStepButton({required this.label, required this.onPressed,
    this.icon, this.style = AppButtonStyle.filled, this.expand = false,
    this.loading = false, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonStyle style;
  final bool expand;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final outlined = style != AppButtonStyle.filled;
    final child = loading ? SizedBox(width: 20, height: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: outlined ? primary : Colors.white))
      : Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[EbrokerIcon(icon, size: 18), const SizedBox(width: 4)],
          Flexible(child: EbrokerText(label, size: 15, weight: FontWeight.w500,
            color: outlined ? EbrokerDesign.text : Colors.white, maxLines: 2, align: TextAlign.center)),
        ]);
    final callback = loading ? null : onPressed;
    final height = 48.rh(context) * (MediaQuery.textScalerOf(context).scale(15) / 15).clamp(1.0, double.infinity);
    if (style == AppButtonStyle.text) { return SizedBox(height: height,
      width: expand ? double.infinity : null, child: TextButton(onPressed: callback,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)), child: child)); }
    return SizedBox(height: height, width: expand ? double.infinity : null,
      child: outlined ? OutlinedButton(onPressed: callback,
        style: OutlinedButton.styleFrom(backgroundColor: Colors.transparent,
          foregroundColor: EbrokerDesign.text,
          side: const BorderSide(color: EbrokerDesign.text, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: EdgeInsets.zero),
        child: child)
        : ElevatedButton(onPressed: callback,
          style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white,
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: EdgeInsets.zero), child: child));
  }
}
