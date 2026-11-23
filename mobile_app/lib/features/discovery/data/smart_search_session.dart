import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/platform/uat_network_trace.dart';
import '../../account/data/auth_controller.dart';
import '../../properties/data/property_repository.dart';
import '../../map/domain/map_area_geometry.dart';
import '../../properties/domain/property_details.dart';
import '../domain/smart_search_filters.dart';
import 'ai_repository.dart';
import 'marketplace_repository.dart';

class SmartSearchState {
  const SmartSearchState({this.filters = const SmartSearchFilters(), this.rows = const [], this.revision = 0,
    this.page = 0, this.total, this.more = false, this.interpreting = false, this.loading = false, this.started = false,
    this.message = '', this.lastRequest = '', this.draftText = '', this.aiError, this.resultsError});
  final SmartSearchFilters filters;
  final List<PropertySummary> rows;
  final int revision, page;
  final int? total;
  final bool more, interpreting, loading, started;
  final String message, lastRequest, draftText;
  final String? aiError, resultsError;
  bool get canLoadMore => more && !loading && resultsError == null;
  bool get hasRankedResults => rows.isNotEmpty && rows.first.discoveryMatch != null;

  SmartSearchState copyWith({SmartSearchFilters? filters, List<PropertySummary>? rows, int? revision, int? page, int? total,
    bool? more, bool? interpreting, bool? loading, bool? started, String? message, String? lastRequest, String? draftText, String? aiError,
    String? resultsError, bool clearAiError = false, bool clearResultsError = false}) => SmartSearchState(
      filters: filters ?? this.filters, rows: rows ?? this.rows, revision: revision ?? this.revision,
      page: page ?? this.page, total: total ?? this.total, more: more ?? this.more, interpreting: interpreting ?? this.interpreting,
      loading: loading ?? this.loading, started: started ?? this.started, message: message ?? this.message, lastRequest: lastRequest ?? this.lastRequest, draftText: draftText ?? this.draftText,
      aiError: clearAiError ? null : aiError ?? this.aiError,
      resultsError: clearResultsError ? null : resultsError ?? this.resultsError);
}

class SmartSearchSession extends StateNotifier<SmartSearchState> {
  SmartSearchSession(this._ai, this._properties, {this.defaultLocation,
    this.traceMapResults = false, this.retainMapRowsOnUnknownFailure = false})
    : super(const SmartSearchState());
  final AiRepository _ai;
  final PropertyRepository _properties;
  SmartSearchState get snapshot => state;
  final SmartSearchFilters Function()? defaultLocation;
  final bool traceMapResults;
  final bool retainMapRowsOnUnknownFailure;
  Map<String, dynamic> _defaultContext = {};
  static const _mapViewportFields = {'south', 'west', 'north', 'east'};
  static const _drawnAreaLocationFields = {
    ...SmartSearchFilters.mapFields, 'governorate', 'governorate_code',
  };
  Map<String, dynamic>? _locationBeforeDrawing;
  bool _usingDefaultLocation = false;
  int _inference = 0, _results = 0;
  CancelToken? _resultTransfer;
  UatMapRequestTiming? get resultTiming => UatMapRequestTiming.of(_resultTransfer);
  bool _failedMore = false;
  bool get isLoadingMore => _failedMore;

  int _journey = 0;
  bool _journeyActive = false;
  bool isCurrentJourney(int token) => mounted && _journeyActive && token == _journey;
  int beginJourney({SmartSearchFilters? savedFilters, SmartSearchFilters? entryFilters,
    SmartSearchState? initialResults}) {
    final token = ++_journey;
    _journeyActive = true;
    reset(useLocation: true);
    final filters = savedFilters ?? entryFilters;
    if (filters == null) return token;
    if (initialResults != null && initialResults.started && !initialResults.loading &&
        initialResults.resultsError == null && initialResults.page > 0 && initialResults.filters.sameAs(filters)) {
      _usingDefaultLocation = false;
      state = SmartSearchState(filters: filters, rows: _insideDrawnArea(filters, initialResults.rows), page: initialResults.page,
        more: initialResults.more, total: initialResults.total, started: true, revision: state.revision);
    } else {
      replaceManually(filters);
    }
    return token;
  }
  void endJourney(int token) {
    if (!isCurrentJourney(token)) return;
    _journeyActive = false;
    // Route pop precedes Widget disposal and its transition animation. Reject
    // deliveries now; defer only the observable state reset to a safe frame.
    _inference++; _results++;
    _resultTransfer?.cancel('Search journey ended');
    scheduleMicrotask(() { if (mounted && token == _journey) reset(); });
  }
  void setDraftText(String value) {
    if (value == state.draftText) return;
    if (state.interpreting) _inference++;
    state = state.copyWith(draftText: value, interpreting: false);
  }
  void startFromHome({required String location, String? type}) => reset();

