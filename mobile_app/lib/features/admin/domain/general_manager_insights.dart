class GeneralManagerInsights {
  const GeneralManagerInsights({
    required this.overview,
    required this.market,
    required this.journey,
    required this.team,
    required this.today,
  });

  final Map<String, dynamic> overview;
  final Map<String, dynamic> market;
  final Map<String, dynamic> journey;
  final Map<String, dynamic> team;
  final Map<String, dynamic> today;

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

  List<Map<String, dynamic>> marketList(String key) {
    final raw = market[key];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.map(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .toList(growable: false);
  }

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
    );
  }
}
