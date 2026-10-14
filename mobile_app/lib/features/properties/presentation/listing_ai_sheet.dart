import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/voice_input.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../discovery/data/ai_repository.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../domain/property_field_options.dart';

class ListingAiSheet extends ConsumerStatefulWidget {
  const ListingAiSheet({required this.facts, this.propertyId, this.description = false, super.key});
  final Map<String, dynamic> facts;
  final int? propertyId;
  final bool description;
  @override
  ConsumerState<ListingAiSheet> createState() => _ListingAiSheetState();
}

class _ListingAiSheetState extends ConsumerState<ListingAiSheet> {
  final _message = TextEditingController(), _description = TextEditingController();
  final _selected = <String>{};
  Map<String, dynamic>? _fields;
  bool _busy = false, _voiceBusy = false, _hasDescription = false;
  String? _error;
  static const labels = {'title': 'عنوان الإعلان', 'type': 'نوع العقار', 'purpose': 'الغرض', 'price': 'سعر البيع بالريال اليمني',
    'monthly_rent': 'الإيجار الشهري بالريال اليمني', 'area_value': 'المساحة', 'area_unit': 'وحدة المساحة',
    'bedrooms': 'غرف النوم', 'bathrooms': 'الحمامات', 'governorate': 'المحافظة', 'district': 'الحي', 'street': 'الشارع',
    'floor_number': 'الدور', 'unit_number': 'رقم الوحدة', 'has_parking': 'موقف السيارة', 'has_elevator': 'المصعد',
    'building_facade': 'واجهة البناء', 'unit_occupies_entire_floor': 'الوحدة تشغل الدور كاملًا', 'tenure_type': 'نوع الملكية'};
  @override
  void dispose() { _message.dispose(); _description.dispose(); super.dispose(); }

  Future<void> _request() async {
    if (_busy || _voiceBusy || !widget.description && _message.text.trim().isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(aiRepositoryProvider);
      final result = widget.description
        ? await api.description(widget.facts, propertyId: widget.propertyId)
        : await api.listingFields(_message.text, widget.facts, propertyId: widget.propertyId);
      if (!mounted) return;
      if (widget.description) {
        final text = result['description'];
        if (text is! String || text.trim().isEmpty) throw StateError('Empty description.');
        setState(() { _description.text = text; _hasDescription = true; });
      } else {
        final raw = result['fields'];
        if (raw is! Map) throw StateError('Invalid proposed fields.');
        // The existing editor uses YER. Do not relabel a foreign amount as YER.
        final foreign = raw['currency'] != null && raw['currency'] != 'YER';
        final fields = <String, dynamic>{for (final entry in raw.entries)
          if (labels.containsKey(entry.key) && entry.value != null && !(foreign && const ['price', 'monthly_rent'].contains(entry.key)))
            entry.key.toString(): entry.value};
        setState(() { _fields = fields; _selected..clear()..addAll(fields.keys);
          if (foreign) _error = 'حقل السعر هنا بالريال اليمني. أدخل المبلغ المناسب يدويًا؛ لم نغيّر العملة.'; });
      }
    } catch (error) { if (mounted) setState(() => _error = friendlyApiError(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _voice() async {
    setState(() { _voiceBusy = true; _error = null; });
    try {
      final text = await ref.read(voiceInputProvider).recognize();
      if (mounted && text?.trim().isNotEmpty == true) _message.text = text!.trim();
    } catch (_) { if (mounted) setState(() => _error = 'تعذّر تحويل الصوت إلى نص. اكتب تفاصيل العقار هنا.'); }
    finally { if (mounted) setState(() => _voiceBusy = false); }
  }

  String _value(String key, dynamic value) => switch (key) {
    'type' => SmartSearchFilters.types[value] ?? '$value', 'purpose' => value == 'rent' ? 'للإيجار' : 'للبيع',
    'building_facade' => SmartSearchFilters.facades[value] ?? '$value', 'area_unit' => propertyAreaUnitLabel(value.toString()),
    'tenure_type' => value == 'waqf' ? 'وقف' : 'حر',
    'has_parking' || 'has_elevator' || 'unit_occupies_entire_floor' => value == true || value == 1 ? 'نعم' : 'لا',
    _ => '$value',
  };

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: SizedBox(
      height: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .78,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        Text(widget.description ? 'وصف من مواصفاتك' : 'مساعد إضافة العقار', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), const Text('راجع الاقتراح قبل تطبيقه. يبقى الإعلان مسودة حتى تكمل مراجعته وإرساله.'), const SizedBox(height: 16),
        if (!widget.description) ...[
          TextField(controller: _message, maxLength: 1500, maxLines: 4, enabled: !_busy,
            decoration: const InputDecoration(labelText: 'صف العقار', hintText: 'مثال: شقة للإيجار في حدة، ثلاث غرف بالدور الثاني…')),
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: _busy || _voiceBusy ? null : _voice,
            icon: const EbrokerIcon(Icons.mic_none, size: 20), label: Text(_voiceBusy ? 'جار الاستماع…' : 'وصف بالصوت'))),
        ],
        AppButton(label: _busy ? 'جار تجهيز الاقتراح…' : widget.description ? 'إنشاء وصف' : 'اقتراح الحقول',
          onPressed: _busy || _voiceBusy ? null : _request, expand: true),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: AppInlineMessage(message: _error!, tone: AppStatusTone.warning)),
        if (_fields != null) ...[
          const SizedBox(height: 16), Text(_fields!.isEmpty ? 'لم نجد مواصفات واضحة. يمكنك إكمال الحقول يدويًا.' : 'المواصفات المقترحة', style: Theme.of(context).textTheme.titleMedium),
          for (final entry in _fields!.entries) CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(labels[entry.key]!),
            subtitle: Text(_value(entry.key, entry.value)), value: _selected.contains(entry.key),
            onChanged: _busy ? null : (value) => setState(() { if (value == true) _selected.add(entry.key); else _selected.remove(entry.key); })),
          const SizedBox(height: 12), AppButton(label: 'تطبيق المواصفات المحددة', expand: true,
            onPressed: _busy || _selected.isEmpty ? null : () => Navigator.of(context).pop({for (final key in _selected) key: _fields![key]})),
        ],
        if (_hasDescription) ...[
          const SizedBox(height: 16), TextField(controller: _description, maxLines: 7, maxLength: 4000,
            decoration: const InputDecoration(labelText: 'راجع الوصف وعدّله إن احتجت')),
          const SizedBox(height: 12), AppButton(label: 'استخدام الوصف بعد المراجعة', expand: true,
            onPressed: _busy ? null : () => Navigator.of(context).pop({'description': _description.text.trim()})),
        ],
      ]))));
}
