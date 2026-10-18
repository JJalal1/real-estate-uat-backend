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
  const PropertyCompareAction({required this.propertyId, this.enabled = true, this.overlay = false, super.key});
  final int propertyId;
  final bool enabled;
  final bool overlay;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(propertyCompareSelectionProvider).contains(propertyId);
    final label = selected ? 'محدد للمقارنة' : 'قارن';
    void toggle() {
      if (!ref.read(propertyCompareSelectionProvider.notifier).toggle(propertyId)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر حتى أربعة عقارات للمقارنة. أزل أحد الاختيارات لإضافة آخر.')));
      }
    }
    if (overlay) return IconButton(key: ValueKey('compare-property-$propertyId'), tooltip: label,
      onPressed: enabled ? toggle : null, isSelected: selected,
      style: IconButton.styleFrom(backgroundColor: selected ? Theme.of(context).colorScheme.primary : Colors.white.withValues(alpha: .96),
        foregroundColor: selected ? Colors.white : Theme.of(context).colorScheme.secondary, minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(10), shape: const CircleBorder()),
      icon: Icon(selected ? Icons.check_rounded : Icons.compare_arrows_rounded, size: 20));
    return TextButton.icon(key: ValueKey('compare-property-$propertyId'), onPressed: enabled ? toggle : null,
      icon: Icon(selected ? Icons.check_circle_outline : Icons.compare_arrows, size: 18), label: Text(label));
  }
}

class PropertyCompareTray extends ConsumerWidget {
  const PropertyCompareTray({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(propertyCompareSelectionProvider);
    if (ids.isEmpty) return const SizedBox.shrink();
    return Material(elevation: 3, color: Theme.of(context).colorScheme.secondary, borderRadius: BorderRadius.circular(20),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(key: const ValueKey('open-property-comparison'),
          style: TextButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: Colors.white70),
          onPressed: ids.length < 2 ? null : () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => PropertyCompareScreen(propertyIds: ids.toList(growable: false)))),
          icon: const Icon(Icons.compare_arrows, size: 20), label: Text('المقارنة (${ids.length}/4)')),
        IconButton(key: const ValueKey('clear-property-comparison'), onPressed: () => ref.read(propertyCompareSelectionProvider.notifier).clear(),
          tooltip: 'مسح اختيارات المقارنة', icon: const Icon(Icons.close, size: 18, color: Colors.white70)),
      ])),
    );
  }
}
