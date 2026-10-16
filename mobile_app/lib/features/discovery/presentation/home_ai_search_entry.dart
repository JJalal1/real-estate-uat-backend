import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'smart_search_assistant.dart';
import '../data/smart_search_session.dart';

/// A lightweight entry to the existing search session, shared with My Account.
class HomeAiSearchEntry extends ConsumerWidget {
  const HomeAiSearchEntry({this.location = 'صنعاء', this.type, super.key});

  final String location;
  final String? type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Theme.of(context).colorScheme.primary;
    return TextButton.icon(
      key: const ValueKey('home-smart-search'),
      onPressed: () {
        ref.read(smartSearchSessionProvider.notifier)
            .startFromHome(location: location, type: type);
        context.push('/smart-search');
      },
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
