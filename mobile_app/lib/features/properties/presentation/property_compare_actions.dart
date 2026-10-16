import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'property_compare_screen.dart';

class PropertyCompareSelection extends StateNotifier<Set<int>> {
  PropertyCompareSelection() : super(const {});
  bool toggle(int id) {
    if (id <= 0) return false;
    final next = {...state};
    if (!next.remove(id)) {
      if (next.length >= 4) return false;
      next.add(id);
    }
    state = Set.unmodifiable(next);
    return true;
  }
  void clear() => state = const {};
}

final propertyCompareSelectionProvider = StateNotifierProvider<PropertyCompareSelection, Set<int>>((ref) => PropertyCompareSelection());

class PropertyCompareAction extends ConsumerWidget {
  const PropertyCompareAction({required this.propertyId, this.enabled = true, super.key});
  final int propertyId;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(propertyCompareSelectionProvider).contains(propertyId);
    return TextButton.icon(key: ValueKey('compare-property-$propertyId'),
      onPressed: !enabled ? null : () {
        if (!ref.read(propertyCompareSelectionProvider.notifier).toggle(propertyId)) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر حتى أربعة عقارات للمقارنة. أزل أحد الاختيارات لإضافة آخر.')));
        }
      },
      icon: Icon(selected ? Icons.check_circle_outline : Icons.compare_arrows, size: 18),
      label: Text(selected ? 'محدد للمقارنة' : 'قارن'),
    );
  }
}

class PropertyCompareTray extends ConsumerWidget {
  const PropertyCompareTray({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(propertyCompareSelectionProvider);
    if (ids.isEmpty) return const SizedBox.shrink();
    return Material(elevation: 3, color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(key: const ValueKey('open-property-comparison'),
          onPressed: ids.length < 2 ? null : () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => PropertyCompareScreen(propertyIds: ids.toList(growable: false)))),
          icon: const Icon(Icons.compare_arrows, size: 20), label: Text('المقارنة (${ids.length}/4)')),
        IconButton(key: const ValueKey('clear-property-comparison'), onPressed: () => ref.read(propertyCompareSelectionProvider.notifier).clear(),
          tooltip: 'مسح اختيارات المقارنة', icon: const Icon(Icons.close, size: 18)),
      ])),
    );
  }
}
