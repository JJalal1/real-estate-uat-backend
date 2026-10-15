import 'dart:async';
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

class HomeAiSearchEntry extends ConsumerStatefulWidget {
  const HomeAiSearchEntry({this.location = 'صنعاء', this.type, super.key});
  final String location;
  final String? type;
  @override
  ConsumerState<HomeAiSearchEntry> createState() => _HomeAiSearchEntryState();
}

class _HomeAiSearchEntryState extends ConsumerState<HomeAiSearchEntry> {
  final _text = TextEditingController();
  late final VoiceCaptureController _capture;
  String _voiceDraft = '';
  @override
  void initState() {
    super.initState();
    _capture = VoiceCaptureController(ref.read(voiceInputProvider))..addListener(_voiceChanged);
  }
  void _voiceChanged() {
    if (!mounted) return;
    if (_capture.active && _capture.transcript.isNotEmpty) _text.text = _searchText(_capture.transcript);
    setState(() {});
  }
  String _searchText(String text) => text;
  @override
  void dispose() { _capture.removeListener(_voiceChanged); _capture.dispose(); _text.dispose(); super.dispose(); }

  void _submit(String text) {
    if (text.trim().isEmpty || _capture.active || ref.read(smartSearchSessionProvider).interpreting) return;
    FocusScope.of(context).unfocus();
    _capture.clearError();
    _text.text = text.trim();
    ref.read(smartSearchSessionProvider.notifier).startFromHome(location: widget.location, type: widget.type);
    unawaited(ref.read(smartSearchSessionProvider.notifier).interpret(text));
  }
  Future<void> _voice() async {
    if (_capture.active || ref.read(smartSearchSessionProvider).interpreting) return;
    FocusScope.of(context).unfocus();
    final revision = ref.read(smartSearchSessionProvider).revision;
    _voiceDraft = _text.text;
    final text = await _capture.start();
    if (!mounted) return;
    if (text == null) {
      _text.text = _capture.error != null && _capture.transcript.isNotEmpty ? _searchText(_capture.transcript) : _voiceDraft;
    } else if (revision == ref.read(smartSearchSessionProvider).revision && ModalRoute.of(context)?.isCurrent != false) {
      _submit(_searchText(text));
    }
  }
  void _cancelVoice() { if (_capture.active) { _capture.cancel(); _text.text = _voiceDraft; } }
  Future<void> _edit({String? focus}) async {
    _cancelVoice();
    final next = await AppBottomSheet.show<SmartSearchFilters>(context,
      builder: (_) => SmartSearchFilterEditor(initial: ref.read(smartSearchSessionProvider).filters, focus: focus));
    if (mounted && next != null) ref.read(smartSearchSessionProvider.notifier).replaceManually(next);
  }
  void _openSearch() {
    _cancelVoice();
    ref.read(smartSearchSessionProvider.notifier).startFromHome(location: widget.location, type: widget.type);
    context.push('/smart-search');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), search = ref.watch(smartSearchSessionProvider);
    ref.listen<SmartSearchState>(smartSearchSessionProvider, (before, after) {
      if (_capture.active && before?.revision != after.revision) _cancelVoice();
    });
    if (ModalRoute.of(context)?.isCurrent == false && _capture.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _capture.active) _cancelVoice(); });
    }
    final hasContext = search.filters.chips.isNotEmpty;
    return Container(key: const ValueKey('home-smart-search'), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: .055),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: .10)), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [EbrokerIcon(Icons.auto_awesome_outlined, size: 20, color: theme.colorScheme.primary), const SizedBox(width: 8),
          Expanded(child: Text(hasContext ? 'أكمل بحثك' : 'مكان يناسبك', style: theme.textTheme.titleMedium)),
          TextButton(onPressed: search.interpreting ? null : () => _edit(), child: const Text('تعديل الفلاتر'))]),
        if (_capture.active) InlineVoiceCapture(capture: _capture, onCancel: _cancelVoice)
        else TextField(key: const ValueKey('home-ai-description'), controller: _text, maxLength: 5000, minLines: 1, maxLines: 3,
          textInputAction: TextInputAction.search, onSubmitted: _submit,
          decoration: InputDecoration(border: InputBorder.none, counterText: '',
            hintText: hasContext ? 'عدّل السعر أو الغرف… سنحتفظ ببقية شروطك' : 'شقة للإيجار في صنعاء، ثلاث غرف…')),
        if (hasContext) Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Wrap(spacing: 6, runSpacing: 4, children: [
          for (final chip in search.filters.chips) ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 68),
            child: InputChip(key: ValueKey('home-smart-chip-${chip.$1}'), label: Text(chip.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
              onPressed: search.interpreting ? null : () => _edit(focus: chip.$1),
              onDeleted: _capture.active || search.interpreting ? null : () => ref.read(smartSearchSessionProvider.notifier).remove(chip.$1))),
        ])),
        if (!_capture.active) Wrap(spacing: 6, runSpacing: 4, children: [
          for (final key in search.filters.suggestions.take(3)) ActionChip(label: Text('أضف ${SmartSearchFilters.labels[key] ?? key}'),
            avatar: const EbrokerIcon(Icons.add, size: 16), onPressed: search.interpreting ? null : () => _edit(focus: key)),
          if (hasContext || search.started) ActionChip(label: const Text('بحث جديد'), onPressed: () { _cancelVoice(); _text.clear(); ref.read(smartSearchSessionProvider.notifier).reset(); }),
        ]),
        if (!_capture.active) Row(children: [
          Expanded(child: FilledButton.icon(key: const ValueKey('home-ai-send'), onPressed: search.interpreting ? null : () => _submit(_text.text),
            icon: search.interpreting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const EbrokerIcon(Icons.arrow_back, size: 18),
            label: Text(search.interpreting ? 'نفهم طلبك…' : hasContext ? 'تحديث البحث' : 'ابحث لي'))),
          const SizedBox(width: 8), IconButton.filledTonal(key: const ValueKey('home-ai-voice'), tooltip: 'البحث بالصوت', onPressed: search.interpreting ? null : _voice,
            icon: const EbrokerIcon(Icons.mic_none_outlined, size: 22)),
        ]),
        if (_capture.error != null || search.aiError != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(_capture.error ?? search.aiError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
        if (search.started) ...[
          const SizedBox(height: 16), Text('نتائج بحثك', style: theme.textTheme.titleSmall), const SizedBox(height: 8),
          if (search.loading) const AppSkeleton(height: 110, radius: 12)
          else if (search.resultsError != null) AppErrorState(message: search.resultsError!,
            onRetry: () => ref.read(smartSearchSessionProvider.notifier).search())
          else if (search.rows.isEmpty) const Text('لا توجد عقارات بهذه الشروط. جرّب تعديل السعر أو المنطقة.')
          else for (final row in search.rows.take(3)) Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [EbrokerPropertyHorizontalCard(key: ValueKey('home-ai-result-${row.id}'), title: row.title,
              price: (row.monthlyRent ?? row.price).toStringAsFixed(0), currency: row.currency,
              imageUrl: row.mainImage, imageUrls: row.imageUrls, isSpotlight: row.isSpotlight, location: row.address,
              facts: [if (row.bedrooms != null) AppPropertyFact(icon: Icons.bed_outlined, label: '${row.bedrooms} غرف'), if (row.areaM2 != null) AppPropertyFact(icon: Icons.square_foot, label: '${row.areaM2} م²'), if (row.floorNumber != null) AppPropertyFact(icon: Icons.layers_outlined, label: row.floorNumber!)],
              categoryLabel: ebrokerPropertyTypeLabel(row.type), purposeLabel: row.purpose == 'rent' ? (row.monthlyRent == null ? 'للإيجار' : 'إيجار شهري') : 'للبيع',
              onTap: () { _cancelVoice(); context.push('/properties/${row.id}'); }),
              if (row.priceDisplayNote != null && (row.monthlyRent == null || row.priceDisplayNote!.contains('%'))) Text(row.priceDisplayNote!, style: theme.textTheme.bodySmall),
            ])),
          TextButton(key: const ValueKey('home-ai-all-results'), onPressed: _capture.active ? null : _openSearch, child: const Text('عرض كل النتائج والشروط')),
        ],
      ]));
  }
}
