import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_components.dart';
import '../data/recent_properties_store.dart';
import 'property_summary_card.dart';

class RecentPropertiesScreen extends ConsumerWidget {
  const RecentPropertiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentPropertiesProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('شوهد مؤخرًا'),
          actions: [
            IconButton(
              tooltip: 'مسح السجل',
              onPressed: recent.asData?.value.isNotEmpty == true
                  ? () async {
                      await ref.read(recentPropertiesStoreProvider).clear();
                      ref.invalidate(recentPropertiesProvider);
                    }
                  : null,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: recent.when(
          loading: () => const AppLoadingState(),
          error: (_, __) => AppErrorState(
            message: 'تعذر تحميل السجل المحلي.',
            onRetry: () => ref.invalidate(recentPropertiesProvider),
          ),
          data: (items) => items.isEmpty
              ? const AppEmptyState(
                  title: 'ما شاهدت عقارات بعد',
                  message: 'العقارات التي تفتحها ستظهر هنا على هذا الجهاز فقط.',
                  icon: Icons.history_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) =>
                      PropertySummaryCard(property: items[index]),
                ),
        ),
      ),
    );
  }
}
