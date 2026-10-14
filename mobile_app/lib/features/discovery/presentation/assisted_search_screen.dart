import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/voice_input.dart';
import '../../../core/platform/voice_capture_controller.dart';
import '../../../core/widgets/inline_voice_capture.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_property_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../data/smart_search_session.dart';
import '../domain/smart_search_filters.dart';

class AssistedSearchScreen extends ConsumerStatefulWidget {
  const AssistedSearchScreen({super.key});
  @override
  ConsumerState<AssistedSearchScreen> createState() => _AssistedSearchState();
}

class _AssistedSearchState extends ConsumerState<AssistedSearchScreen> {
  final _description = TextEditingController();
  late final VoiceCaptureController _capture;
  String _voiceDraft = '';

  @override
  void initState() {
    super.initState(); _capture = VoiceCaptureController(ref.read(voiceInputProvider))..addListener(_voiceChanged);
  }
  void _voiceChanged() {
    if (!mounted) return;
    if (_capture.active && _capture.transcript.isNotEmpty) _description.text = _searchText(_capture.transcript);
    setState(() {});
  }
  String _searchText(String text) => text.length > 1000 ? text.substring(0, 1000) : text;

  @override
  void dispose() { _capture.removeListener(_voiceChanged); _capture.dispose(); _description.dispose(); super.dispose(); }

  Future<void> _send() async {
    final text = _description.text.trim();
    if (text.isEmpty || _capture.active || ref.read(smartSearchSessionProvider).interpreting) return;
    FocusScope.of(context).unfocus();
    _capture.clearError();
    _description.clear();
    await ref.read(smartSearchSessionProvider.notifier).interpret(text);
    if (mounted && ref.read(smartSearchSessionProvider).aiError != null && _description.text.isEmpty) _description.text = text;
  }

  Future<void> _voice() async {
    if (_capture.active || ref.read(smartSearchSessionProvider).interpreting) return;
    FocusScope.of(context).unfocus();
    final revision = ref.read(smartSearchSessionProvider).revision;
    _voiceDraft = _description.text;
    final text = await _capture.start();
    if (!mounted) return;
    if (text == null) {
      _description.text = _capture.error != null && _capture.transcript.isNotEmpty ? _searchText(_capture.transcript) : _voiceDraft;
    } else if (revision == ref.read(smartSearchSessionProvider).revision && ModalRoute.of(context)?.isCurrent != false) {
      _description.text = _searchText(text); await _send();
    }
  }
  void _cancelVoice() { if (_capture.active) { _capture.cancel(); _description.text = _voiceDraft; } }

