class SavedPropertySearch {
  const SavedPropertySearch({
    required this.id,
    required this.name,
    required this.filters,
    required this.alertFrequency,
    required this.isActive,
    required this.matchingCount,
    this.lastCheckedAt,
  });

  final int id;
  final String name;
  final Map<String, dynamic> filters;
  final String alertFrequency;
  final bool isActive;
  final int matchingCount;
  final DateTime? lastCheckedAt;

  factory SavedPropertySearch.fromJson(Map<String, dynamic> json) {
    final rawFilters = json['filters'];
    return SavedPropertySearch(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? 'بحث محفوظ',
      filters: rawFilters is Map
          ? Map<String, dynamic>.from(rawFilters)
          : const <String, dynamic>{},
      alertFrequency: json['alert_frequency']?.toString() ?? 'instant',
      isActive: json['is_active'] == true,
      matchingCount: _asInt(json['matching_count']),
      lastCheckedAt: DateTime.tryParse(json['last_checked_at']?.toString() ?? ''),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

String savedSearchAlertLabel(String value) => switch (value) {
      'daily' => 'ملخص يومي',
      'off' => 'بدون تنبيهات',
      _ => 'تنبيه فوري',
    };
