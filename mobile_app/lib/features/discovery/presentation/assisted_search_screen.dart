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
import 'smart_search_assistant.dart';
import 'smart_search_query_summary.dart';
import '../../properties/presentation/save_search_action.dart';
import '../../properties/presentation/property_compare_actions.dart';
import '../../map/presentation/map_screen.dart';
import '../../properties/domain/saved_property_search.dart';

class AssistedSearchScreen extends ConsumerStatefulWidget {
  const AssistedSearchScreen({this.savedSearch, this.initialMapMode = false, this.entryFilters, super.key});
  final SavedPropertySearch? savedSearch;
  final bool initialMapMode;
  final SmartSearchFilters? entryFilters;
  @override
  ConsumerState<AssistedSearchScreen> createState() => _AssistedSearchState();
}

class _AssistedSearchState extends ConsumerState<AssistedSearchScreen> {
  final _description = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final VoiceCaptureController _capture;
  String _voiceDraft = '';
  late final SmartSearchSession _session;
  int _journey = 0;
  bool _ready = false, _mapMode = false;

  @override
  void initState() {
    super.initState();
    _session = ref.read(smartSearchSessionProvider.notifier);
    _mapMode = widget.initialMapMode;
    Future.microtask(() {
      if (!mounted) return;
      _journey = _session.beginJourney(savedFilters: widget.savedSearch == null ? null : SmartSearchFilters.fromApiFilters(widget.savedSearch!.filters), entryFilters: widget.entryFilters);
      setState(() => _ready = true);
    });
    _capture = VoiceCaptureController(ref.read(voiceInputProvider))..addListener(_voiceChanged);
  }
  void _voiceChanged() {
    if (!mounted) return;
    if (_capture.active && _capture.preview.isNotEmpty) {
      final text = appendDictation(_voiceDraft, _capture.preview);
      if (_description.text != text) _description.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() {});
  }
  @override
  void dispose() { if (_journey != 0) _session.endJourney(_journey); _capture.removeListener(_voiceChanged); _capture.dispose(); _description.dispose(); _scroll.dispose(); _focus.dispose(); super.dispose(); }

  Future<void> _send() async {
    final text = _description.text.trim();
    if (text.isEmpty || _capture.active || ref.read(smartSearchSessionProvider).interpreting) return;
    if (text.length > 5000) { setState(() => _capture.error = 'النص أطول من 5000 حرف. اختصره قبل البحث.'); return; }
    FocusScope.of(context).unfocus();
    _capture.clearError();
    _session.setDraftText(text);
    await ref.read(smartSearchSessionProvider.notifier).interpret(text);
  }

  Future<void> _voice() async {
    if (_capture.active || ref.read(smartSearchSessionProvider).interpreting) return;
    FocusScope.of(context).unfocus();
    final revision = ref.read(smartSearchSessionProvider).revision;
    _voiceDraft = _description.text;
    final text = await _capture.start();
    if (!mounted) return;
    if (text == null) {
      _description.text = _voiceDraft;
    } else if (revision == ref.read(smartSearchSessionProvider).revision && ModalRoute.of(context)?.isCurrent != false) {
      final combined = appendDictation(_voiceDraft, text);
      _description.text = combined; _session.setDraftText(combined);
      if (combined.length > 5000) setState(() => _capture.error = 'النص أطول من 5000 حرف. اختصره قبل البحث.');
    }
  }
  void _cancelVoice() { if (_capture.active) { _capture.cancel(); _description.text = _voiceDraft; } }

  Future<void> _edit({String? focus}) async {
    if (_capture.active) _cancelVoice();
    if (focus == 'map_area') { await _openMap(); return; }
    final next = await AppBottomSheet.show<SmartSearchFilters>(context,
      builder: (_) => SmartSearchFilterEditor(initial: ref.read(smartSearchSessionProvider).filters, focus: focus));
    if (next != null && mounted) ref.read(smartSearchSessionProvider.notifier).replaceManually(next);
  }

  Future<void> _openMap() async {
    if (_capture.active) _cancelVoice();
    _session.setDraftText(_description.text);
    setState(() => _mapMode = !_mapMode);
  }

