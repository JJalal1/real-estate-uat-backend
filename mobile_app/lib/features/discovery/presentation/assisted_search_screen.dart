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
import 'smart_search_filter_editor.dart';

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
  String _searchText(String text) => text;

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
      builder: (_) => SmartSearchFilterEditor(initial: ref.read(smartSearchSessionProvider).filters, focus: focus));
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
            minLines: 2, maxLines: 4, maxLength: 5000, textInputAction: TextInputAction.search,
            onSubmitted: (_) => _send(), decoration: InputDecoration(border: InputBorder.none,
              hintText: chips.isEmpty ? 'شقة للإيجار في صنعاء، ثلاث غرف…' : 'أكمل بحثك… مثل: خفّض السعر أو أزل شرط الغرف', counterText: '')),
          if (!_capture.active && state.lastRequest.isNotEmpty) ExpansionTile(tilePadding: EdgeInsets.zero,
            title: const Text('آخر طلب في هذه الجلسة'), children: [SelectableText(state.lastRequest)]),
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
        const SizedBox(height: 12),
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
        ])),
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
            EbrokerPropertyHorizontalCard(key: ValueKey('smart-search-result-${row.id}'), imageFirst: false, title: row.title, price: (row.monthlyRent ?? row.price).toStringAsFixed(0), currency: row.currency,
              imageUrl: row.mainImage, imageUrls: row.imageUrls, isSpotlight: row.isSpotlight, location: row.address,
              facts: [if (row.bedrooms != null) AppPropertyFact(icon: Icons.bed_outlined, label: '${row.bedrooms} غرف'), if (row.areaM2 != null) AppPropertyFact(icon: Icons.square_foot, label: '${row.areaM2} م²'), if (row.floorNumber != null) AppPropertyFact(icon: Icons.layers_outlined, label: row.floorNumber!)],
              categoryLabel: ebrokerPropertyTypeLabel(row.type), purposeLabel: row.purpose == 'rent' ? (row.monthlyRent == null ? 'للإيجار' : 'إيجار شهري') : 'للبيع',
              onTap: () => context.push('/properties/${row.id}')),
            if (row.priceDisplayNote != null && (row.monthlyRent == null || row.priceDisplayNote!.contains('السعي'))) Text(row.priceDisplayNote!, style: theme.textTheme.bodySmall),
          ])),
          if (state.more && state.resultsError == null) TextButton(onPressed: state.loading ? null : () => controller.search(more: true), child: const Text('المزيد من العقارات')),
        ],
      ]),
    ));
  }
}
