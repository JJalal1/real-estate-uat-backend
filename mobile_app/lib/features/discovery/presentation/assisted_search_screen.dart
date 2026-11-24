import '../../account/data/auth_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/voice_input.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/platform/voice_capture_controller.dart';
import '../../../core/widgets/inline_voice_capture.dart';
import '../../../core/widgets/app_components.dart';
import '../../properties/presentation/property_summary_card.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../data/smart_search_session.dart';
import '../data/marketplace_repository.dart';
import '../data/assisted_search_suggestions.dart';
import '../domain/smart_search_filters.dart';
import 'smart_search_filter_editor.dart';
import 'smart_search_assistant.dart';
import 'smart_search_query_summary.dart';
import 'search_result_pagination.dart';
import '../../map/presentation/map_discovery_toolbar.dart';
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
  String _voiceDraft = '', _voiceRestoration = '', _voiceVisibleText = '';
  String? _lastVoiceBase, _lastVoiceText;
  int _voiceTurn = 0;
  SmartSearchSession get _session => ref.read(smartSearchSessionProvider.notifier);
  late SmartSearchSession _journeySession;
  late final int? _entryActor;
  late final int _entryEpoch;
  int? _visibleActor;
  int _visibleEpoch = 0;
  int _journey = 0;
  bool _ready = false;
  bool _showEntryMap = false;
  bool _mapEditorOpen = false;
  LocalHistoryEntry? _mapHistory;
  bool get _showingMap => _showEntryMap || _mapHistory != null;
  bool _journeyEnded = false;

  @override
  void initState() {
    super.initState();
    _showEntryMap = widget.initialMapMode;
    _journeySession = _session;
    _entryActor = ref.read(authControllerProvider).asData?.value?.id;
    _visibleActor = _entryActor;
    _entryEpoch = _visibleEpoch = Stage6SecureSessionStore.instance.sessionEpoch;
    Future.microtask(() {
      if (!mounted || _journeyEnded) return;
      final sameActor = _entryActor == ref.read(authControllerProvider).asData?.value?.id &&
          _entryEpoch == Stage6SecureSessionStore.instance.sessionEpoch;
      _journeySession = _session;
      _journey = _journeySession.beginJourney(
        savedFilters: !sameActor || widget.savedSearch == null ? null : SmartSearchFilters.fromApiFilters(widget.savedSearch!.filters),
        entryFilters: sameActor ? widget.entryFilters : null);
      setState(() => _ready = true);
    });
    _capture = VoiceCaptureController(ref.read(voiceInputProvider))..addListener(_voiceChanged);
  }
  void _voiceChanged() {
    if (!mounted || _journeyEnded) return;
    if (_capture.active && _capture.preview.isNotEmpty) {
      final text = appendDictation(_voiceDraft, _capture.preview);
      _voiceVisibleText = text;
      if (_description.text != text) _description.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() {});
  }
  @override
  void dispose() {
    _capture.removeListener(_voiceChanged);
    _endJourney();
    _mapHistory?.remove();
    _capture.dispose();
    _description.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _endJourney() {
    _journeyEnded = true;
    ++_voiceTurn;
    if (_journey != 0) { _journeySession.endJourney(_journey); _journey = 0; }
    if (_capture.active || _capture.canRetry) _capture.cancel();
  }

  Future<void> _send() async {
    final text = _description.text.trim();
    final state = ref.read(smartSearchSessionProvider);
    if (_journeyEnded || !_journeySession.isCurrentJourney(_journey) || text.isEmpty || _capture.active || state.interpreting ||
      (state.started && state.aiError == null && state.draftText.isEmpty && text == state.lastRequest)) { return; }
    if (text.length > 5000) { setState(() => _capture.error = 'النص أطول من 5000 حرف. اختصره قبل البحث.'); return; }
    FocusScope.of(context).unfocus();
    _capture.clearError();
    _session.setDraftText(text);
    await ref.read(smartSearchSessionProvider.notifier).interpret(text);
  }

  Future<void> _voice({bool retry = false}) async {
    if (_journeyEnded || !_journeySession.isCurrentJourney(_journey) || _capture.active || ref.read(smartSearchSessionProvider).interpreting) return;
    if (retry && !_capture.canRetry) return;
    FocusScope.of(context).unfocus();
    final revision = ref.read(smartSearchSessionProvider).revision;
    final current = ref.read(smartSearchSessionProvider);
    _voiceRestoration = _description.text;
    _voiceDraft = current.started && current.draftText.isEmpty && _description.text.trim() == current.lastRequest
      ? '' : _description.text;
    if (_description.text != _voiceDraft) _description.text = _voiceDraft;
    _voiceVisibleText = _voiceDraft;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final journey = _journey;
    final turn = ++_voiceTurn;
    final text = retry ? await _capture.retryTranscription() : await _capture.start();
    if (!mounted || _journeyEnded || journey != _journey || !_journeySession.isCurrentJourney(journey) || turn != _voiceTurn ||
        epoch != Stage6SecureSessionStore.instance.sessionEpoch || actor != ref.read(authControllerProvider).asData?.value?.id ||
        _description.text != _voiceVisibleText) { return; }
    if (text == null) {
      _description.text = _capture.error != null && _capture.stablePreview.isNotEmpty
        ? appendDictation(_voiceDraft, _capture.stablePreview)
        : _capture.error != null && _capture.preview.trim().isNotEmpty
          ? appendDictation(_voiceDraft, _capture.preview) : _voiceRestoration;
    } else if (revision == ref.read(smartSearchSessionProvider).revision && ModalRoute.of(context)?.isCurrent != false) {
      final combined = appendDictation(_voiceDraft, text);
      _lastVoiceBase = _voiceDraft; _lastVoiceText = combined;
      _description.text = combined; _session.setDraftText(combined);
      if (combined.length > 5000) {
        setState(() => _capture.error = 'النص أطول من 5000 حرف. اختصره قبل البحث.');
      } else if (text.trim().isNotEmpty) {
        // Only the completed, current voice turn submits. Partials, stable
        // segments, cancellation and transcription errors never reach here.
        await _send();
      }
    }
  }
  void _cancelVoice() { if (_capture.active || _capture.canRetry) { ++_voiceTurn; _capture.cancel(); _description.text = _voiceRestoration; } }
  void _restartVoice() {
    if (_capture.active) { _cancelVoice(); }
    else if (_lastVoiceBase != null && _description.text == _lastVoiceText) { _description.text = _lastVoiceBase!; }
    unawaited(_voice());
  }

  Widget _voiceOptions() => Wrap(spacing: 8, children: [
    if (_lastVoiceBase != null && _description.text == _lastVoiceText) TextButton(onPressed: _restartVoice, child: const Text('ابدأ الإملاء من جديد')),
    if (_capture.canRetry) TextButton(key: const ValueKey('search-voice-retry'),
      onPressed: () => _voice(retry: true), child: const Text('إعادة محاولة التفريغ')),
  ]);

  Future<void> _edit({String? focus, MapSearchActions? mapActions}) async {
    if (_journeyEnded || !_journeySession.isCurrentJourney(_journey)) return;
    if (_capture.active) _cancelVoice();
    if (focus == 'map_area') { await _openMap(); return; }
    final owner = _session, journey = _journey, epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final next = await AppBottomSheet.show<Object>(context,
      builder: (sheetContext) => SmartSearchFilterEditor(
        initial: ref.read(smartSearchSessionProvider).filters, focus: focus,
        rangesFirst: mapActions != null,
        extraActions: mapActions == null ? null : Wrap(spacing: 8, children: [
          TextButton.icon(key: const ValueKey('map-filter-draw-area'),
            onPressed: () => Navigator.of(sheetContext).pop(mapActions.onDrawArea),
            icon: const Icon(Icons.gesture_rounded), label: const Text('رسم منطقة')),
          if (mapActions.hasDrawnArea) TextButton(
            onPressed: () => Navigator.of(sheetContext).pop(mapActions.onClearArea),
            child: const Text('إزالة المنطقة المرسومة')),
        ]),
      ));
    if (!mounted || _journeyEnded || journey != _journey || !owner.isCurrentJourney(journey) ||
        epoch != Stage6SecureSessionStore.instance.sessionEpoch || !identical(owner, _session)) {
      return;
    }
    if (next is SmartSearchFilters) unawaited(owner.replaceManually(next));
    if (next is VoidCallback) next();
  }

  Future<void> _openMap() async {
    if (_showingMap || _journeyEnded || !_journeySession.isCurrentJourney(_journey)) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (_capture.active) _cancelVoice();
    _focus.unfocus();
    _session.setDraftText(_description.text);
    // Back consumes the inline map first. Details still own their own route,
    // and MapScreen can cancel an active drawing before this entry is popped.
    final entry = LocalHistoryEntry(onRemove: () {
      _mapHistory = null;
      if (!mounted || _journeyEnded) return;
      if (_capture.active) _cancelVoice();
      _focus.unfocus();
      setState(() => _mapEditorOpen = false);
    });
    setState(() => _mapHistory = entry);
    route.addLocalHistoryEntry(entry);
  }

  void _showList() {
    if (_showEntryMap) {
      if (_capture.active) _cancelVoice();
      _focus.unfocus();
      setState(() {
        _showEntryMap = false;
        _mapEditorOpen = false;
      });
    } else {
      _mapHistory?.remove();
    }
  }

  Future<void> _focusAssistant() async {
    if (!mounted || _journeyEnded || !_journeySession.isCurrentJourney(_journey)) return;
    if (_mapEditorOpen) {
      _focus.requestFocus();
      return;
    }
    setState(() => _mapEditorOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showingMap && _mapEditorOpen) _focus.requestFocus();
    });
  }

  void _closeMapEditor() {
    if (!_mapEditorOpen) return;
    if (_capture.active) _cancelVoice();
    _focus.unfocus();
    setState(() => _mapEditorOpen = false);
  }

  Widget _mapToolbar(SmartSearchState state, String initialHint, MapSearchActions actions) =>
    Column(mainAxisSize: MainAxisSize.min, children: [
      MapDiscoveryToolbar(
        filters: state.filters,
        onBack: () => Navigator.of(context).maybePop(),
        onPurpose: (purpose) => unawaited(_session.replaceManually(
          SmartSearchFilters.fromMap({...state.filters.values, 'purpose': purpose}))),
        onType: (type) {
          final filters = Map<String, dynamic>.of(state.filters.values)
            ..remove('types')
            ..['type'] = type;
          unawaited(_session.replaceManually(SmartSearchFilters.fromMap(filters)));
        },
        onSearch: _focusAssistant,
        onFilters: () => _edit(mapActions: actions),
        extraFilters: actions.hasDrawnArea,
      ),
      if (_mapEditorOpen) Padding(padding: const EdgeInsets.only(top: 7),
        child: _mapEditor(state, initialHint)),
    ]);

  Widget _mapEditor(SmartSearchState state, String initialHint) => Material(elevation:2,borderRadius:BorderRadius.circular(13),
    color:Theme.of(context).colorScheme.surface,child:Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(children:[const SmartSearchRobotIcon(size:24),const SizedBox(width:6), Expanded(child:TextField(
        key:const ValueKey('smart-search-description'),controller:_description,focusNode:_focus,readOnly:_capture.active || state.interpreting,
        minLines:1,maxLines:2,textInputAction:TextInputAction.search,
        onChanged:_session.setDraftText,onSubmitted:(_)=>_send(),
        decoration:InputDecoration(hintText:_capture.active ? null : state.started ? 'أضف أو عدّل أي شرط…' : initialHint,isDense:true,border:InputBorder.none))),
        IconButton(key:const ValueKey('smart-search-voice'),tooltip:'أكمل بحثك بالصوت',onPressed:state.interpreting?null:() => _voice(),icon:const Icon(Icons.mic_none_outlined)),
        IconButton(key:const ValueKey('smart-search-send'),tooltip:'بحث',onPressed:state.interpreting?null:_send,
          icon:state.interpreting?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.search)),
        IconButton(tooltip: 'إغلاق البحث', onPressed: _closeMapEditor, icon: const Icon(Icons.close)),
      ]),
      if(_capture.active) InlineVoiceCapture(capture:_capture,onCancel:_cancelVoice,onRestart:_restartVoice),
      if (!_capture.active && !state.interpreting) _voiceOptions(),
      if(_capture.error!=null || state.aiError!=null) Text(_capture.error ?? state.aiError!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ])));

  @override
  Widget build(BuildContext context) => PopScope(onPopInvokedWithResult: (didPop, _) {
    if (didPop) _endJourney();
  }, child: _contents(context));

  Widget _contents(BuildContext context) {
    if (!_ready) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final state = ref.watch(smartSearchSessionProvider), theme = Theme.of(context);
    final location = ref.watch(homeLocationProvider);
    final regions = ref.watch(homeLocationsProvider).asData?.value ?? const <HomeLocation>[];
    final suggestions = AssistedSearchSuggestions.forLocation(location, regions: regions);
    ref.listen(authControllerProvider, (previous, next) {
      final actor = next.asData?.value?.id, epoch = Stage6SecureSessionStore.instance.sessionEpoch;
      if (_visibleActor != actor || _visibleEpoch != epoch) {
        _visibleActor = actor; _visibleEpoch = epoch;
        _cancelVoice(); _description.clear();
        _lastVoiceBase = null; _lastVoiceText = null;
        if (_journey != 0) _journeySession.endJourney(_journey);
        _journey = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _journeyEnded || actor != ref.read(authControllerProvider).asData?.value?.id ||
              epoch != Stage6SecureSessionStore.instance.sessionEpoch) { return; }
          _journeySession = _session;
          _journey = _journeySession.beginJourney();
        });
      }
    });
    ref.listen<SmartSearchState>(smartSearchSessionProvider, (before, after) {
      if (_journeyEnded) return;
      if (_capture.active && before?.revision != after.revision) _cancelVoice();
      // Applied criteria belong to the summary. Only consume the exact draft
      // that was accepted; manual changes and newer unsent text stay intact.
      if (before != null && before.revision != after.revision &&
          before.draftText.isNotEmpty && after.draftText.isEmpty &&
          _description.text.trim() == before.draftText.trim()) {
        // Keep the accepted text visible. A fresh voice followup starts from
        // an empty draft in _voice(), never replays this accepted sentence.
        _description.text = after.lastRequest;
      }
    });
    if (ModalRoute.of(context)?.isCurrent == false && _capture.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _capture.active) _cancelVoice(); });
    }
    if (_showingMap) {
      final mapOwner = _journeySession, mapJourney = _journey;
      final mapActor = _visibleActor, mapEpoch = _visibleEpoch;
      return Directionality(textDirection:TextDirection.rtl,child:Scaffold(
      body:SafeArea(bottom: false, child: MapScreen(key: ValueKey(('assisted-search-map', mapActor, mapEpoch, mapJourney)),
        sharedSearchJourney:true, toolbarAboveMap:true, collapseResults: true,
        cameraCenterHint: mapSearchInitialCamera(state.filters, location, regions),
        searchToolbarBuilder: (_, actions) => _mapToolbar(state, suggestions.hint, actions),
        onShowList:_showList, onSmartSearch:_focusAssistant,
        onMapInteraction: _closeMapEditor,
        isJourneyCurrent: () => mounted && !_journeyEnded && mapJourney != 0 &&
          _journey == mapJourney && mapOwner.isCurrentJourney(mapJourney) && _visibleActor == mapActor && _visibleEpoch == mapEpoch &&
          identical(mapOwner, _journeySession) && identical(mapOwner, ref.read(smartSearchSessionProvider.notifier)))))); }
    final controller = ref.read(smartSearchSessionProvider.notifier);
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppAppBar(title: 'البحث الذكي', actions: [
        IconButton(key: const ValueKey('smart-search-reset'), tooltip: 'بدء بحث جديد', onPressed: () {
          _cancelVoice(); _capture.clearError(); _description.clear(); controller.reset(useLocation: true);
        }, icon: const Icon(Icons.restart_alt)),
      ]),
      body: SmartSearchAssistantLayer(enabled: state.started && !_capture.active, onOpenMap: _openMap, onPressed: () {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); _focus.requestFocus();
      }, child: SearchResultPagination(
        onLoadMore: state.hasRankedResults && state.canLoadMore ? () => controller.loadNextPage(state) : null,
        child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(18, 12, 18, 110), children: [
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
              hintText: _capture.active ? null : !state.started ? suggestions.hint : 'أكمل بحثك… مثل: خفّض السعر أو أزل شرط الغرف', counterText: '')),
          if (_capture.active) InlineVoiceCapture(capture: _capture, onCancel: _cancelVoice, onRestart: _restartVoice),
          if (!_capture.active && !state.interpreting) _voiceOptions(),
          const SizedBox(height: 8),
          if (!_capture.active && !state.started) const Padding(padding: EdgeInsets.only(bottom: 8),
            child: Text('اكتب طلبك ثم اضغط البحث، أو أمْلِه ليبدأ البحث بعد اكتمال الإملاء.')),
          if (!_capture.active) Row(children: [
            Expanded(child: AppButton(key: const ValueKey('smart-search-send'), label: !state.started ? 'ابحث لي' : 'تحديث',
              icon: Icons.auto_awesome_outlined, loading: state.interpreting,
              onPressed: state.interpreting ? null : _send)),
            const SizedBox(width: 8),
            IconButton.filledTonal(key: const ValueKey('smart-search-voice'), tooltip: 'أكمل بحثك بالصوت',
              onPressed: state.interpreting ? null : () => _voice(),
              icon: const EbrokerIcon(Icons.mic_none_outlined, size: 22)),
          ]),
          if (_capture.error != null || state.aiError != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_capture.error ?? state.aiError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
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
          Wrap(spacing: 8, runSpacing: 6, children: [for (final example in suggestions.examples)
            ActionChip(label: Text(example), onPressed: state.interpreting ? null : () { _description.text = example; _send(); })]),
        ] else ...[
          const SizedBox(height: 28),
          Row(children: [Expanded(child: Text('عقارات تناسب بحثك', style: theme.textTheme.titleMedium)),
            if (state.loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))]),
          const SizedBox(height: 12),
          // Keep successful pages visible during a temporary refresh/load-more
          // failure, and offer retry for precisely the failed page.
          if (state.rows.isNotEmpty &&
              (state.loading || state.resultsError != null) && !controller.isLoadingMore)
            AppRefreshStatus(
              loading: state.loading,
              error: state.resultsError,
              onRetry: controller.retryResults,
            ),
          if (state.loading && state.rows.isEmpty) ...[
            const AppSkeleton(height: 170, radius: 12), const SizedBox(height: 12), const AppSkeleton(height: 170, radius: 12),
          ] else if (state.resultsError != null && state.rows.isEmpty)
            AppErrorState(message: state.resultsError!, onRetry: controller.retryResults)
          else if (state.rows.isEmpty)
            _SmartSearchEmptyState(
              filters: state.filters,
              onRemove: controller.remove,
              onEdit: () => _edit(),
            ),
          for (final row in state.rows)
            Padding(padding: const EdgeInsets.only(bottom: 12),
              child: PropertySummaryCard(key: ValueKey('smart-search-result-${row.id}'), property: row)),
          if (state.rows.isNotEmpty && controller.isLoadingMore &&
              (state.loading || state.resultsError != null))
            AppRefreshStatus(loading: state.loading, error: state.resultsError,
              onRetry: controller.retryResults),
          if (state.more && state.resultsError == null) TextButton(onPressed: state.canLoadMore ? () => controller.loadNextPage(state) : null,
            child: const Text('المزيد من العقارات')),
        ],
      ]))),
    ));
  }
}


