import 'dart:convert';
import 'package:flutter/material.dart';

/// Optional advertiser-selected requirements. No amount or term is invented.
class RentalConditionsEditor extends StatefulWidget {
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
  @override
  State<RentalConditionsEditor> createState() => _RentalConditionsEditorState();
}

class _RentalConditionsEditorState extends State<RentalConditionsEditor> {
  static const labels = RentalConditionsEditor.labels;
  late List<Map<String, dynamic>> _rows;
  int _layoutRevision = 0;
  List<Map<String, dynamic>> _copy(List<Map<String, dynamic>> rows) => rows.map((row) => Map<String, dynamic>.from(row)).toList();
  @override
  void initState() { super.initState(); _rows = _copy(widget.value); }
  @override
  void didUpdateWidget(covariant RentalConditionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(widget.value) != jsonEncode(_rows)) { _rows = _copy(widget.value); _layoutRevision++; }
  }
  void _emit(List<Map<String, dynamic>> next, {bool structural = false}) {
    // Keep edits synchronous even when another action arrives before a rebuild.
    setState(() { _rows = _copy(next); if (structural) _layoutRevision++; });
    widget.onChanged(_copy(_rows));
  }
  Future<void> _choose() async {
    final selected = _rows.map((e) => e['kind'] as String).toSet();
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
    if (result == null || !mounted) return;
    _emit([for (final kind in labels.keys) if (result.contains(kind))
      ...(_rows.any((e) => e['kind'] == kind)
        ? _rows.where((e) => e['kind'] == kind).map((e) => Map<String, dynamic>.from(e))
        : [<String, dynamic>{'kind': kind}])], structural: true);
  }
  int? _months(String text) {
    const digits = '٠١٢٣٤٥٦٧٨٩';
    var normalized = text.trim();
    for (var i = 0; i < 10; i++) { normalized = normalized.replaceAll(digits[i], '$i'); }
    return int.tryParse(normalized);
  }
  void _change(int index, String key, dynamic next) {
    final copy = _copy(_rows);
    if (next == null) { copy[index].remove(key); } else { copy[index][key] = next; }
    _emit(copy);
  }
  @override
  Widget build(BuildContext context) => Column(key: ValueKey(_layoutRevision), crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Divider(height: 32),
    Row(children: [Expanded(child: Text('شروط الإيجار', style: Theme.of(context).textTheme.titleMedium)),
      TextButton(onPressed: widget.enabled ? _choose : null,
        child: Text(_rows.isEmpty ? 'إضافة شروط اختيارية' : 'تعديل الشروط'))]),
    if (_rows.isEmpty) const Text('أضف ما تحتاجه فقط؛ يمكنك المتابعة دون شروط.'),
    for (var i = 0; i < _rows.length; i++) Padding(padding: const EdgeInsets.only(top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: switch (_rows[i]['kind']) {
          'advance' || 'duration' => TextFormField(key: ValueKey('rent-${_rows[i]['kind']}-$i'),
            initialValue: _rows[i]['months']?.toString() ?? '', enabled: widget.enabled,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _rows[i]['kind'] == 'advance' ? 'عدد أشهر المقدم' : 'مدة العقد بالأشهر'),
            onChanged: (text) => _change(i, 'months', _months(text))),
          'special' => TextFormField(key: ValueKey('rent-special-$i'),
            initialValue: _rows[i]['text']?.toString() ?? '', enabled: widget.enabled, maxLength: 300, maxLines: 2,
            decoration: const InputDecoration(labelText: 'اكتب شرطك الخاص'),
            onChanged: (text) => _change(i, 'text', text)),
          _ => Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(labels[_rows[i]['kind']] ?? '')),
        }),
        IconButton(tooltip: 'حذف الشرط', onPressed: !widget.enabled ? null : () => _emit([
          for (var n = 0; n < _rows.length; n++) if (n != i) Map<String, dynamic>.from(_rows[n])], structural: true),
          icon: const Icon(Icons.close, size: 18)),
      ])),
    if (_rows.isNotEmpty && widget.onPolish != null) TextButton.icon(
      onPressed: widget.enabled ? widget.onPolish : null, icon: const Icon(Icons.auto_awesome, size: 18),
      label: const Text('ترتيب وصياغة الشروط بالذكاء الاصطناعي')),
    if (_rows.any((e) => e['kind'] == 'special') && _rows.where((e) => e['kind'] == 'special').length < 4)
      TextButton.icon(onPressed: !widget.enabled ? null : () => _emit([..._rows, {'kind': 'special'}], structural: true),
        icon: const Icon(Icons.add, size: 18), label: const Text('إضافة شرط خاص آخر')),
  ]);
}