  Widget _mapToolbar(SmartSearchState state) => Material(elevation:2,borderRadius:BorderRadius.circular(16),
    color:Theme.of(context).colorScheme.surface,child:Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(children:[const SmartSearchRobotIcon(size:24),const SizedBox(width:6), Expanded(child:TextField(
        key:const ValueKey('smart-search-description'),controller:_description,focusNode:_focus,readOnly:_capture.active || state.interpreting,
        minLines:1,maxLines:2,onChanged:_session.setDraftText,onSubmitted:(_)=>_send(),
        decoration:InputDecoration(hintText:_capture.active ? null : state.started ? 'أضف أو عدّل أي شرط…' : 'صف العقار الذي تبحث عنه',isDense:true,border:InputBorder.none))),
        IconButton(key:const ValueKey('smart-search-voice'),tooltip:'أكمل بحثك بالصوت',onPressed:state.interpreting?null:_voice,icon:const Icon(Icons.mic_none_outlined)),
        IconButton(key:const ValueKey('smart-search-send'),tooltip:'بحث',onPressed:state.interpreting?null:_send,
          icon:state.interpreting?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.search)),
        IconButton(key:const ValueKey('smart-search-manual'),tooltip:'الفلاتر',onPressed:()=>_edit(),icon:const Icon(Icons.tune)),
      ]),
      if(_capture.active) InlineVoiceCapture(capture:_capture,onCancel:_cancelVoice),
      if(_capture.error!=null || state.aiError!=null) Text(_capture.error ?? state.aiError!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(state.page>0 && !state.loading && state.resultsError==null) Align(alignment:AlignmentDirectional.centerStart,
        child:TextButton.icon(key:const ValueKey('smart-search-save'),onPressed:()=>saveSearchFilters(context,ref,state.filters.apiFilters),
          icon:const Icon(Icons.bookmark_add_outlined,size:18),label:const Text('حفظ البحث والتنبيه'))),
    ])));

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final state = ref.watch(smartSearchSessionProvider), theme = Theme.of(context);
    ref.listen<SmartSearchState>(smartSearchSessionProvider, (before, after) {
      if (_capture.active && before?.revision != after.revision) _cancelVoice();
      // Applied criteria belong to the summary. Only consume the exact draft
      // that was accepted; manual changes and newer unsent text stay intact.
      if (before != null && before.revision != after.revision &&
          before.draftText.isNotEmpty && after.draftText.isEmpty &&
          _description.text.trim() == before.draftText.trim()) {
        _description.clear();
      }
    });
    if (ModalRoute.of(context)?.isCurrent == false && _capture.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _capture.active) _cancelVoice(); });
    }
    if (_mapMode) { return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      appBar:AppAppBar(title:'البحث على الخريطة',actions:[TextButton(key:const ValueKey('smart-search-list'),onPressed:_openMap,child:const Text('القائمة'))]),
      body:MapScreen(sharedSearchJourney:true,searchToolbar:_mapToolbar(state),onShowList:_openMap))); }
    final controller = ref.read(smartSearchSessionProvider.notifier);
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppAppBar(title: 'البحث الذكي', actions: [
        IconButton(key: const ValueKey('smart-search-reset'), tooltip: 'بدء بحث جديد', onPressed: () {
          _cancelVoice(); _capture.clearError(); _description.clear(); controller.reset(useLocation: true);
        }, icon: const Icon(Icons.restart_alt)),
      ]),
      body: SmartSearchAssistantLayer(enabled: state.started && !_capture.active, onPressed: () {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); _focus.requestFocus();
      }, child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(18, 12, 18, 110), children: [
        if (!state.started) ...[
          Text('مكان يناسبك', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('صف ما تبحث عنه، ثم أكمل طلبك أو عدّل أي شرط.'),
          const SizedBox(height: 18),
        ],
        AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (state.started || state.interpreting) ...[
            SmartSearchQuerySummary(
              filters: state.started ? state.filters : const SmartSearchFilters(),
              interpreting: state.interpreting,
              onEdit: (key) => _edit(focus: key),
              onRemove: (key) { if (_capture.active) { _cancelVoice(); } controller.remove(key); },
            ),
            const SizedBox(height: 12),
          ],
          if (state.started) ...[
            Wrap(spacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('أضف أو عدّل أي شرط', style: theme.textTheme.titleSmall),
              TextButton.icon(key: const ValueKey('smart-search-manual'), onPressed: () => _edit(),
                icon: const EbrokerIcon(Icons.tune, size: 18), label: const Text('تعديل الفلاتر')),
            ]),
            const SizedBox(height: 4),
          ],
          TextField(key: const ValueKey('smart-search-description'), controller: _description, focusNode: _focus,
            readOnly: _capture.active || state.interpreting,
            minLines: state.started ? 1 : 2, maxLines: 4, maxLength: 5000, textInputAction: TextInputAction.search,
            onChanged: _session.setDraftText, onSubmitted: (_) => _send(), decoration: InputDecoration(border: InputBorder.none,
              hintText: _capture.active ? null : !state.started ? 'شقة للإيجار في صنعاء، ثلاث غرف…' : 'أكمل بحثك… مثل: خفّض السعر أو أزل شرط الغرف', counterText: '')),
          if (_capture.active) InlineVoiceCapture(capture: _capture, onCancel: _cancelVoice),
          const SizedBox(height: 8),
          if (!_capture.active && !state.started) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('اكتب أو أمْلِ طلبك، راجعه ثم اضغط البحث.')),
          if (!_capture.active) Row(children: [
            Expanded(child: AppButton(key: const ValueKey('smart-search-send'), label: !state.started ? 'ابحث لي' : 'تحديث',
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
        Wrap(spacing: 8, children: [
          if (state.page > 0 && !state.loading && state.resultsError == null) TextButton.icon(key: const ValueKey('smart-search-save'), onPressed: _capture.active || state.interpreting ? null : () => saveSearchFilters(context, ref, state.filters.apiFilters),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18), label: const Text('حفظ البحث')),
          TextButton.icon(key: const ValueKey('smart-search-map'), onPressed: _capture.active || state.interpreting ? null : _openMap,
            icon: const Icon(Icons.map_outlined, size: 18), label: const Text('الخريطة')),
        ]),
        if (state.message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(state.message, style: theme.textTheme.bodySmall)),
        const SizedBox(height: 10),
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
            PropertyCompareAction(propertyId: row.id, enabled: row.status == 'published'),
            if (row.priceDisplayNote != null && (row.monthlyRent == null || row.priceDisplayNote!.contains('السعي'))) Text(row.priceDisplayNote!, style: theme.textTheme.bodySmall),
          ])),
          if (state.more && state.resultsError == null) TextButton(onPressed: state.loading ? null : () => controller.search(more: true), child: const Text('المزيد من العقارات')),
        ],
      ])),
    ));
  }
}
