import 'package:flutter/material.dart';

/// Optional advertiser-selected requirements. Selecting a kind never invents
/// an amount, a duration or a special condition.
class RentalConditionsEditor extends StatelessWidget {
  const RentalConditionsEditor({required this.value, required this.onChanged,
    this.enabled = true, this.onPolish, super.key});
  final List<Map<String, dynamic>> value;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final VoidCallback? onPolish;

  static const labels = <String, String>{
    'advance': 'مقدم إيجار', 'guarantor': 'ضمانة تجارية',
    'deposit': 'تأمين', 'duration': 'مدة عقد', 'special': 'شرط خاص',
  };

  Future<void> _choose(BuildContext context) async {
    final selected = value.map((e) => e['kind'] as String).toSet();
    final result = await showModalBottomSheet<Set<String>>(context: context,
      isScrollControlled: true, builder: (sheet) => StatefulBuilder(
        builder: (_, update) => SafeArea(child: Padding(
          padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('اختر شروط الإيجار', style: Theme.of(context).textTheme.titleMedium),
            for (final item in labels.entries) CheckboxListTile(contentPadding: EdgeInsets.zero,
              title: Text(item.value), value: selected.contains(item.key),
              onChanged: (on) => update(() { if (on == true) { selected.add(item.key); } else { selected.remove(item.key); } })),
            FilledButton(onPressed: () => Navigator.pop(sheet, selected), child: const Text('استخدام الشروط المحددة')),
          ])))));
    if (result == null) return;
    onChanged([for (final kind in labels.keys) if (result.contains(kind))
      ...(value.any((e) => e['kind'] == kind)
        ? value.where((e) => e['kind'] == kind).map((e) => Map<String, dynamic>.from(e))
        : [<String, dynamic>{'kind': kind}])]);
  }

  void _change(int index, String key, dynamic next) {
    final copy = value.map((e) => Map<String, dynamic>.from(e)).toList();
    if (next == null) { copy[index].remove(key); } else { copy[index][key] = next; }
    onChanged(copy);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Divider(height: 32),
    Row(children: [Expanded(child: Text('شروط الإيجار', style: Theme.of(context).textTheme.titleMedium)),
      TextButton(onPressed: enabled ? () => _choose(context) : null,
        child: Text(value.isEmpty ? 'إضافة شروط اختيارية' : 'تعديل الشروط'))]),
    if (value.isEmpty) const Text('أضف ما تحتاجه فقط؛ يمكنك المتابعة دون شروط.'),
    for (var i = 0; i < value.length; i++) Padding(padding: const EdgeInsets.only(top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: switch (value[i]['kind']) {
          'advance' || 'duration' => TextFormField(key: ValueKey('rent-${value[i]['kind']}-$i'),
            initialValue: value[i]['months']?.toString() ?? '', enabled: enabled,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: value[i]['kind'] == 'advance' ? 'عدد أشهر المقدم' : 'مدة العقد بالأشهر'),
            onChanged: (text) => _change(i, 'months', int.tryParse(text))),
          'special' => TextFormField(key: ValueKey('rent-special-$i'),
            initialValue: value[i]['text']?.toString() ?? '', enabled: enabled, maxLength: 300, maxLines: 2,
            decoration: const InputDecoration(labelText: 'اكتب شرطك الخاص'),
            onChanged: (text) => _change(i, 'text', text)),
          _ => Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(labels[value[i]['kind']] ?? '')),
        }),
        IconButton(tooltip: 'حذف الشرط', onPressed: !enabled ? null : () => onChanged([
          for (var n = 0; n < value.length; n++) if (n != i) Map<String, dynamic>.from(value[n])]),
          icon: const Icon(Icons.close, size: 18)),
      ])),
    if (value.isNotEmpty && onPolish != null) TextButton.icon(
      onPressed: enabled ? onPolish : null, icon: const Icon(Icons.auto_awesome, size: 18),
      label: const Text('ترتيب وصياغة الشروط بالذكاء الاصطناعي')),
    if (value.any((e) => e['kind'] == 'special') && value.where((e) => e['kind'] == 'special').length < 4)
      TextButton.icon(onPressed: !enabled ? null : () => onChanged([...value, {'kind': 'special'}]),
        icon: const Icon(Icons.add, size: 18), label: const Text('إضافة شرط خاص آخر')),
  ]);
}
