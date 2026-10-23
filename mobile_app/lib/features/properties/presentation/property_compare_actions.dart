import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'property_compare_screen.dart';

class PropertyCompareSelection extends StateNotifier<Set<int>> {
  PropertyCompareSelection() : super(const {});
  bool toggle(int id) {
    if (id <= 0) return false;
    final next = {...state};
    if (!next.remove(id)) {
      if (next.length >= 2) return false;
      next.add(id);
    }
    state = Set.unmodifiable(next);
    return true;
  }
  void clear() => state = const {};
}

final propertyCompareSelectionProvider = StateNotifierProvider<PropertyCompareSelection, Set<int>>((ref) => PropertyCompareSelection());

class PropertyCompareAction extends ConsumerWidget {
  const PropertyCompareAction({required this.propertyId, this.enabled = true, this.overlay = false, super.key});
  final int propertyId;
  final bool enabled;
  final bool overlay;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(propertyCompareSelectionProvider).contains(propertyId);
    final label = selected ? 'مضاف للمقارنة' : 'أضف للمقارنة';
    void toggle() {
      if (!ref.read(propertyCompareSelectionProvider.notifier).toggle(propertyId)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المقارنة بين عقارين فقط. أزل أحدهما أو استبدله لإضافة آخر.')));
      } else if (ref.read(propertyCompareSelectionProvider).length == 1 && !selected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر عقارًا آخر لإكمال المقارنة.')));
      }
    }
    final scheme = Theme.of(context).colorScheme;
    return Align(alignment: AlignmentDirectional.centerStart, child: Semantics(selected: selected,
      child: TextButton(key: ValueKey('compare-property-$propertyId'), onPressed: enabled ? toggle : null,
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 48),
          foregroundColor: scheme.onSurfaceVariant),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: selected ? scheme.primaryContainer : scheme.surface,
            border: Border.all(color: selected ? scheme.primary : scheme.outline), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(selected ? Icons.check : Icons.add, size: 13),
            const SizedBox(width: 3), Flexible(child: Text(label, style: const TextStyle(fontSize: 11)))])))));
  }
}

class PropertyCompareTray extends ConsumerWidget {
  const PropertyCompareTray({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(propertyCompareSelectionProvider);
    if (ids.isEmpty) return const SizedBox.shrink();
    return Material(color: Theme.of(context).colorScheme.secondary, borderRadius: BorderRadius.circular(20),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(key: const ValueKey('open-property-comparison'),
          style: TextButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: Colors.white70),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => PropertyCompareScreen(propertyIds: ids.toList(growable: false)))),
          icon: const Icon(Icons.compare_arrows, size: 20), label: Text(ids.length == 1 ? 'اختر العقار الثاني (١/٢)' : 'قارن العقارين (٢/٢)')),
        IconButton(key: const ValueKey('clear-property-comparison'), onPressed: () => ref.read(propertyCompareSelectionProvider.notifier).clear(),
          tooltip: 'مسح اختيارات المقارنة', icon: const Icon(Icons.close, size: 18, color: Colors.white70)),
      ])),
    );
  }
}

