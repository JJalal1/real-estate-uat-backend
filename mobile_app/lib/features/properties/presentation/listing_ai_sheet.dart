import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/voice_input.dart';
import '../../../core/platform/voice_capture_controller.dart';
import '../../../core/widgets/inline_voice_capture.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../discovery/data/ai_repository.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../domain/property_field_options.dart';

class ListingAiSheet extends ConsumerStatefulWidget {
  const ListingAiSheet({required this.facts, this.propertyId, this.description = false,
    this.prepareDraft = false, this.initialMessage = '', this.onMessageChanged,
    this.hasExistingDescription = false, super.key});
  final Map<String, dynamic> facts;
  final int? propertyId;
  final bool description, prepareDraft, hasExistingDescription;
  final String initialMessage;
  final ValueChanged<String>? onMessageChanged;
  @override
  ConsumerState<ListingAiSheet> createState() => _ListingAiSheetState();
}

class _ListingAiSheetState extends ConsumerState<ListingAiSheet> {
  final _message = TextEditingController(), _description = TextEditingController(), _title = TextEditingController();
  final _selected = <String>{};
  Map<String, dynamic>? _fields;
  bool _busy = false, _hasDescription = false, _copyReady = false;
  late final VoiceCaptureController _capture;
  String _voiceDraft = '';
  bool _restoringVoice = false;
  bool get _voiceBusy => _capture.active;
  String? _error, _notice, _source;
  static const labels = {'title': 'عنوان الإعلان', 'type': 'نوع العقار', 'purpose': 'الغرض', 'price': 'سعر البيع بالريال اليمني',
    'monthly_rent': 'الإيجار الشهري بالريال اليمني', 'area_value': 'المساحة', 'area_unit': 'وحدة المساحة',
    'bedrooms': 'غرف النوم', 'bathrooms': 'الحمامات', 'governorate': 'المحافظة', 'district': 'الحي', 'street': 'الشارع',
    'floor_number': 'الدور', 'unit_number': 'موضع الوحدة', 'has_parking': 'موقف السيارة', 'has_elevator': 'المصعد',
    'building_facade': 'واجهة البناء', 'tenure_type': 'نوع الملكية'};

  @override
  void initState() {
    super.initState();
    _message.text = widget.initialMessage;
    _message.addListener(_briefChanged);
    _capture = VoiceCaptureController(ref.read(voiceInputProvider))..addListener(_voiceChanged);
  }

  void _briefChanged() {
    if (_capture.active || _restoringVoice) return;
    widget.onMessageChanged?.call(_message.text);
    if (widget.prepareDraft && _fields != null && mounted) {
      setState(() { _fields = null; _selected.clear(); _copyReady = false; _notice = null; });
    }
  }

  void _voiceChanged() {
    if (!mounted) return;
    if (_capture.active && _capture.preview.isNotEmpty) {
      final text = appendDictation(_voiceDraft, _capture.preview);
      if (_message.text != text) _message.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() {});
  }

  @override
  void dispose() {
    _capture.removeListener(_voiceChanged); _capture.dispose();
    _message.removeListener(_briefChanged); _message.dispose(); _description.dispose(); _title.dispose();
    super.dispose();
  }

  void _setCopy(dynamic raw) {
    if (raw is! Map || raw['title'] is! String || raw['description'] is! String ||
        (raw['title'] as String).length > 160 || (raw['description'] as String).length > 4000) {
      throw StateError('Invalid listing copy.');
    }
    _title.text = raw['title'] as String;
    _description.text = raw['description'] as String;
    _copyReady = true;
  }

