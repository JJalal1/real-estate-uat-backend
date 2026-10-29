import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'smart_search_assistant.dart';
import '../domain/smart_search_filters.dart';

/// A lightweight entry to the existing search session, shared with My Account.
class HomeAiSearchEntry extends ConsumerWidget {
  const HomeAiSearchEntry({this.location = 'صنعاء', this.type, this.purpose, this.wide = false, super.key});

  final String location;
  final String? type;
  final String? purpose;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Theme.of(context).colorScheme.primary;
    void open() => context.push('/smart-search', extra: type == null && purpose == null ? null
      : SmartSearchFilters.fromMap({if (type != null) 'type': type, if (purpose != null) 'purpose': purpose}));
    if (wide) {
      return Material(color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(16),
      child: InkWell(key: const ValueKey('home-smart-search'), onTap: open, borderRadius: BorderRadius.circular(16),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(children: [
          Icon(Icons.chevron_right, color: color, size: 22), const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('بحث ذكي', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)),
            Text('صف ما تحتاجه بالنص أو الصوت', style: Theme.of(context).textTheme.bodySmall),
          ])), const SizedBox(width: 8), const SmartSearchRobotIcon(size: 30),
        ]))));
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
