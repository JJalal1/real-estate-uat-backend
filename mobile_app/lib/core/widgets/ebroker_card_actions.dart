import 'package:flutter/material.dart';
import 'app_components.dart';
import 'ebroker_widgets.dart';

class EbrokerCardAction {
  const EbrokerCardAction(this.label, this.onPressed, {this.icon = Icons.chevron_left});
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
}

/// One visible next action; all other authorized actions remain reachable.
class EbrokerCardActions extends StatelessWidget {
  const EbrokerCardActions({required this.actions, super.key});
  final List<EbrokerCardAction> actions;
  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: AppButton(label: actions.first.label, icon: actions.first.icon,
        expand: true, style: AppButtonStyle.tonal, onPressed: actions.first.onPressed)),
      if (actions.length > 1) ...[
        const SizedBox(width: 6),
        PopupMenuButton<int>(tooltip: 'خيارات البطاقة',
          icon: const EbrokerIcon(Icons.more_vert, size: 22),
          onSelected: (index) => actions[index].onPressed?.call(),
          itemBuilder: (_) => [for (var i = 1; i < actions.length; i++) PopupMenuItem<int>(
            value: i, enabled: actions[i].onPressed != null,
            child: Row(children: [EbrokerIcon(actions[i].icon, size: 18), const SizedBox(width: 10), Expanded(child: Text(actions[i].label))]))]),
      ],
    ]);
  }
}
