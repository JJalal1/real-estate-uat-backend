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
  const PropertyDiscoveryHistoryStore();

  static const _fileName = 'property_discovery_history_v1.json';
  static const _maxRecent = 5;

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
  }) async {
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
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'recent_searches': recent,
          'last_filters': filters,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } catch (_) {
      // Discovery history is a convenience only; never block search on local I/O.
    }
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }
}
