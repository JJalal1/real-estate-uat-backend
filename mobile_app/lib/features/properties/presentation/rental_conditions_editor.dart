import 'dart:convert';

import 'package:flutter/material.dart';

/// Only the selected requirements enter the listing payload.
class RentalConditionsEditor extends StatefulWidget {
  const RentalConditionsEditor({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<Map<String, dynamic>> value;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;

  static const labels = <String, String>{
    'advance': 'إيجار مقدم',
    'guarantor': 'ضمانة تجارية',
    'deposit': 'تأمين',
    'duration': 'مدة عقد',
    'special': 'شرط خاص',
  };

  @override
  State<RentalConditionsEditor> createState() => _RentalConditionsEditorState();
}

class _RentalConditionsEditorState extends State<RentalConditionsEditor> {
  late List<Map<String, dynamic>> _rows;
  int _layoutRevision = 0;

  List<Map<String, dynamic>> _copy(List<Map<String, dynamic>> rows) =>
      rows.map((row) => Map<String, dynamic>.from(row)).toList();

  @override
  void initState() {
    super.initState();
    _rows = _copy(widget.value);
  }

  @override
  void didUpdateWidget(covariant RentalConditionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(widget.value) != jsonEncode(_rows)) {
      _rows = _copy(widget.value);
      _layoutRevision++;
    }
  }

  void _emit(List<Map<String, dynamic>> next, {bool structural = false}) {
    setState(() {
      _rows = _copy(next);
      if (structural) _layoutRevision++;
    });
    widget.onChanged(_copy(_rows));
  }

  void _toggle(String kind, bool selected) {
    _emit(selected
        ? [..._rows, {'kind': kind}]
        : _rows.where((row) => row['kind'] != kind).toList(),
        structural: true);
  }

  void _change(int index, String key, dynamic value) {
    final next = _copy(_rows);
    if (value == null) {
      next[index].remove(key);
    } else {
      next[index][key] = value;
    }
    _emit(next);
  }

  String _monthLabel(int months) => switch (months) {
    1 => 'شهر واحد',
    2 => 'شهران',
    <= 10 => '$months أشهر',
    _ => '$months شهرًا',
  };

  @override
  Widget build(BuildContext context) {
    final labels = RentalConditionsEditor.labels;
    final selected = _rows.map((row) => row['kind']).toSet();
    return Column(
      key: ValueKey(_layoutRevision),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text('شروط الإيجار', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('اختر ما تحتاجه فقط؛ جميع الشروط اختيارية.'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final item in labels.entries)
            FilterChip(
              key: ValueKey('rent-condition-${item.key}'),
              label: Text(item.value),
              selected: selected.contains(item.key),
              onSelected: widget.enabled ? (on) => _toggle(item.key, on) : null,
            ),
        ]),
        for (var i = 0; i < _rows.length; i++)
          if (const ['advance', 'duration', 'special'].contains(_rows[i]['kind']))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _detail(i)),
                IconButton(
                  tooltip: 'حذف الشرط',
                  onPressed: widget.enabled ? () => _emit([
                    for (var n = 0; n < _rows.length; n++)
                      if (n != i) Map<String, dynamic>.from(_rows[n]),
                  ], structural: true) : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ]),
            ),
        if (selected.contains('special') &&
            _rows.where((row) => row['kind'] == 'special').length < 4)
          TextButton.icon(
            onPressed: widget.enabled
                ? () => _emit([..._rows, {'kind': 'special'}], structural: true)
                : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة شرط خاص آخر'),
          ),
      ],
    );
  }

  Widget _detail(int index) {
    final row = _rows[index];
    final kind = row['kind'] as String;
    if (kind == 'special') {
      return TextFormField(
        key: ValueKey('rent-special-$index'),
        initialValue: row['text']?.toString() ?? '',
        enabled: widget.enabled,
        maxLength: 300,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'اكتب شرطك الخاص'),
        onChanged: (text) => _change(index, 'text', text),
      );
    }
    final value = row['months'] as int?;
    final months = <int>{
      if (kind == 'advance') ...[2, 3, 4, 5]
      else ...List.generate(24, (i) => i + 1),
      // Preserve a previously saved valid choice without silently changing it.
      if (value != null && value >= 1 && value <= 24) value,
    }.toList()..sort();
    return DropdownButtonFormField<int>(
      key: ValueKey('rent-$kind-$index'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: kind == 'advance' ? 'عدد أشهر المقدم' : 'مدة العقد بالأشهر',
        hintText: 'اختر عدد الأشهر',
      ),
      items: months.map((month) =>
          DropdownMenuItem(value: month, child: Text(_monthLabel(month)))).toList(),
      onChanged: widget.enabled ? (next) => _change(index, 'months', next) : null,
    );
  }
}
