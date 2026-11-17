import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/data/property_repository.dart';
import '../domain/smart_search_filters.dart';
import 'ai_repository.dart';
import 'marketplace_repository.dart';
import 'smart_search_session.dart';

SmartSearchSession _results(Ref ref) {
  ref.watch(authControllerProvider.select((value) =>
    (value.asData?.value?.id, Stage6SecureSessionStore.instance.sessionEpoch)));
  return SmartSearchSession(ref.watch(aiRepositoryProvider), ref.watch(propertyRepositoryProvider));
}
final homeSearchResultsProvider = StateNotifierProvider<SmartSearchSession, SmartSearchState>(_results);
final marketplaceMapResultsProvider = StateNotifierProvider<SmartSearchSession, SmartSearchState>(_results);

/// Home owns these fields. The optional map editor is a temporary child copy,
/// never an alternative value for Home's query, criteria, or offline snapshot.
class MarketplaceSearchUi {
  const MarketplaceSearchUi({this.draftQuery = '', this.submittedQuery = '',
    this.criteria = const SmartSearchFilters(), this.active = false,
    this.editing = false, this.mapOpen = false, this.landUse = '', this.mapEditor});
  final String draftQuery, submittedQuery, landUse;
  final SmartSearchFilters criteria;
  final bool active, editing, mapOpen;
  final MarketplaceSearchUi? mapEditor;
  MarketplaceSearchUi copyWith({String? draftQuery, String? submittedQuery,
    SmartSearchFilters? criteria, bool? active, bool? editing, bool? mapOpen, String? landUse,
    MarketplaceSearchUi? mapEditor, bool clearMapEditor = false}) => MarketplaceSearchUi(
      draftQuery: draftQuery ?? this.draftQuery, submittedQuery: submittedQuery ?? this.submittedQuery,
      criteria: criteria ?? this.criteria, active: active ?? this.active,
      editing: editing ?? this.editing, mapOpen: mapOpen ?? this.mapOpen, landUse: landUse ?? this.landUse,
      mapEditor: clearMapEditor ? null : mapEditor ?? this.mapEditor);
}

class MarketplaceSearchController extends StateNotifier<MarketplaceSearchUi> {
  MarketplaceSearchController(this.home, this.map, this.location) : super(const MarketplaceSearchUi());
  final SmartSearchSession home, map;
  final HomeLocation Function() location;
  String _lastSubmit = '', _lastMapSubmit = '';
  bool _mapActive = false;
  int _mapJourney = 0, _mapResultsJourney = 0;
  bool get active => state.active || _mapActive;
  int get mapJourneyToken => _mapJourney;
  bool isMapJourneyCurrent(int token) => mounted && _mapActive && token == _mapJourney;
  MarketplaceSearchUi uiFor({bool onMap = false}) {
    if (!onMap || !_mapActive) return state;
    final editor = state.mapEditor ?? state;
    // A user-drawn/visible map area replaces the inherited province context.
    // Its chips and editor must describe the same scope as the actual request.
    return map.snapshot.filters.hasMapArea &&
            (editor.criteria.values.containsKey('governorate') || editor.criteria.values.containsKey('governorate_code'))
        ? editor.copyWith(criteria: editor.criteria.without('governorate'))
        : editor;
  }

  bool _canEdit(bool onMap) => mounted && (!onMap || _mapActive);
  void _setUi(MarketplaceSearchUi value, {required bool onMap}) {
    if (!_canEdit(onMap)) return;
    state = onMap ? state.copyWith(mapEditor: value) : value;
  }

