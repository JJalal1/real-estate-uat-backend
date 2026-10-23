import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../properties/data/property_repository.dart';
import '../../properties/domain/property_details.dart';
import '../domain/smart_search_filters.dart';
import 'ai_repository.dart';
import 'marketplace_repository.dart';

class SmartSearchState {
  const SmartSearchState({this.filters = const SmartSearchFilters(), this.rows = const [], this.revision = 0,
    this.page = 0, this.more = false, this.interpreting = false, this.loading = false, this.started = false,
    this.message = '', this.lastRequest = '', this.draftText = '', this.aiError, this.resultsError});
  final SmartSearchFilters filters;
  final List<PropertySummary> rows;
  final int revision, page;
  final bool more, interpreting, loading, started;
  final String message, lastRequest, draftText;
  final String? aiError, resultsError;

  SmartSearchState copyWith({SmartSearchFilters? filters, List<PropertySummary>? rows, int? revision, int? page,
    bool? more, bool? interpreting, bool? loading, bool? started, String? message, String? lastRequest, String? draftText, String? aiError,
    String? resultsError, bool clearAiError = false, bool clearResultsError = false}) => SmartSearchState(
      filters: filters ?? this.filters, rows: rows ?? this.rows, revision: revision ?? this.revision,
      page: page ?? this.page, more: more ?? this.more, interpreting: interpreting ?? this.interpreting,
      loading: loading ?? this.loading, started: started ?? this.started, message: message ?? this.message, lastRequest: lastRequest ?? this.lastRequest, draftText: draftText ?? this.draftText,
      aiError: clearAiError ? null : aiError ?? this.aiError,
      resultsError: clearResultsError ? null : resultsError ?? this.resultsError);
}

class SmartSearchSession extends StateNotifier<SmartSearchState> {
  SmartSearchSession(this._ai, this._properties, {this.defaultLocation}) : super(const SmartSearchState());
  final AiRepository _ai;
  final PropertyRepository _properties;
  final SmartSearchFilters Function()? defaultLocation;
  Map<String, dynamic> _defaultContext = {};
  bool _usingDefaultLocation = false;
  int _inference = 0, _results = 0;

  int _journey = 0;
  int beginJourney({SmartSearchFilters? savedFilters, SmartSearchFilters? entryFilters}) {
    final token = ++_journey;
    reset(useLocation: true);
    if (savedFilters != null || entryFilters != null) replaceManually(savedFilters ?? entryFilters!);
    return token;
  }
  void endJourney(int token) {
    scheduleMicrotask(() { if (mounted && token == _journey) reset(); });
  }
  void setDraftText(String value) { if (value != state.draftText) state = state.copyWith(draftText:value); }
  void startFromHome({required String location, String? type}) => reset();
  void updateViewport({required double south, required double west, required double north, required double east}) {
    final values = Map<String,dynamic>.from(state.filters.values)..remove('latitude')..remove('longitude')..remove('radius_km');
    values.addAll({'south':south,'west':west,'north':north,'east':east});
    replaceManually(SmartSearchFilters.fromMap(values));
  }

  Future<void> interpret(String message) async {
    final text = message.trim();
    if (text.isEmpty || text.length > 5000) return;
    final request = ++_inference, revision = state.revision;
    final filters = state.filters;
    state = state.copyWith(interpreting: true, clearAiError: true, lastRequest: text);
    try {
      // A default city is a starting point, not an explicit map constraint.
      // Let a city stated in the request override it; retain user-chosen bounds.
      final input = Map<String, dynamic>.from(filters.values);
      if (_usingDefaultLocation) { for (final key in _defaultContext.keys) { input.remove(key); } }
      final result = await _ai.refine(text, input, revision);
      if (!mounted || request != _inference || revision != state.revision) return;
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
      if (mounted && request == _inference && revision == state.revision) state = state.copyWith(interpreting: false, aiError: friendlyApiError(error));
    }
  }

  void _replace(SmartSearchFilters filters, {String message = 'حدّثنا شروطك. النتائج حسب الاختيارات الحالية.', String? draftText}) {
    _inference++; _results++;
    state = SmartSearchState(filters: filters, revision: state.revision + 1, message: message, lastRequest: state.lastRequest, draftText: draftText ?? state.draftText);
  }

  void replaceManually(SmartSearchFilters filters) {
    _usingDefaultLocation = false;
    _replace(filters);
    unawaited(search());
  }

  void remove(String key) => replaceManually(state.filters.without(key));

  void reset({bool useLocation = false}) {
    _inference++; _results++;
    _defaultContext = useLocation ? Map.of(defaultLocation?.call().values ?? const <String,dynamic>{}) : {};
    _usingDefaultLocation = _defaultContext.isNotEmpty;
    state = SmartSearchState(revision: state.revision + 1, filters: SmartSearchFilters.fromMap(_defaultContext));
  }

  Future<void> search({bool more = false}) async {
    if (more && (state.loading || !state.more)) return;
    final request = ++_results, revision = state.revision;
    final page = more ? state.page + 1 : 1;
    final filters = state.filters;
    state = state.copyWith(loading: true, started: true, clearResultsError: true, rows: more ? null : const []);
    try {
      final result = await _properties.searchListings(filters.apiFilters, page: page);
      if (!mounted || request != _results || revision != state.revision) return;
      final rows = more ? List<PropertySummary>.of(state.rows) : <PropertySummary>[];
      final ids = rows.map((row) => row.id).toSet();
      rows.addAll(result.$1.where((row) => ids.add(row.id)));
      state = state.copyWith(rows: List.unmodifiable(rows), page: page, more: result.$2, loading: false);
    } catch (error) {
      if (mounted && request == _results && revision == state.revision) state = state.copyWith(loading: false, resultsError: friendlyApiError(error));
    }
  }
}

// One owner route controls a journey. List/map share it; full exit invalidates it.
final smartSearchSessionProvider = StateNotifierProvider<SmartSearchSession, SmartSearchState>((ref) =>
  SmartSearchSession(ref.watch(aiRepositoryProvider), ref.watch(propertyRepositoryProvider),
    defaultLocation: () => SmartSearchFilters.fromMap(ref.read(homeLocationProvider).searchContext)));
