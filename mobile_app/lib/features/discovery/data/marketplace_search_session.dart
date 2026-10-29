import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/data/property_repository.dart';
import '../domain/smart_search_filters.dart';
import 'ai_repository.dart';
import 'marketplace_repository.dart';
import 'smart_search_session.dart';

// Reuse the existing public results engine, cancellation, paging and retry.
// Home and the visible map have separate spatial snapshots, with one editor.
SmartSearchSession _results(Ref ref) {
  ref.watch(authControllerProvider.select((value) => value.asData?.value?.id));
  return SmartSearchSession(ref.watch(aiRepositoryProvider), ref.watch(propertyRepositoryProvider));
}
final homeSearchResultsProvider = StateNotifierProvider<SmartSearchSession, SmartSearchState>(_results);
final marketplaceMapResultsProvider = StateNotifierProvider<SmartSearchSession, SmartSearchState>(_results);

class MarketplaceSearchUi {
  const MarketplaceSearchUi({this.draftQuery = '', this.submittedQuery = '',
    this.criteria = const SmartSearchFilters(), this.active = false,
    this.editing = false, this.mapOpen = false, this.landUse = ''});
  final String draftQuery, submittedQuery, landUse;
  final SmartSearchFilters criteria;
  final bool active, editing, mapOpen;
  MarketplaceSearchUi copyWith({String? draftQuery, String? submittedQuery,
    SmartSearchFilters? criteria, bool? active, bool? editing, bool? mapOpen, String? landUse}) => MarketplaceSearchUi(
      draftQuery: draftQuery ?? this.draftQuery, submittedQuery: submittedQuery ?? this.submittedQuery,
      criteria: criteria ?? this.criteria, active: active ?? this.active,
      editing: editing ?? this.editing, mapOpen: mapOpen ?? this.mapOpen, landUse: landUse ?? this.landUse);
}

class MarketplaceSearchController extends StateNotifier<MarketplaceSearchUi> {
  MarketplaceSearchController(this.home, this.map, this.location) : super(const MarketplaceSearchUi());
  final SmartSearchSession home, map;
  final HomeLocation Function() location;
  String _lastSubmit = '';
  bool get active => state.active;

  Map<String, dynamic> get _homeContext {
    final place = location(), context = place.searchContext;
    return context.isEmpty ? {'governorate': place.governorate ?? place.label} : context;
  }
  SmartSearchFilters _filters({required String text, bool onMap = false}) {
    final spatial = onMap && map.snapshot.filters.hasMapArea
      ? {for (final e in map.snapshot.filters.values.entries) if (SmartSearchFilters.mapFields.contains(e.key)) e.key: e.value}
      : _homeContext;
    return SmartSearchFilters.fromMap({...spatial, ...state.criteria.values,
      if (text.trim().isNotEmpty || state.landUse.isNotEmpty)
        'search': [text.trim(), state.landUse].where((s) => s.isNotEmpty).join(' ')});
  }
  SmartSearchFilters suggestionFilters({bool onMap = false}) => _filters(text: state.draftQuery, onMap: onMap);
  void begin() => state = state.copyWith(active: true, editing: true);
  void edit(String text) => state = state.copyWith(draftQuery: text, active: true, editing: true);
  void stopEditing() => state = state.copyWith(editing: false);
  void leaveHomeSearch() => state = state.copyWith(active: false, editing: false);

  void prepareSearch({String? type}) {
    final next = Map<String, dynamic>.from(state.criteria.values)..remove('type');
    if (type != null) next['type'] = type;
    state = state.copyWith(active: true, criteria: SmartSearchFilters.fromMap(next),
      editing: state.draftQuery.trim() != state.submittedQuery);
  }

  /// One explicit session choice supplies Home, suggestions, list and map.
  /// No new-user default or cross-account/device preference is invented.
  void choosePurpose(String? purpose) {
    if (purpose != null && !const ['rent', 'sale'].contains(purpose)) return;
    if (state.criteria.values['purpose'] == purpose) return;
    final next = Map<String, dynamic>.from(state.criteria.values)..remove('purpose');
    if (purpose != null) next['purpose'] = purpose;
    state = state.copyWith(criteria: SmartSearchFilters.fromMap(next));
    _lastSubmit = '';
    if (home.snapshot.started) {
      unawaited(home.replaceManually(_filters(text: state.submittedQuery)));
    }
    if (state.mapOpen) {
      unawaited(map.replaceManually(_filters(text: state.submittedQuery, onMap: true)));
    }
  }