  Future<void> _request() async {
    if (_busy || _voiceBusy || !widget.description && _message.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(aiRepositoryProvider);
      final result = widget.description
        ? await api.description(widget.facts, propertyId: widget.propertyId)
        : widget.prepareDraft
          ? await api.prepareListing(_message.text, widget.facts, propertyId: widget.propertyId)
          : await api.listingFields(_message.text, widget.facts, propertyId: widget.propertyId);
      if (!mounted) return;
      if (widget.description) {
        final text = result['description'];
        if (text is! String || text.trim().isEmpty) throw StateError('Empty description.');
        setState(() { _description.text = text; _hasDescription = true; });
      } else {
        final raw = result['fields'];
        if (raw is! Map) throw StateError('Invalid proposed fields.');
        final foreign = raw['currency'] != null && raw['currency'] != 'YER';
        final fields = <String, dynamic>{for (final entry in raw.entries)
          if (labels.containsKey(entry.key) && entry.value != null && !(foreign && const ['price', 'monthly_rent'].contains(entry.key)))
            entry.key.toString(): entry.value};
        setState(() {
          _fields = fields; _selected..clear()..addAll(fields.keys);
          if (widget.prepareDraft) {
            _setCopy(result['copy']);
            _source = result['source']?.toString();
            _notice = result['message']?.toString();
          }
          if (foreign) _error = 'حقل السعر هنا بالريال اليمني. أدخل المبلغ المناسب يدويًا؛ لم نغيّر العملة.';
        });
      }
    } catch (error) {
      if (mounted) setState(() { _error = friendlyApiError(error); _copyReady = false; });
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _refreshCopy() async {
    if (_busy || _voiceBusy || _fields == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final facts = {...widget.facts, for (final key in _selected) key: _fields![key]};
      final result = await ref.read(aiRepositoryProvider).listingCopy(facts, propertyId: widget.propertyId);
      if (!mounted) return;
      setState(() => _setCopy(result['copy']));
    } catch (error) { if (mounted) setState(() => _error = friendlyApiError(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  void _applyDraft() {
    if (!_copyReady || _busy || _voiceBusy) return;
    if (_title.text.trim().length < 4 || _description.text.trim().isEmpty) {
      setState(() => _error = 'راجع العنوان (4 أحرف على الأقل) والوصف قبل الاستخدام.');
      return;
    }
    Navigator.of(context).pop({
      for (final key in _selected) key: _fields![key],
      'title': _title.text.trim(), 'description': _description.text.trim(),
    });
  }

  Future<void> _voice() async {
    if (_busy || _voiceBusy) return;
    FocusScope.of(context).unfocus(); _voiceDraft = _message.text;
    setState(() => _error = null);
    final text = await _capture.start();
    if (!mounted) return;
    if (text == null) { _restoreVoiceDraft(); return; }
    final combined = appendDictation(_voiceDraft, text);
    if (combined.length > 1500) {
      _restoreVoiceDraft();
      setState(() => _error = 'النص أطول من 1500 حرف. اختصر الوصف أو أمْلِ تفاصيل أقل.');
    } else { _message.text = combined; }
  }
  void _restoreVoiceDraft() { _restoringVoice = true; _message.text = _voiceDraft; _restoringVoice = false; }
  void _cancelVoice() { if (_capture.active) { _capture.cancel(); _restoreVoiceDraft(); } }

  String _value(String key, dynamic value) => switch (key) {
    'type' => SmartSearchFilters.types[value] ?? '$value', 'purpose' => value == 'rent' ? 'للإيجار' : 'للبيع',
    'building_facade' => SmartSearchFilters.facades[value] ?? '$value', 'area_unit' => propertyAreaUnitLabel(value.toString()),
    'tenure_type' => value == 'waqf' ? 'وقف' : 'حر',
    'has_parking' || 'has_elevator' || 'unit_occupies_entire_floor' => value == true || value == 1 ? 'نعم' : 'لا',
    _ => '$value',
  };

  String _proposalValue(String key, dynamic value) {
    final old = widget.facts[key];
    return widget.prepareDraft && old != null && old != value
      ? 'الحالي: ${_value(key, old)}\nالمقترح: ${_value(key, value)}' : _value(key, value);
  }

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: SizedBox(
      height: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * .78,
      child: ListView(padding: const EdgeInsets.all(18), children: [
        Text(widget.description ? 'وصف من مواصفاتك' : widget.prepareDraft ? 'جهّز إعلانك بسرعة' : 'مساعد إضافة العقار',
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(widget.prepareDraft ? 'اكتب التفاصيل أو الصق نص إعلانك أو سجّل وصفًا، ثم راجع الحقول والعنوان والوصف معًا.'
          : 'راجع الاقتراح قبل تطبيقه. يبقى الإعلان مسودة حتى تكمل مراجعته وإرساله.'),
        const SizedBox(height: 16),
        if (!widget.description) ...[
          Text('صف العقار', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('listing-ai-brief'), controller: _message, maxLength: 1500, minLines: 2, maxLines: 5, enabled: !_busy, readOnly: _voiceBusy,
            decoration: InputDecoration(labelText: _voiceBusy ? null : 'صف العقار', floatingLabelBehavior: FloatingLabelBehavior.never,
              hintText: _voiceBusy ? null : 'النوع، الموقع، الغرف، الدور، الإيجار أو السعر…')),
          if (_voiceBusy) InlineVoiceCapture(capture: _capture, onCancel: _cancelVoice),
          if (!_voiceBusy) Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: _busy ? null : _voice,
            key: const ValueKey('listing-ai-voice'),
            icon: const EbrokerIcon(Icons.mic_none, size: 20), label: const Text('أمْلِ تفاصيل العقار'))),
        ],
        AppButton(key: const ValueKey('listing-ai-prepare'),
          label: _busy ? 'جار تجهيز الاقتراح…' : widget.description ? 'إنشاء وصف' : widget.prepareDraft ? 'جهّز الإعلان' : 'اقتراح الحقول',
          onPressed: _busy || _voiceBusy ? null : _request, expand: true),
        if (_error != null || _capture.error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: AppInlineMessage(message: _error ?? _capture.error!, tone: AppStatusTone.warning)),
        if (widget.prepareDraft && _notice != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: AppInlineMessage(key: const ValueKey('listing-ai-source'), message: _notice!,
            tone: _source == 'text' ? AppStatusTone.warning : AppStatusTone.info)),
        if (_fields != null) ...[
          const SizedBox(height: 16),
          Text(_fields!.isEmpty ? 'لم نجد مواصفات واضحة في النص. أكمل التفاصيل يدويًا.' : 'راجع ما سيتغير',
            style: Theme.of(context).textTheme.titleMedium),
          for (final entry in _fields!.entries) CheckboxListTile(
            key: ValueKey('listing-ai-field-${entry.key}'), contentPadding: EdgeInsets.zero,
            title: Text(labels[entry.key]!), subtitle: Text(_proposalValue(entry.key, entry.value)),
            value: _selected.contains(entry.key), onChanged: _busy || _voiceBusy ? null : (value) => setState(() {
              if (value == true) { _selected.add(entry.key); } else { _selected.remove(entry.key); }
              if (widget.prepareDraft) _copyReady = false;
            })),
          if (!widget.prepareDraft) ...[
            const SizedBox(height: 12), AppButton(label: 'تطبيق المواصفات المحددة', expand: true,
              onPressed: _busy || _selected.isEmpty ? null : () => Navigator.of(context).pop({for (final key in _selected) key: _fields![key]})),
          ],
        ],
        if (widget.prepareDraft && _fields != null) ...[
          const SizedBox(height: 16),
          if (!_copyReady) ...[
            const Text('حدّث النص ليطابق التفاصيل المحددة، ثم راجعه.'),
            const SizedBox(height: 8),
            AppButton(key: const ValueKey('listing-ai-refresh-copy'), label: 'تجهيز النص من اختياري', expand: true,
              onPressed: _busy || _voiceBusy ? null : _refreshCopy),
          ] else ...[
            if (widget.hasExistingDescription) const AppInlineMessage(
              message: 'اعتماد هذه المسودة يستبدل الوصف الحالي بالنص الذي تراجعه هنا.', tone: AppStatusTone.info),
            Text('عنوان الإعلان', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(key: const ValueKey('listing-ai-title'), controller: _title, maxLength: 160, enabled: !_busy && !_voiceBusy,
              decoration: const InputDecoration(labelText: 'عنوان الإعلان', floatingLabelBehavior: FloatingLabelBehavior.never)),
            const SizedBox(height: 8),
            Text('نص الإعلان', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(key: const ValueKey('listing-ai-copy'), controller: _description, minLines: 3, maxLines: 7,
              maxLength: 4000, enabled: !_busy && !_voiceBusy,
              decoration: const InputDecoration(labelText: 'نص الإعلان', floatingLabelBehavior: FloatingLabelBehavior.never)),
            const SizedBox(height: 12),
            const Text('راجع العنوان والنص، ثم اعتمد المسودة.'),
            const SizedBox(height: 8),
            AppButton(key: const ValueKey('listing-ai-apply-draft'), label: 'اعتماد المسودة', expand: true,
              onPressed: _busy || _voiceBusy ? null : _applyDraft),
            const SizedBox(height: 8),
            const Text('بعد التطبيق أكمل الموقع والصور والمتطلبات، ثم أرسل الإعلان للمراجعة.'),
          ],
        ],
        if (_hasDescription) ...[
          const SizedBox(height: 16), TextField(controller: _description, maxLines: 7, maxLength: 4000,
            decoration: const InputDecoration(labelText: 'راجع الوصف وعدّله إن احتجت')),
          const SizedBox(height: 12), AppButton(label: 'استخدام الوصف بعد المراجعة', expand: true,
            onPressed: _busy ? null : () => Navigator.of(context).pop({'description': _description.text.trim()})),
        ],
      ]))));
}