  Future<void> applyDrawnArea(String encodedRing) {
    final current = state.filters.values;
    final hasViewport = _mapViewportFields.every((key) => current[key] is num);
    _locationBeforeDrawing ??= {
      for (final entry in current.entries)
        if (entry.key != 'area_polygon' && _drawnAreaLocationFields.contains(entry.key))
          entry.key: entry.value,
    };
    // The polygon already supplies the exact limits. Keep only a viewport
    // the user had applied, so clearing the drawing can restore the prior scope.
    final values = Map<String, dynamic>.from(current)
      ..removeWhere((key, _) => _drawnAreaLocationFields.contains(key) &&
        !(hasViewport && _mapViewportFields.contains(key)))
      ..['area_polygon'] = encodedRing;
    return replaceManually(SmartSearchFilters.fromMap(values), retainedRows: state.rows);
  }

  Future<void> clearDrawnArea() {
    final values = Map<String, dynamic>.from(state.filters.values);
    if (values.remove('area_polygon') == null) return Future.value();
    final location = _locationBeforeDrawing;
    final hasOtherLocation = values.keys.any((key) =>
      _drawnAreaLocationFields.contains(key) && !_mapViewportFields.contains(key));
    if (location != null && !hasOtherLocation &&
        _mapViewportFields.every((key) => values[key] == location[key])) {
      values.addAll(location);
    }
    return replaceManually(SmartSearchFilters.fromMap(values));
  }

  void updateViewport({required double south, required double west, required double north, required double east}) {
    if (![south, west, north, east].every((value) => value.isFinite) || south >= north ||
      south < -90 || north > 90 || west < -180 || east > 180) { return; }
    final values = Map<String,dynamic>.from(state.filters.values)..remove('latitude')..remove('longitude')..remove('radius_km')..remove('governorate')..remove('governorate_code');
    values.addAll({'south':south,'west':west,'north':north,'east':east});
    final next = SmartSearchFilters.fromMap(values);
    if (next.sameAs(state.filters)) return;
    final retained = state.rows.where((row) => row.latitude >= south && row.latitude <= north &&
      (west <= east ? row.longitude >= west && row.longitude <= east : row.longitude >= west || row.longitude <= east)).toList(growable: false);
    _usingDefaultLocation = false;
    _replace(next, retainedRows: retained);
    unawaited(search());
  }

  Future<void> interpret(String message) async {
    if (!mounted) return;
    final text = message.trim();
    if (text.isEmpty || text.length > 5000) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final request = ++_inference, revision = state.revision;
    final filters = state.filters;
    state = state.copyWith(interpreting: true, clearAiError: true, lastRequest: text);
    try {
      // A default city is a starting point, not an explicit map constraint.
      // Let a city stated in the request override it; retain user-chosen bounds.
      final input = Map<String, dynamic>.from(filters.values);
      if (_usingDefaultLocation) { for (final key in _defaultContext.keys) { input.remove(key); } }
      final result = await _ai.refine(text, input, revision);
      if (!_acceptInferenceDelivery(request, revision, epoch)) return;
      if (result['revision'] != revision || result['filters'] is! Map) throw StateError('Invalid search session response.');
      final values = Map<String, dynamic>.from(result['filters'] as Map);
      final explicitLocation = values.containsKey('governorate') ||
        (values['search'] is String && (values['search'] as String).trim().isNotEmpty) || SmartSearchFilters.mapFields.any(values.containsKey);
      if (_usingDefaultLocation && !explicitLocation) values.addAll(_defaultContext);
      if (explicitLocation) _usingDefaultLocation = false;
      final next = SmartSearchFilters.fromMap(values);
      _replace(next, message: result['message']?.toString() ?? 'حدّثنا شروط بحثك.',
        draftText: state.draftText.trim() == text ? '' : null);
      await search();
    } catch (error) {
      if (_acceptInferenceDelivery(request, revision, epoch)) state = state.copyWith(interpreting: false, aiError: friendlyApiError(error));
    }
  }

  bool _acceptInferenceDelivery(int request, int revision, int epoch) {
    if (!mounted || request != _inference || revision != state.revision) return false;
    if (epoch == Stage6SecureSessionStore.instance.sessionEpoch) return true;
    // A failed/cancelled login can advance the secure epoch without changing
    // the visible actor. Discard the old payload, but leave that UI retryable.
    state = state.copyWith(interpreting: false);
    return false;
  }

  List<PropertySummary> _insideDrawnArea(SmartSearchFilters filters, List<PropertySummary> rows) {
    final ring = filters.values['area_polygon'];
    if (ring is! String || rows.isEmpty) return rows;
    try {
      final polygon = MapAreaGeometry.fromEncodedRing(ring);
      return rows.where((row) => polygon.contains(row.latitude, row.longitude)).toList(growable: false);
    } on FormatException {
      // Discard out-of-scope cached results while the API validates the ring.
      return const [];
    }
  }