  bool _sameFilters(SmartSearchFilters a, SmartSearchFilters b) =>
    a.apiFilters.length == b.apiFilters.length &&
    a.apiFilters.entries.every((entry) => b.apiFilters[entry.key] == entry.value);

  Future<void> submit({bool force = false}) async {
    if (!mounted || state.draftQuery.trim().length > 120) return;
    final filters = _filters(text: state.draftQuery);
    if ((filters.values['search']?.toString().length ?? 0) > 120) return;
    final key = jsonEncode(filters.apiFilters);
    state = state.copyWith(active: true, editing: false, submittedQuery: state.draftQuery.trim());
    if (!force && key == _lastSubmit && home.snapshot.started && home.snapshot.resultsError == null) return;
    _lastSubmit = key;
    final loading = home.replaceManually(filters,
      retainedRows: _sameFilters(home.snapshot.filters, filters) ? home.snapshot.rows : const []);
    if (state.mapOpen) {
      final mapFilters = _filters(text: state.submittedQuery, onMap: true);
      unawaited(map.replaceManually(mapFilters,
        retainedRows: _sameFilters(map.snapshot.filters, mapFilters) ? map.snapshot.rows : const []));
    }
    await loading;
  }
  void setChoice(String key, Object? value) {
    final next = Map<String, dynamic>.from(state.criteria.values);
    if (value == null || next[key] == value) { next.remove(key); } else { next[key] = value; }
    applyFilters(SmartSearchFilters.fromMap(next));
  }
  void applyFilters(SmartSearchFilters filters) {
    final next = Map<String, dynamic>.from(filters.values)
      ..removeWhere((key, _) => SmartSearchFilters.mapFields.contains(key) || const ['governorate', 'search'].contains(key));
    state = state.copyWith(criteria: SmartSearchFilters.fromMap(next),
      landUse: next['type'] == 'land' ? state.landUse : '');
    unawaited(submit(force: true));
  }
  void remove(String key) {
    if (key == 'land_use') { setLandUse(''); return; }
    applyFilters(state.criteria.without(key));
  }
  void setLandUse(String text) {
    // Existing listings have free-text declared use, not a legal classification
    // column. A visible keyword criterion uses the same canonical public search.
    state = state.copyWith(landUse: state.criteria.values['type'] == 'land' ? text.trim() : '');
    unawaited(submit(force: true));
  }
  void enterMap() {
    state = state.copyWith(mapOpen: true, active: true, editing: false);
    // Opening the map applies the current editor through the same guarded
    // submit path, including Home results previously loaded for another text.
    unawaited(submit());
    final filters = _filters(text: state.submittedQuery, onMap: true);
    final previous = map.snapshot.filters.apiFilters, next = filters.apiFilters;
    if (!map.snapshot.started || map.snapshot.resultsError != null || previous.length != next.length ||
        next.entries.any((entry) => previous[entry.key] != entry.value)) {
      // A repeated entry preserves the map's independent viewport and rows.
      // submit() may already have started this exact request synchronously.
      unawaited(map.replaceManually(filters,
        retainedRows: _sameFilters(home.snapshot.filters, filters) ? home.snapshot.rows : const []));
    }
  }
  void leaveMap() { if (mounted) state = state.copyWith(mapOpen: false, editing: false); }
  Future<void> refresh() {
    if (state.mapOpen) unawaited(map.search());
    return home.search();
  }
}

final marketplaceSearchControllerProvider = StateNotifierProvider<MarketplaceSearchController, MarketplaceSearchUi>((ref) {
  final controller = MarketplaceSearchController(ref.watch(homeSearchResultsProvider.notifier),
    ref.watch(marketplaceMapResultsProvider.notifier), () => ref.read(homeLocationProvider));
  ref.listen(propertyDataRevisionProvider, (_, __) {
    if (controller.active) unawaited(controller.refresh());
  });
  return controller;
});