  Map<String, dynamic> get _homeContext {
    final place = location(), context = place.searchContext;
    return context.isEmpty ? {'governorate': place.governorate ?? place.label} : context;
  }
  SmartSearchFilters _filters({required String text, bool onMap = false}) {
    final editor = uiFor(onMap: onMap);
    final spatial = onMap && map.snapshot.filters.hasMapArea
      ? {for (final e in map.snapshot.filters.values.entries) if (SmartSearchFilters.mapFields.contains(e.key)) e.key: e.value}
      : onMap && map.snapshot.filters.values.keys.any((key) => const ['governorate', 'governorate_code'].contains(key))
        ? {for (final e in map.snapshot.filters.values.entries) if (const ['governorate', 'governorate_code'].contains(e.key)) e.key: e.value}
        : _homeContext;
    final criteria = Map<String, dynamic>.from(editor.criteria.values);
    if (onMap && map.snapshot.filters.hasMapArea) {
      criteria.remove('governorate'); criteria.remove('governorate_code');
    }
    return SmartSearchFilters.fromMap({...spatial, ...criteria,
      if (text.trim().isNotEmpty || editor.landUse.isNotEmpty)
        'search': [text.trim(), editor.landUse].where((s) => s.isNotEmpty).join(' ')});
  }
  SmartSearchFilters suggestionFilters({bool onMap = false}) => _filters(text: uiFor(onMap: onMap).draftQuery, onMap: onMap);
  void restoreOfflineHomeCriteria(SmartSearchFilters filters) {
    if (state.active || state.criteria.values.isNotEmpty) return;
    final values = Map<String, dynamic>.from(filters.values)
      ..removeWhere((key, _) => SmartSearchFilters.mapFields.contains(key) ||
          const ['governorate', 'governorate_code', 'search'].contains(key));
    state = state.copyWith(criteria: SmartSearchFilters.fromMap(values));
  }

  Future<void> restoreOfflineSession(Map<String, dynamic> saved,
      {bool Function()? current}) async {
    if (state.active || state.draftQuery.isNotEmpty || home.snapshot.started || current?.call() == false) return;
    final criteria = SmartSearchFilters.fromMap(Map<String, dynamic>.from(saved['criteria'] as Map? ?? const {}));
    state = MarketplaceSearchUi(criteria: criteria, active: saved['active'] == true,
      submittedQuery: saved['submitted']?.toString() ?? '', draftQuery: saved['draft']?.toString() ?? '',
      landUse: saved['land_use']?.toString() ?? '', mapOpen: state.mapOpen, mapEditor: state.mapEditor);
    final raw = saved['home_filters'];
    if (raw is! Map || saved['home_started'] != true || current?.call() == false) return;
    final filters = SmartSearchFilters.fromMap(Map<String, dynamic>.from(raw));
    await home.replaceManually(filters);
    if (!mounted || current?.call() == false || !home.mounted) return;
    final pages = (saved['home_pages'] as num? ?? 1).toInt().clamp(1, 8);
    for (var page = 1; page < pages && current?.call() != false && home.mounted &&
        home.snapshot.more && home.snapshot.resultsError == null && home.snapshot.filters.sameAs(filters); page++) {
      await home.search(more: true);
    }
    if (mounted && current?.call() != false && home.mounted && home.snapshot.started && home.snapshot.resultsError == null) {
      _lastSubmit = home.snapshot.filters.signature;
    }
    // Historical map checkpoints remain cached data, not a resumed temporary
    // editor. A new map entry always copies the current parent Home criteria.
  }

  void locationChanged() {
    final next = Map<String, dynamic>.from(state.criteria.values)..remove('governorate')..remove('governorate_code');
    state = state.copyWith(criteria: SmartSearchFilters.fromMap(next));
    _lastSubmit = '';
    if (state.active || home.snapshot.started) unawaited(submit(force: true));
  }
  void begin({bool onMap = false}) {
    if (_canEdit(onMap)) _setUi(uiFor(onMap: onMap).copyWith(active: true, editing: true), onMap: onMap);
  }
  void edit(String text, {bool onMap = false}) {
    if (_canEdit(onMap)) _setUi(uiFor(onMap: onMap).copyWith(draftQuery: text, active: true, editing: true), onMap: onMap);
  }
  void stopEditing({bool onMap = false}) {
    if (_canEdit(onMap)) _setUi(uiFor(onMap: onMap).copyWith(editing: false), onMap: onMap);
  }
  void leaveHomeSearch() { if (mounted) state = state.copyWith(active: false, editing: false); }

  void prepareSearch({String? type}) {
    if (type == null) {
      state = state.copyWith(active: true, editing: state.draftQuery.trim() != state.submittedQuery);
      return;
    }
    final changed = state.criteria.values['type'] != type || state.criteria.values.containsKey('types');
    final next = Map<String, dynamic>.from(state.criteria.values)..remove('type')..remove('types');
    next['type'] = type;
    state = state.copyWith(active: true, criteria: SmartSearchFilters.fromMap(next),
      editing: state.draftQuery.trim() != state.submittedQuery);
    if (changed) { _lastSubmit = ''; home.reset(); }
  }

