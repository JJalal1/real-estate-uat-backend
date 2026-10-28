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

  Future<void> submit({bool force = false}) async {
    if (!mounted || state.draftQuery.trim().length > 120) return;
    final filters = _filters(text: state.draftQuery);
    if ((filters.values['search']?.toString().length ?? 0) > 120) return;
    final key = jsonEncode(filters.apiFilters);
    state = state.copyWith(active: true, editing: false, submittedQuery: state.draftQuery.trim());
    if (!force && key == _lastSubmit && home.snapshot.started && home.snapshot.resultsError == null) return;
    _lastSubmit = key;
    final loading = home.replaceManually(filters, retainedRows: home.snapshot.rows);
    if (state.mapOpen) {
      unawaited(map.replaceManually(_filters(text: state.submittedQuery, onMap: true), retainedRows: map.snapshot.rows));
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
    final filters = _filters(text: state.draftQuery);
    state = state.copyWith(submittedQuery: state.draftQuery.trim());
    if (!home.snapshot.started) unawaited(home.replaceManually(filters));
    unawaited(map.replaceManually(filters, retainedRows: home.snapshot.rows));
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