class _SmartSearchEmptyState extends StatelessWidget {
  const _SmartSearchEmptyState({
    required this.filters,
    required this.onRemove,
    required this.onEdit,
  });

  final SmartSearchFilters filters;
  final ValueChanged<String> onRemove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final values = filters.values;
    final actions = <({String key, String label})>[
      if (filters.hasMapArea)
        (key: 'map_area', label: 'إزالة نطاق الخريطة'),
      if (values.containsKey('min_price') || values.containsKey('max_price'))
        (key: 'budget', label: 'إزالة حد السعر'),
      if (values.containsKey('type'))
        (key: 'type', label: 'عرض كل أنواع العقارات'),
      if (values.containsKey('search'))
        (key: 'search', label: 'إزالة الموقع أو عبارة البحث'),
      if (values.containsKey('min_bedrooms'))
        (key: 'min_bedrooms', label: 'إزالة شرط غرف النوم'),
      if (values.containsKey('min_bathrooms'))
        (key: 'min_bathrooms', label: 'إزالة شرط دورات المياه'),
    ];

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'لا توجد عقارات بهذه الشروط',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'لن نغيّر بحثك تلقائيًا. اختر تعديلًا واضحًا أدناه أو افتح جميع الشروط.',
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions.take(4))
                  ActionChip(
                    key: ValueKey('zero-results-${action.key}'),
                    label: Text(action.label),
                    onPressed: () => onRemove(action.key),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            key: const ValueKey('zero-results-edit-all'),
            onPressed: onEdit,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('تعديل جميع الشروط'),
          ),
        ],
      ),
    );
  }
}