  void choosePurpose(String? purpose, {bool onMap = false}) {
    if (!_canEdit(onMap) || (purpose != null && !const ['rent', 'sale'].contains(purpose))) return;
    final editor = uiFor(onMap: onMap);
    if (editor.criteria.values['purpose'] == purpose) return;
    final next = Map<String, dynamic>.from(editor.criteria.values)..remove('purpose');
    if (purpose != null) next['purpose'] = purpose;
    _chooseScope(SmartSearchFilters.fromMap(next), onMap: onMap);
  }
  void chooseType(String type, {bool onMap = false}) {
    if (_canEdit(onMap)) _chooseScope(uiFor(onMap: onMap).criteria.toggleType(type), onMap: onMap);
  }
  void _chooseScope(SmartSearchFilters filters, {bool onMap = false}) {
    if (!_canEdit(onMap)) return;
    final editor = uiFor(onMap: onMap);
    if (filters.sameAs(editor.criteria)) return;
    _setUi(editor.copyWith(criteria: filters, landUse: filters.values['type'] == 'land' ? editor.landUse : ''), onMap: onMap);
    if (onMap) {
      _lastMapSubmit = '';
      unawaited(submit(force: true, onMap: true));
    } else {
      _lastSubmit = '';
      if (home.snapshot.started) {
        final next = _filters(text: state.submittedQuery);
        _lastSubmit = next.signature;
        unawaited(home.replaceManually(next));
      }
    }
  }

  Future<void> submit({bool force = false, bool onMap = false}) async {
    if (!_canEdit(onMap)) return;
    final editor = uiFor(onMap: onMap), session = onMap ? map : home;
    if (editor.draftQuery.trim().length > 120) return;
    final filters = _filters(text: editor.draftQuery, onMap: onMap);
    if ((filters.values['search']?.toString().length ?? 0) > 120) return;
    final key = filters.signature, previous = onMap ? _lastMapSubmit : _lastSubmit;
    _setUi(editor.copyWith(active: true, editing: false, submittedQuery: editor.draftQuery.trim()), onMap: onMap);
    if (!force && key == previous && session.snapshot.started && session.snapshot.resultsError == null) return;
    if (onMap) { _lastMapSubmit = key; } else { _lastSubmit = key; }
    await session.replaceManually(filters,
      retainedRows: session.snapshot.filters.sameAs(filters) ? session.snapshot.rows : const []);
  }
  void setChoice(String key, Object? value, {bool onMap = false}) {
    if (!_canEdit(onMap)) return;
    final next = Map<String, dynamic>.from(uiFor(onMap: onMap).criteria.values);
    if (key == 'type') next.remove('types');
    if (value == null || next[key] == value) { next.remove(key); } else { next[key] = value; }
    applyFilters(SmartSearchFilters.fromMap(next), onMap: onMap);
  }
  void toggleType(String type, {bool onMap = false}) {
    if (_canEdit(onMap)) applyFilters(uiFor(onMap: onMap).criteria.toggleType(type), onMap: onMap);
  }
  void applyFilters(SmartSearchFilters filters, {bool onMap = false}) {
    if (!_canEdit(onMap)) return;
    final editor = uiFor(onMap: onMap);
    final next = Map<String, dynamic>.from(filters.values)
      ..removeWhere((key, _) => SmartSearchFilters.mapFields.contains(key) || key == 'search' ||
          (!onMap && const ['governorate', 'governorate_code'].contains(key)));
    _setUi(editor.copyWith(criteria: SmartSearchFilters.fromMap(next),
      landUse: next['type'] == 'land' ? editor.landUse : ''), onMap: onMap);
    unawaited(submit(force: true, onMap: onMap));
  }
  void remove(String key, {bool onMap = false}) {
    if (!_canEdit(onMap)) return;
    if (key == 'land_use') { setLandUse('', onMap: onMap); return; }
    if (onMap && key == 'map_area') { map.remove(key); return; }
    applyFilters(uiFor(onMap: onMap).criteria.without(key), onMap: onMap);
  }

