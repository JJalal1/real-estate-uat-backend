class GeneralManagerInsights {
  const GeneralManagerInsights({
    required this.overview,
    required this.market,
    required this.journey,
    required this.team,
    required this.today,
    required this.periods,
  });

  final Map<String, dynamic> overview;
  final Map<String, dynamic> market;
  final Map<String, dynamic> journey;
  final Map<String, dynamic> team;
  final Map<String, dynamic> today;
  final Map<String, dynamic> periods;

  int value(Map<String, dynamic> source, String key) {
    final raw = source[key];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  int overviewCount(String key) => value(overview, key);
  int marketCount(String key) => value(market, key);
  int teamCount(String key) => value(team, key);
  int todayCount(String key) => value(today, key);

  int? journeyCount(String key) {
    final raw = journey[key];
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  Map<String, dynamic> period(String key) {
    final raw = periods[key];
    if (raw is! Map) return const <String, dynamic>{};
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  List<Map<String, dynamic>> marketList(String key) => _listOfMaps(market[key]);

  factory GeneralManagerInsights.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final raw = json[key];
      if (raw is! Map) return const <String, dynamic>{};
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    return GeneralManagerInsights(
      overview: section('overview'),
      market: section('market'),
      journey: section('journey'),
      team: section('team'),
      today: section('today'),
      periods: section('periods'),
    );
  }
}

class GeneralManagerTeamMember {
  const GeneralManagerTeamMember({
    required this.id,
    required this.name,
    required this.role,
    required this.openTasks,
    required this.closedTasks,
    required this.overdueTasks,
    required this.urgentTasks,
    required this.tickets,
    required this.verifications,
    required this.listingReviews,
    required this.reports,
    required this.averageClaimMinutes,
    required this.lastActivityAt,
  });

  final int id;
  final String name;
  final String role;
  final int openTasks;
  final int closedTasks;
  final int overdueTasks;
  final int urgentTasks;
  final int tickets;
  final int verifications;
  final int listingReviews;
  final int reports;
  final int? averageClaimMinutes;
  final DateTime? lastActivityAt;

  bool get isManager => role == 'support_manager';

  factory GeneralManagerTeamMember.fromJson(Map<String, dynamic> json) {
    int number(String key) {
      final raw = json[key];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return GeneralManagerTeamMember(
      id: number('id'),
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'support_agent',
      openTasks: number('open_tasks'),
      closedTasks: number('closed_tasks'),
      overdueTasks: number('overdue_tasks'),
      urgentTasks: number('urgent_tasks'),
      tickets: number('tickets'),
      verifications: number('verifications'),
      listingReviews: number('listing_reviews'),
      reports: number('reports'),
      averageClaimMinutes: json['average_claim_minutes'] == null
          ? null
          : number('average_claim_minutes'),
      lastActivityAt: DateTime.tryParse(json['last_activity_at']?.toString() ?? ''),
    );
  }
}

class GeneralManagerPlaceResult {
  const GeneralManagerPlaceResult({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.bounds,
  });

  final String label;
  final double latitude;
  final double longitude;
  final String type;
  final Map<String, dynamic>? bounds;

  factory GeneralManagerPlaceResult.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final raw = json[key];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? 0;
    }

    final rawBounds = json['bounds'];
    return GeneralManagerPlaceResult(
      label: json['label']?.toString() ?? '',
      latitude: number('latitude'),
      longitude: number('longitude'),
      type: json['type']?.toString() ?? 'place',
      bounds: rawBounds is Map
          ? rawBounds.map((key, value) => MapEntry(key.toString(), value))
          : null,
    );
  }
}

List<Map<String, dynamic>> _listOfMaps(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}
