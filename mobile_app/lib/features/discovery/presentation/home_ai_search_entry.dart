import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import 'smart_search_assistant.dart';

/// Home and My Account open a new assistant journey without copying Home edits.
class HomeAiSearchEntry extends StatelessWidget {
  const HomeAiSearchEntry({this.location = 'صنعاء', this.type, this.purpose, this.wide = false, this.onPressed, super.key});

  final String location;
  final String? type;
  final String? purpose;
  final bool wide;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    void open() {
      if (onPressed case final action?) {
        action();
      } else {
        context.push('/smart-search');
      }
    }
    if (wide) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final radius = BorderRadius.circular(AppRadii.control);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: color.withValues(alpha: .07),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('home-smart-search'),
            onTap: open,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: SmartSearchRobotIcon(size: 28, color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('بحث ذكي', style: theme.textTheme.titleSmall?.copyWith(
                  color: color, fontWeight: FontWeight.w700,
                ))),
                const SizedBox(width: 8),
                Flexible(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(9)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text('جرّب الآن', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimary)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    return TextButton.icon(
      key: const ValueKey('home-smart-search'),
      onPressed: open,
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: .07),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const SmartSearchRobotIcon(size: 24),
      label: const Text('بحث ذكي'),
    );
  }
}
