import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'support/wave3_fakes.dart';

void main() {
  final saved = <String, dynamic>{
    'active': true,
    'submitted': 'ذمار',
    'draft': 'ذمار',
    'criteria': {'purpose': 'rent', 'min_bedrooms': 3},
    'home_started': true,
    'home_filters': {'search': 'ذمار', 'purpose': 'rent', 'min_bedrooms': 3},
    'home_pages': 2,
    'map_started': true,
    'map_filters': {
      'search': 'ذمار',
      'purpose': 'rent',
      'min_bedrooms': 3,
      'south': 14.0,
      'west': 44.0,
      'north': 15.0,
      'east': 45.0
    },
    'map_pages': 1,
  };
  test(
      'restart restores saved search pages and independent map bounds without replacing shared criteria',
      () async {
    final repo = Wave3PropertiesFake();
    repo.onSearch = (filters, page) async =>
        ([wave3Property(page)], page == 1);
    final home = SmartSearchSession(Wave3AiFake(), repo),
        map = SmartSearchSession(Wave3AiFake(), repo);
    final controller =
        MarketplaceSearchController(home, map, () => const HomeLocation());
    await controller.restoreOfflineSession(saved, current: () => true);
    expect(home.snapshot.rows.map((r) => r.id), [1, 2]);
    expect(home.snapshot.page, 2);
    expect(map.snapshot.rows.map((r) => r.id), [1]);
    expect(map.snapshot.filters.values['south'], 14.0);
    expect(controller.active, true);
    expect(controller.suggestionFilters().values['purpose'], 'rent');
    expect(controller.suggestionFilters().values['min_bedrooms'], 3);
    controller.dispose();
    home.dispose();
    map.dispose();
  });
  test(
      'account/session change while restoring cannot touch disposed sessions or load the next page',
      () async {
    final pending = Completer<(List<PropertySummary>, bool)>(),
        started = Completer<void>();
    final repo = Wave3PropertiesFake();
    var calls = 0, current = true;
    repo.onSearch = (_, page) {
      calls++;
      started.complete();
      return pending.future;
    };
    final home = SmartSearchSession(Wave3AiFake(), repo),
        map = SmartSearchSession(Wave3AiFake(), repo);
    final controller =
        MarketplaceSearchController(home, map, () => const HomeLocation());
    final restore =
        controller.restoreOfflineSession(saved, current: () => current);
    await started.future;
    current = false;
    controller.dispose();
    home.dispose();
    map.dispose();
    pending.complete(([wave3Property(1)], true));
    await restore;
    expect(calls, 1);
  });
}