  Future<void> _edit({String? focus}) async {
    if (_capture.active) _cancelVoice();
    final next = await AppBottomSheet.show<SmartSearchFilters>(context,
      builder: (_) => _SearchFilterEditor(initial: ref.read(smartSearchSessionProvider).filters, focus: focus));
    if (next != null && mounted) ref.read(smartSearchSessionProvider.notifier).replaceManually(next);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartSearchSessionProvider), theme = Theme.of(context);
    ref.listen<SmartSearchState>(smartSearchSessionProvider, (before, after) {
      if (_capture.active && before?.revision != after.revision) _cancelVoice();
    });
    if (ModalRoute.of(context)?.isCurrent == false && _capture.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _capture.active) _cancelVoice(); });
    }
    final controller = ref.read(smartSearchSessionProvider.notifier);
    final chips = state.filters.chips;
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppAppBar(title: 'البحث الذكي', actions: [
        TextButton(key: const ValueKey('smart-search-reset'), onPressed: () {
          _cancelVoice(); _capture.clearError(); _description.clear(); controller.reset();
        }, child: const Text('بدء بحث جديد')),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
        Text('مكان يناسبك', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('صف ما تبحث عنه، ثم أكمل طلبك أو عدّل أي شرط.'),
        const SizedBox(height: 18),
        AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_capture.active) InlineVoiceCapture(capture: _capture, onCancel: _cancelVoice)
          else TextField(key: const ValueKey('smart-search-description'), controller: _description,
            minLines: 2, maxLines: 4, maxLength: 1000, textInputAction: TextInputAction.search,
            onSubmitted: (_) => _send(), decoration: InputDecoration(border: InputBorder.none,
              hintText: chips.isEmpty ? 'شقة للإيجار في صنعاء، ثلاث غرف…' : 'أكمل بحثك… مثل: خفّض السعر أو أزل شرط الغرف', counterText: '')),
          const SizedBox(height: 8),
          if (!_capture.active) Row(children: [
            Expanded(child: AppButton(key: const ValueKey('smart-search-send'), label: chips.isEmpty ? 'ابحث لي' : 'تحديث البحث',
              icon: Icons.auto_awesome_outlined, loading: state.interpreting,
              onPressed: state.interpreting ? null : _send)),
            const SizedBox(width: 8),
            IconButton.filledTonal(key: const ValueKey('smart-search-voice'), tooltip: 'أكمل بحثك بالصوت',
              onPressed: state.interpreting ? null : _voice,
              icon: const EbrokerIcon(Icons.mic_none_outlined, size: 22)),
          ]),
          if (_capture.error != null || state.aiError != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_capture.error ?? state.aiError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
        ])),
        const SizedBox(height: 18),
        Row(children: [Expanded(child: Text(chips.isEmpty ? 'اختر ما يناسبك' : 'شروط بحثك', style: theme.textTheme.titleMedium)),
          TextButton.icon(key: const ValueKey('smart-search-manual'), onPressed: () => _edit(), icon: const EbrokerIcon(Icons.tune, size: 18), label: const Text('تعديل الفلاتر'))]),
        if (chips.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: [for (final chip in chips)
          ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 36), child: InputChip(
            key: ValueKey('smart-chip-${chip.$1}'), label: Text(chip.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
            onPressed: () => _edit(focus: chip.$1), onDeleted: () { if (_capture.active) _cancelVoice(); controller.remove(chip.$1); }, deleteButtonTooltipMessage: 'إزالة ${chip.$2}')),
        ]),
        if (state.message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(state.message, style: theme.textTheme.bodySmall)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final key in state.filters.suggestions.take(3))
          ActionChip(label: Text('أضف ${SmartSearchFilters.labels[key] ?? key}'), avatar: const EbrokerIcon(Icons.add, size: 16), onPressed: () => _edit(focus: key)),
        ]),
        if (!state.started) ...[
          const SizedBox(height: 22),
          const Text('جرّب مثلًا'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [for (final example in const ['شقة للإيجار في صنعاء', 'منزل للبيع', 'أرض في صنعاء'])
            ActionChip(label: Text(example), onPressed: state.interpreting ? null : () { _description.text = example; _send(); })]),
        ] else ...[
          const SizedBox(height: 28),
          Row(children: [Expanded(child: Text('عقارات تناسب بحثك', style: theme.textTheme.titleMedium)),
            if (state.loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))]),
          const SizedBox(height: 12),
          if (state.loading && state.rows.isEmpty) ...[
            const AppSkeleton(height: 170, radius: 12), const SizedBox(height: 12), const AppSkeleton(height: 170, radius: 12),
          ] else if (state.resultsError != null)
            AppErrorState(message: state.resultsError!, onRetry: () => controller.search(more: state.rows.isNotEmpty))
          else if (state.rows.isEmpty)
            AppEmptyState(title: 'لا توجد عقارات بهذه الشروط', message: 'وسّع الميزانية أو عدّل الموقع والنوع.', actionLabel: 'تعديل الشروط', onAction: () => _edit()),
          for (final row in state.rows) Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            EbrokerPropertyHorizontalCard(imageFirst: false, title: row.title, price: row.price.toStringAsFixed(0), currency: row.currency,
              imageUrl: row.mainImage, imageUrls: row.imageUrls, isSpotlight: row.isSpotlight, location: row.address,
              categoryLabel: ebrokerPropertyTypeLabel(row.type), purposeLabel: row.purpose == 'rent' ? 'للإيجار' : 'للبيع',
              onTap: () => context.push('/properties/${row.id}')),
            if (row.monthlyRent != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('الإيجار الشهري: ${row.monthlyRent!.toStringAsFixed(0)} ${row.currency}', style: theme.textTheme.bodySmall)),
            if (row.priceDisplayNote != null) Text(row.priceDisplayNote!, style: theme.textTheme.bodySmall),
          ])),
          if (state.more && state.resultsError == null) TextButton(onPressed: state.loading ? null : () => controller.search(more: true), child: const Text('المزيد من العقارات')),
        ],
      ]),
    ));
  }
}

class _SearchFilterEditor extends StatefulWidget {
  const _SearchFilterEditor({required this.initial, this.focus});
  final SmartSearchFilters initial;
  final String? focus;
  @override
  State<_SearchFilterEditor> createState() => _SearchFilterEditorState();
}

class _SearchFilterEditorState extends State<_SearchFilterEditor> {
  static const _numbers = ['min_price', 'max_price', 'min_bedrooms', 'min_bathrooms', 'min_area_m2', 'max_area_m2'];
  late Map<String, dynamic> _values;
  late Map<String, TextEditingController> _text;
  String? _error;
  @override
  void initState() {
    super.initState(); _values = Map.of(widget.initial.values);
    _text = {for (final key in ['search', 'floor_number', ..._numbers]) key: TextEditingController(text: _values[key]?.toString() ?? '')};
  }
  @override
  void dispose() { for (final controller in _text.values) { controller.dispose(); } super.dispose(); }

