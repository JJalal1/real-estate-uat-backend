import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PropertyDiscoveryHistory {
  const PropertyDiscoveryHistory({
    this.recentSearches = const <String>[],
    this.lastFilters = const <String, dynamic>{},
  });

  final List<String> recentSearches;
  final Map<String, dynamic> lastFilters;
}

class PropertyDiscoveryHistoryStore {
  const PropertyDiscoveryHistoryStore({this.supportDirectory});

  /// Injectable for deterministic, filesystem-backed regression tests.
  final Future<Directory> Function()? supportDirectory;

  static const _fileName = 'property_discovery_history_v1.json';
  static const _maxRecent = 5;

  // All instances currently use one on-device file. Queue writes globally so
  // rapid filters/search edits cannot overwrite one another out of order.
  static Future<void> _lastWrite = Future<void>.value();

  Future<PropertyDiscoveryHistory> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const PropertyDiscoveryHistory();
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return const PropertyDiscoveryHistory();
      final recentRaw = raw['recent_searches'];
      final filtersRaw = raw['last_filters'];
      final recent = recentRaw is List
          ? recentRaw
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .take(_maxRecent)
              .toList(growable: false)
          : const <String>[];
      final filters = filtersRaw is Map
          ? Map<String, dynamic>.from(filtersRaw)
          : const <String, dynamic>{};
      return PropertyDiscoveryHistory(
        recentSearches: recent,
        lastFilters: filters,
      );
    } catch (_) {
      return const PropertyDiscoveryHistory();
    }
  }

  Future<void> record({
    required String query,
    required Map<String, dynamic> filters,
  }) {
    final snapshot = Map<String, dynamic>.from(filters);
    final write = _lastWrite.then(
      (_) => _record(query: query, filters: snapshot),
    );
    // _record is best-effort and absorbs IO errors. A failed save never
    // prevents a later search from persisting its own state.
    _lastWrite = write;
    return write;
  }

  Future<void> _record({
    required String query,
    required Map<String, dynamic> filters,
  }) async {
    File? temporary;
    try {
      final current = await load();
      final normalized = query.trim();
      final recent = <String>[
        if (normalized.isNotEmpty) normalized,
        ...current.recentSearches.where(
          (value) => value.toLowerCase() != normalized.toLowerCase(),
        ),
      ].take(_maxRecent).toList(growable: false);
      final file = await _file();
      await file.parent.create(recursive: true);
      final payload = jsonEncode(<String, dynamic>{
        'recent_searches': recent,
        'last_filters': filters,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      // Replace the file only after a complete, flushed JSON write. A crash
      // or failed save must not destroy the previous valid search history.
      temporary = File('${file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      // Discovery history is a convenience; never block search on local I/O.
    } finally {
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {
          // Temporary cleanup should not fail a search.
        }
      }
    }
  }

  Future<File> _file() async {
    final directory =
        await (supportDirectory?.call() ?? getApplicationSupportDirectory());
    return File('${directory.path}/$_fileName');
  }
}