  void _replace(SmartSearchFilters filters, {String message = 'حدّثنا شروطك. النتائج حسب الاختيارات الحالية.', String? draftText,
    List<PropertySummary> retainedRows = const []}) {
    _inference++; _results++;
    _resultTransfer?.cancel('Search criteria changed');
    if (!filters.values.containsKey('area_polygon')) _locationBeforeDrawing = null;
    state = SmartSearchState(filters: filters, rows: _insideDrawnArea(filters, retainedRows), revision: state.revision + 1,
      message: message, lastRequest: state.lastRequest, draftText: draftText ?? state.draftText);
  }

  Future<void> replaceManually(SmartSearchFilters filters, {List<PropertySummary> retainedRows = const []}) {
    _usingDefaultLocation = false;
    _replace(filters, retainedRows: retainedRows);
    return search();
  }

  void remove(String key) => replaceManually(state.filters.without(key));

  void reset({bool useLocation = false}) {
    _inference++; _results++;
    _resultTransfer?.cancel('Search journey ended');
    _resultTransfer = null;
    _locationBeforeDrawing = null;
    _defaultContext = useLocation ? Map.of(defaultLocation?.call().values ?? const <String,dynamic>{}) : {};
    _usingDefaultLocation = _defaultContext.isNotEmpty;
    state = SmartSearchState(revision: state.revision + 1, filters: SmartSearchFilters.fromMap(_defaultContext));
  }

  Future<void> search({bool more = false}) async {
    if (!mounted) return;
    if (more && (state.loading || !state.more)) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final request = ++_results, revision = state.revision;
    final page = more ? state.page + 1 : 1;
    final filters = state.filters;
    _resultTransfer?.cancel('Search superseded');
    final transfer = _resultTransfer = CancelToken();
    final timing = traceMapResults ? UatMapRequestTiming.start(transfer, page) : null;
    _failedMore = more;
    state = state.copyWith(loading: true, started: true, clearResultsError: true);
    try {
      final result = await _properties.searchListings(filters.apiFilters, page: page, cancelToken: transfer, refresh: !more && state.page > 0);
      if (!_acceptResultsDelivery(request, revision, epoch)) return;
      final rows = more ? List<PropertySummary>.of(state.rows) : <PropertySummary>[];
      // Keep the server's order across pages regardless of classification.
      final ids = rows.map((row) => row.id).toSet();
      final pageRows = result.$1;
      final inside = _insideDrawnArea(filters, pageRows);
      rows.addAll(inside.where((row) => ids.add(row.id)));
      final total = !result.$2 ? rows.length
        : inside.length == pageRows.length && pageRows is PropertySearchPageRows ? pageRows.total : rows.length;
      state = state.copyWith(rows: List.unmodifiable(rows), page: page, total: total, more: result.$2, loading: false);
      timing?.mark(UatMapPhase.resultsApplied);
    } catch (error) {
      if (_acceptResultsDelivery(request, revision, epoch)) {
        // A public map can keep the rows already restricted to the current
        // viewport when Dio fails before producing a response.
        final retainRows = isTransientApiFailure(error) ||
            (retainMapRowsOnUnknownFailure && error is DioException &&
              error.type == DioExceptionType.unknown && error.response == null);
        state = state.copyWith(loading: false, rows: retainRows ? null : const [], total: retainRows ? state.total : 0,
          resultsError: friendlyApiError(error));
        timing?.mark(UatMapPhase.resultsFailed);
      }
    }
  }

  bool _acceptResultsDelivery(int request, int revision, int epoch) {
    if (!mounted || request != _results || revision != state.revision) return false;
    if (epoch == Stage6SecureSessionStore.instance.sessionEpoch) return true;
    // Only this obsolete operation may finish its busy state. A newer request
    // has a different request/revision and must keep its loading indicator.
    state = state.copyWith(loading: false);
    return false;
  }

  Future<void> loadNextPage(SmartSearchState expected) async {
    if (!mounted || !state.canLoadMore || state.revision != expected.revision || state.page != expected.page) return;
    await search(more: true);
  }

  Future<void> retryResults() => state.loading ? Future.value() : search(more: _failedMore);

  @override
  void dispose() { _inference++; _results++; _resultTransfer?.cancel('Search disposed'); super.dispose(); }
}

// One owner route controls a journey. List/map share it; full exit invalidates it.
final smartSearchSessionProvider = StateNotifierProvider<SmartSearchSession, SmartSearchState>((ref) {
  // A renewed login is a different session even when it belongs to the same
  // actor. A metadata refresh within that session keeps the current search.
  ref.watch(authControllerProvider.select((value) =>
    (value.asData?.value?.id, Stage6SecureSessionStore.instance.sessionEpoch)));
  return SmartSearchSession(ref.watch(aiRepositoryProvider), ref.watch(propertyRepositoryProvider),
    defaultLocation: () => SmartSearchFilters.fromMap(ref.read(homeLocationProvider).searchContext));
});