  String _digits(String text) {
    const digits = {'٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9', '٫': '.', '٬': '', ',': ''};
    return text.trim().split('').map((char) => digits[char] ?? char).join();
  }
  void _save() {
    final next = Map<String, dynamic>.from(_values);
    for (final entry in _text.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) { next.remove(entry.key); continue; }
      if (_numbers.contains(entry.key)) {
        final value = double.tryParse(_digits(text));
        final rooms = const ['min_bedrooms', 'min_bathrooms'].contains(entry.key);
        if (value == null || !value.isFinite || value < 0 || value > (rooms ? 50 : 1000000000000) || (rooms && value != value.roundToDouble())) {
          setState(() => _error = 'أدخل أرقامًا صحيحة للغرف والمساحة والميزانية.'); return;
        }
        next[entry.key] = rooms ? value.toInt() : value;
      } else { next[entry.key] = text; }
    }
    for (final pair in const [('min_price', 'max_price'), ('min_area_m2', 'max_area_m2')]) {
      if (next[pair.$1] is num && next[pair.$2] is num && (next[pair.$1] as num) > (next[pair.$2] as num)) {
        setState(() => _error = 'الحد الأدنى يجب ألا يتجاوز الحد الأعلى.'); return;
      }
    }
    Navigator.of(context).pop(SmartSearchFilters.fromMap(next));
  }

  Widget _field(String key, String label) => Padding(padding: const EdgeInsets.only(top: 12), child: TextField(
    key: ValueKey('filter-$key'), controller: _text[key], autofocus: widget.focus == key,
    maxLength: key == 'search' ? 120 : key == 'floor_number' ? 32 : 24,
    keyboardType: _numbers.contains(key) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: InputDecoration(labelText: label, counterText: '')));
  Widget _boolean(String key, String label) => Padding(padding: const EdgeInsets.only(top: 12), child: DropdownButtonFormField<bool>(
    value: _values[key] as bool?, isExpanded: true, decoration: InputDecoration(labelText: label),
    items: const [DropdownMenuItem(value: null, child: Text('لا يشترط')), DropdownMenuItem(value: true, child: Text('نعم')), DropdownMenuItem(value: false, child: Text('لا'))],
    onChanged: (value) => setState(() { if (value == null) { _values.remove(key); } else { _values[key] = value; } })));

  @override
  Widget build(BuildContext context) {
    final type = _values['type'], rent = _values['purpose'] == 'rent';
    return Directionality(textDirection: TextDirection.rtl, child: Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('شروط البحث', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 18),
        DropdownButtonFormField<String>(key: const ValueKey('filter-type'), value: _values['type'] as String?, isExpanded: true,
          decoration: const InputDecoration(labelText: 'نوع العقار'), items: [const DropdownMenuItem(value: null, child: Text('كل الأنواع')),
            for (final entry in SmartSearchFilters.types.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
          onChanged: (value) => setState(() { if (value == null) { _values.remove('type'); } else { _values['type'] = value; } })),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(key: const ValueKey('filter-purpose'), value: _values['purpose'] as String?, isExpanded: true,
          decoration: const InputDecoration(labelText: 'الغرض'), items: const [DropdownMenuItem(value: null, child: Text('بيع وإيجار')),
            DropdownMenuItem(value: 'sale', child: Text('بيع')), DropdownMenuItem(value: 'rent', child: Text('إيجار'))],
          onChanged: (value) => setState(() { if (value == null) { _values.remove('purpose'); } else { _values['purpose'] = value; } })),
        _field('search', 'المحافظة أو المنطقة'),
        _field('min_price', rent ? 'من إيجار شهري' : 'أقل سعر'), _field('max_price', rent ? 'حتى إيجار شهري' : 'أعلى سعر'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _values['currency'] as String?, isExpanded: true, decoration: const InputDecoration(labelText: 'العملة'),
          items: const [DropdownMenuItem(value: null, child: Text('ريال يمني للميزانية')), DropdownMenuItem(value: 'YER', child: Text('ريال يمني')),
            DropdownMenuItem(value: 'USD', child: Text('دولار')), DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي'))],
          onChanged: (value) => setState(() { if (value == null) { _values.remove('currency'); } else { _values['currency'] = value; } })),
        _field('min_area_m2', 'أقل مساحة بالمتر المربع'), _field('max_area_m2', 'أقصى مساحة بالمتر المربع'),
        if (type == null || const ['apartment', 'house', 'villa'].contains(type)) ...[_field('min_bedrooms', 'غرف النوم على الأقل'), _field('min_bathrooms', 'دورات المياه على الأقل')],
        if (const ['apartment', 'office', 'shop'].contains(type)) _field('floor_number', 'الدور'),
        if (type == 'apartment') _boolean('unit_occupies_entire_floor', 'الوحدة تشغل الدور كاملًا'),
        if (const ['apartment', 'building', 'office'].contains(type)) _boolean('has_elevator', 'مصعد'),
        if (!const ['land', 'farm'].contains(type)) ...[_boolean('has_parking', 'موقف'), const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _values['building_facade'] as String?, isExpanded: true, decoration: const InputDecoration(labelText: 'الواجهة'),
            items: [const DropdownMenuItem(value: null, child: Text('كل الواجهات')), for (final entry in SmartSearchFilters.facades.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
            onChanged: (value) => setState(() { if (value == null) { _values.remove('building_facade'); } else { _values['building_facade'] = value; } }))],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 20), AppButton(label: 'تطبيق الشروط', expand: true, onPressed: _save),
      ]))));
  }
}
