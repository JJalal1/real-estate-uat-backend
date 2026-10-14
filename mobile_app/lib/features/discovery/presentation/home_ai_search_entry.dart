import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/voice_input.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../data/smart_search_session.dart';

class HomeAiSearchEntry extends ConsumerStatefulWidget {
  const HomeAiSearchEntry({super.key});
  @override
  ConsumerState<HomeAiSearchEntry> createState() => _HomeAiSearchEntryState();
}

class _HomeAiSearchEntryState extends ConsumerState<HomeAiSearchEntry> {
  final _text = TextEditingController();
  bool _listening = false;
  String? _error;
  @override
  void dispose() { _text.dispose(); super.dispose(); }

  void _submit(String text) {
    if (text.trim().isEmpty || ref.read(smartSearchSessionProvider).interpreting) return;
    FocusScope.of(context).unfocus();
    _text.clear();
    unawaited(ref.read(smartSearchSessionProvider.notifier).interpret(text));
    context.push('/smart-search');
  }
  Future<void> _voice() async {
    final revision = ref.read(smartSearchSessionProvider).revision;
    setState(() { _listening = true; _error = null; });
    try {
      final text = await ref.read(voiceInputProvider).recognize();
      if (mounted && text != null && text.trim().isNotEmpty && revision == ref.read(smartSearchSessionProvider).revision) {
        _submit(text.length > 1000 ? text.substring(0, 1000) : text);
      }
    } catch (_) { if (mounted) setState(() => _error = 'يمكنك كتابة طلبك؛ الصوت غير متاح الآن.'); }
    finally { if (mounted) setState(() => _listening = false); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), search = ref.watch(smartSearchSessionProvider);
    final hasContext = search.filters.chips.isNotEmpty;
    return Container(key: const ValueKey('home-smart-search'), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: .055),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: .10)), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [EbrokerIcon(Icons.auto_awesome_outlined, size: 20, color: theme.colorScheme.primary), const SizedBox(width: 8),
          Expanded(child: Text(hasContext ? 'أكمل بحثك' : 'مكان يناسبك', style: theme.textTheme.titleMedium)),
          TextButton(onPressed: () => context.push('/smart-search'), child: Text(hasContext ? 'شروط بحثك' : 'الفلاتر'))]),
        TextField(key: const ValueKey('home-ai-description'), controller: _text, maxLength: 1000, minLines: 1, maxLines: 3,
          textInputAction: TextInputAction.search, onSubmitted: _submit,
          decoration: InputDecoration(border: InputBorder.none, counterText: '',
            hintText: hasContext ? 'عدّل السعر أو الغرف… سنحتفظ ببقية شروطك' : 'شقة للإيجار في صنعاء، ثلاث غرف…')),
        if (hasContext) Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text(
          search.filters.chips.take(3).map((chip) => chip.$2).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
        Row(children: [
          Expanded(child: FilledButton.icon(key: const ValueKey('home-ai-send'), onPressed: search.interpreting || _listening ? null : () => _submit(_text.text),
            icon: const EbrokerIcon(Icons.arrow_back, size: 18), label: Text(hasContext ? 'تحديث البحث' : 'ابحث لي'))),
          const SizedBox(width: 8), IconButton.filledTonal(key: const ValueKey('home-ai-voice'), tooltip: 'البحث بالصوت', onPressed: search.interpreting || _listening ? null : _voice,
            icon: _listening ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const EbrokerIcon(Icons.mic_none_outlined, size: 22)),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: theme.textTheme.bodySmall)),
      ]));
  }
}
