import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';

import 'support/wave3_fakes.dart';

const _place = HomeLocation(governorate: 'ذمار', governorateCode: 'YE-DH', label: 'ذمار', manual: true);
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('the map starts with matching settled Home pages and still queries its actual viewport', () async {
    final viewport = Completer<(List<PropertySummary>, bool)>();
    final repo = Wave3PropertiesFake()..onSearch = (filters, page) async =>
        filters.containsKey('south') ? viewport.future : ([wave3Property(146 + page)], page == 1);
    final home = SmartSearchSession(Wave3AiFake(), repo), map = SmartSearchSession(Wave3AiFake(), repo);
    final owner = MarketplaceSearchController(home, map, () => _place);
    addTearDown(() { owner.dispose(); home.dispose(); map.dispose(); });
    owner.edit('20');
    owner.applyFilters(SmartSearchFilters.fromMap({'purpose': 'rent'}));
    await _settle();
    await home.search(more: true);
    final before = home.snapshot;
    expect(repo.queries, hasLength(2));

    owner.enterMap();
    expect(repo.queries, hasLength(2));
    expect(map.snapshot.rows.map((row) => row.id), [147, 148]);
    expect(map.snapshot.page, 2);
    expect(map.snapshot.loading, isFalse);

    map.updateViewport(south: 15, west: 44, north: 16, east: 45);
    expect(repo.queries, hasLength(3));
    expect(map.snapshot.loading, isTrue);
    expect(map.snapshot.rows.map((row) => row.id), [147, 148]);
    expect(repo.queries.last.page, 1);
    expect(repo.queries.last.filters, containsPair('purpose', 'rent'));
    viewport.complete(([wave3Property(147)], false));
    await _settle();
    expect(map.snapshot.loading, isFalse);
    expect(map.snapshot.rows.single.id, 147);
    expect(home.snapshot, same(before));
  });

  test('temporary map edits preserve the exact Home UI, pages and rows on return', () async {
    final repo = Wave3PropertiesFake()..onSearch = (filters, page) async =>
        ([wave3Property(filters['search'] == 'بحث الخريطة' ? 90 : page)], page == 1);
    final home = SmartSearchSession(Wave3AiFake(), repo), map = SmartSearchSession(Wave3AiFake(), repo);
    final owner = MarketplaceSearchController(home, map, () => _place);
    addTearDown(() { owner.dispose(); home.dispose(); map.dispose(); });
    owner.edit('بحث الصفحة');
    owner.applyFilters(SmartSearchFilters.fromMap({'types': ['apartment', 'villa'], 'purpose': 'rent', 'max_price': 200000}));
    await _settle();
    await home.search(more: true);
    owner.edit('مسودة لم أرسلها');
    final parent = owner.uiFor(), parentResults = home.snapshot;

    final token = owner.enterMap();
    expect(owner.enterMap(), token);
    await _settle();
    owner.edit('بحث الخريطة', onMap: true);
    owner.setChoice('purpose', 'sale', onMap: true);
    owner.setChoice('max_price', 50000000, onMap: true);
    map.updateViewport(south: 14, west: 44, north: 15, east: 45);
    await _settle();
    expect(owner.uiFor(onMap: true).criteria.values['purpose'], 'sale');
    expect(map.snapshot.filters.hasMapArea, isTrue);
    expect(map.snapshot.rows.single.id, 90);
    expect(owner.uiFor().draftQuery, parent.draftQuery);
    expect(owner.uiFor().submittedQuery, parent.submittedQuery);
    expect(owner.uiFor().criteria.sameAs(parent.criteria), isTrue);
    expect(identical(home.snapshot, parentResults), isTrue);

    owner.leaveMap(token);
    await _settle();
    expect(owner.uiFor().mapOpen, isFalse);
    expect(owner.uiFor().mapEditor, isNull);
    expect(home.snapshot.rows.map((row) => row.id), [1, 2]);
    expect(home.snapshot.page, 2);
    expect(home.snapshot.filters.values['search'], 'بحث الصفحة');
    expect(map.snapshot.rows, isEmpty);
    final next = owner.enterMap();
    await _settle();
    expect(next, greaterThan(token));
    expect(map.snapshot.filters.values['search'], 'مسودة لم أرسلها');
    expect(map.snapshot.filters.values['purpose'], 'rent');
    expect(map.snapshot.filters.values['max_price'], 200000);
    expect(map.snapshot.filters.hasMapArea, isFalse);
    expect(identical(home.snapshot, parentResults), isTrue);
  });

  test('stale map pop and deferred reset cannot close or overwrite a newer map entry', () async {
    final pending = Completer<(List<PropertySummary>, bool)>();
    final repo = Wave3PropertiesFake()..onSearch = (filters, _) =>
        filters['search'] == 'قديم' ? pending.future : Future.value(([wave3Property(2)], false));
    final home = SmartSearchSession(Wave3AiFake(), repo), map = SmartSearchSession(Wave3AiFake(), repo);
    final owner = MarketplaceSearchController(home, map, () => _place);
    addTearDown(() { owner.dispose(); home.dispose(); map.dispose(); });
    final old = owner.enterMap(filters: SmartSearchFilters.fromMap({'search': 'قديم', 'purpose': 'rent'}));
    owner.leaveMap(old);
    final current = owner.enterMap(filters: SmartSearchFilters.fromMap({'search': 'جديد', 'purpose': 'sale'}));
    owner.leaveMap(old);
    pending.complete(([wave3Property(1)], false));
    await _settle();
    expect(owner.isMapJourneyCurrent(current), isTrue);
    expect(owner.uiFor().mapOpen, isTrue);
    expect(owner.uiFor(onMap: true).draftQuery, 'جديد');
    expect(map.snapshot.filters.values['search'], 'جديد');
    expect(map.snapshot.rows.single.id, 2);
    expect(home.snapshot.started, isFalse);
  });

  test('a viewport replaces copied governorate constraints when a later map filter changes', () async {
    final repo = Wave3PropertiesFake();
    final home = SmartSearchSession(Wave3AiFake(), repo), map = SmartSearchSession(Wave3AiFake(), repo);
    final owner = MarketplaceSearchController(home, map, () => _place);
    addTearDown(() { owner.dispose(); home.dispose(); map.dispose(); });
    owner.enterMap(filters: SmartSearchFilters.fromMap({'governorate': 'ذمار', 'governorate_code': 'YE-DH', 'purpose': 'rent'}));
    await _settle();
    map.updateViewport(south: 13, west: 43, north: 14, east: 44);
    await _settle();
    expect(owner.uiFor(onMap: true).criteria.values.containsKey('governorate'), isFalse);
    expect(owner.uiFor(onMap: true).criteria.values.containsKey('governorate_code'), isFalse);
    owner.setChoice('max_price', 150000, onMap: true);
    await _settle();
    expect(map.snapshot.filters.values['south'], 13);
    expect(map.snapshot.filters.values['north'], 14);
    expect(map.snapshot.filters.values.containsKey('governorate'), isFalse);
    expect(map.snapshot.filters.values.containsKey('governorate_code'), isFalse);
    expect(map.snapshot.filters.values['purpose'], 'rent');
    expect(map.snapshot.filters.values['max_price'], 150000);
    expect(home.snapshot.started, isFalse);
  });

  test('late persisted Home hydration keeps an already active map editor isolated', () async {
    final pendingHome = Completer<(List<PropertySummary>, bool)>();
    final repo = Wave3PropertiesFake()..onSearch = (filters, _) =>
        filters['search'] == 'محفوظ' ? pendingHome.future : Future.value(([wave3Property(9)], false));
    final home = SmartSearchSession(Wave3AiFake(), repo), map = SmartSearchSession(Wave3AiFake(), repo);
    final owner = MarketplaceSearchController(home, map, () => _place);
    addTearDown(() { owner.dispose(); home.dispose(); map.dispose(); });
    final token = owner.enterMap();
    owner.edit('مسودة الخريطة', onMap: true);
    owner.setChoice('purpose', 'sale', onMap: true);
    await _settle();
    final child = owner.uiFor(onMap: true), mapResults = map.snapshot;
    final restore = owner.restoreOfflineSession({
      'active': true, 'submitted': 'محفوظ', 'draft': 'محفوظ',
      'criteria': {'purpose': 'rent'}, 'home_started': true,
      'home_filters': {'search': 'محفوظ', 'purpose': 'rent'}, 'home_pages': 1,
      'map_started': true, 'map_filters': {'search': 'خريطة قديمة', 'purpose': 'rent'},
    }, current: () => true);
    expect(owner.isMapJourneyCurrent(token), isTrue);
    expect(identical(owner.uiFor(onMap: true), child), isTrue);
    pendingHome.complete(([wave3Property(1)], false));
    await restore;
    expect(identical(map.snapshot, mapResults), isTrue);
    expect(owner.uiFor().draftQuery, 'محفوظ');
    expect(home.snapshot.rows.single.id, 1);
    owner.leaveMap(token);
    await _settle();
    expect(owner.uiFor().criteria.values['purpose'], 'rent');
    expect(home.snapshot.rows.single.id, 1);
    expect(map.snapshot.started, isFalse);
  });

  test('an explicit Home search prevents a delayed offline checkpoint from replacing it', () async {
    final repo = Wave3PropertiesFake(), home = SmartSearchSession(Wave3AiFake(), Wave3PropertiesFake());
    final map = SmartSearchSession(Wave3AiFake(), repo);
    final owner = MarketplaceSearchController(home, map, () => _place);
    addTearDown(() { owner.dispose(); home.dispose(); map.dispose(); });
    owner.edit('بحث جديد');
    await owner.submit();
    final current = home.snapshot;
    await owner.restoreOfflineSession({'active': true, 'draft': 'قديم', 'home_started': true,
      'home_filters': {'search': 'قديم'}}, current: () => true);
    expect(owner.uiFor().draftQuery, 'بحث جديد');
    expect(identical(home.snapshot, current), isTrue);
  });

  test('AI pop rejects an inference already queued before the safe deferred reset', () async {
    final response = Completer<Map<String, dynamic>>(), ai = Wave3AiFake(), repo = Wave3PropertiesFake();
    ai.onRefine = (_, __, ___) => response.future;
    final session = SmartSearchSession(ai, repo);
    addTearDown(session.dispose);
    final token = session.beginJourney();
    final emitted = <SmartSearchState>[];
    final stop = session.addListener(emitted.add, fireImmediately: false);
    addTearDown(stop);
    final operation = session.interpret('فلل');
    response.complete({'revision': ai.requests.single.revision, 'filters': {'type': 'villa'}});
    session.endJourney(token);
    await operation;
    await _settle();
    expect(emitted.any((state) => state.filters.selectedTypes.contains('villa')), isFalse);
    expect(repo.queries, isEmpty);
    expect(session.snapshot.filters.values, isEmpty);
  });

  test('AI pop rejects queued rows and an old route cannot reset a fresh journey', () async {
    final response = Completer<(List<PropertySummary>, bool)>();
    final repo = Wave3PropertiesFake()..onSearch = (filters, _) =>
        filters['search'] == 'قديم' ? response.future : Future.value(([wave3Property(2)], false));
    final session = SmartSearchSession(Wave3AiFake(), repo);
    addTearDown(session.dispose);
    final old = session.beginJourney();
    final emitted = <SmartSearchState>[];
    final stop = session.addListener(emitted.add, fireImmediately: false);
    addTearDown(stop);
    final operation = session.replaceManually(SmartSearchFilters.fromMap({'search': 'قديم'}));
    response.complete(([wave3Property(1)], false));
    session.endJourney(old);
    expect(session.isCurrentJourney(old), isFalse);
    final current = session.beginJourney(entryFilters: SmartSearchFilters.fromMap({'search': 'جديد', 'purpose': 'rent'}));
    session.endJourney(old);
    await operation;
    await _settle();
    expect(current, greaterThan(old));
    expect(session.isCurrentJourney(current), isTrue);
    expect(session.isCurrentJourney(old), isFalse);
    expect(emitted.any((state) => state.rows.any((row) => row.id == 1)), isFalse);
    expect(session.snapshot.filters.values['search'], 'جديد');
    expect(session.snapshot.rows.single.id, 2);
  });
}