  /// Explicit map-only adoption retained for callers that own that child scope.
  /// Popping an AI route must never call this method to update its parent.
  void adoptMapSearch(SmartSearchFilters filters, {bool applyMap = true}) {
    if (!_canEdit(true)) return;
    final next = Map<String, dynamic>.from(filters.values)
      ..removeWhere((key, _) => SmartSearchFilters.mapFields.contains(key) || key == 'search');
    final text = filters.values['search']?.toString().trim() ?? '';
    _setUi(uiFor(onMap: true).copyWith(criteria: SmartSearchFilters.fromMap(next), draftQuery: text,
      submittedQuery: text, landUse: '', active: true, editing: false), onMap: true);
    _lastMapSubmit = filters.signature;
    if (applyMap && (!map.snapshot.started || map.snapshot.resultsError != null || !map.snapshot.filters.sameAs(filters))) {
      unawaited(map.replaceManually(filters));
    }
  }
  void setLandUse(String text, {bool onMap = false}) {
    if (!_canEdit(onMap)) return;
    final editor = uiFor(onMap: onMap);
    _setUi(editor.copyWith(landUse: editor.criteria.values['type'] == 'land' ? text.trim() : ''), onMap: onMap);
    unawaited(submit(force: true, onMap: onMap));
  }

  int enterMap({SmartSearchFilters? filters}) {
    if (!mounted) return 0;
    if (_mapActive) return _mapJourney;
    _mapActive = true;
    final token = ++_mapJourney;
    final initial = filters == null ? _filters(text: state.draftQuery)
      : SmartSearchFilters.fromMap(Map<String, dynamic>.from(filters.values));
    final editor = filters == null
      ? MarketplaceSearchUi(draftQuery: state.draftQuery, submittedQuery: state.draftQuery.trim(),
          criteria: state.criteria, landUse: state.landUse, active: true)
      : MarketplaceSearchUi(draftQuery: initial.values['search']?.toString() ?? '',
          submittedQuery: initial.values['search']?.toString() ?? '', active: true,
          criteria: SmartSearchFilters.fromMap(Map<String, dynamic>.from(initial.values)
            ..removeWhere((key, _) => SmartSearchFilters.mapFields.contains(key) || key == 'search')));
    state = state.copyWith(mapOpen: true, mapEditor: editor);
    _lastMapSubmit = initial.signature;
    _mapResultsJourney = map.beginJourney(entryFilters: initial);
    return token;
  }
  void leaveMap([int? token]) {
    if (!mounted || !_mapActive || (token != null && token != _mapJourney)) return;
    final ended = _mapJourney;
    _mapActive = false;
    _lastMapSubmit = '';
    map.endJourney(_mapResultsJourney);
    // Widget disposal cannot mutate provider state during the framework's
    // unmount. Invalidate transfers immediately, publish the UI reset safely.
    scheduleMicrotask(() {
      if (mounted && !_mapActive && ended == _mapJourney) state = state.copyWith(mapOpen: false, clearMapEditor: true);
    });
  }
  Future<void> refresh({bool onMap = false}) {
    if (!_canEdit(onMap)) return Future.value();
    return onMap ? map.search() : home.search();
  }
  Future<void> refreshActiveScopes() async {
    if (!mounted) return;
    final work = <Future<void>>[];
    if (state.active || home.snapshot.started) work.add(home.search());
    if (_mapActive) work.add(map.search());
    await Future.wait(work);
  }
  @override
  void dispose() {
    if (_mapActive) map.endJourney(_mapResultsJourney);
    _mapActive = false;
    super.dispose();
  }
}

final marketplaceSearchControllerProvider = StateNotifierProvider<MarketplaceSearchController, MarketplaceSearchUi>((ref) {
  final controller = MarketplaceSearchController(ref.watch(homeSearchResultsProvider.notifier),
    ref.watch(marketplaceMapResultsProvider.notifier), () => ref.read(homeLocationProvider));
  ref.listen(propertyDataRevisionProvider, (_, __) {
    if (controller.active) unawaited(controller.refreshActiveScopes());
  });
  return controller;
});
