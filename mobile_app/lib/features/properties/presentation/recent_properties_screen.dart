import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_components.dart';
import '../data/recent_properties_store.dart';
import 'property_summary_card.dart';

class RecentPropertiesScreen extends ConsumerStatefulWidget {
  const RecentPropertiesScreen({super.key});

  @override
  ConsumerState<RecentPropertiesScreen> createState() => _RecentPropertiesState();
}

class _RecentPropertiesState extends ConsumerState<RecentPropertiesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(recentPropertiesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
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
                      try {
                        await ref.read(recentPropertiesStoreProvider).clear();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تعذر مسح السجل. حاول مرة أخرى.')));
                        }
                      }
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
              : RefreshIndicator(
                  onRefresh: () async {
                    try {
                      ref.invalidate(recentPropertiesProvider);
                      await ref.read(recentPropertiesProvider.future);
                    } catch (_) {
                      // The provider exposes the error and retry action.
                    }
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, index) =>
                        PropertySummaryCard(property: items[index], compact: true),
                  ),
                ),
        ),
      ),
    );
  }
}
