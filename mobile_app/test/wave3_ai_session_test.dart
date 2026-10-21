import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/properties/data/property_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'support/wave3_fakes.dart';

void main() {
  test('each fresh journey starts empty without restoring home location',() async {
    final ai=Wave3AiFake();
    final session=SmartSearchSession(ai,Wave3PropertiesFake());addTearDown(session.dispose);
    session.replaceManually(SmartSearchFilters.fromMap({'search':'تعز','type':'land'}));
    session.beginJourney();expect(session.state.filters.values,isEmpty);expect(session.state.rows,isEmpty);
    expect(ai.requests,isEmpty);
  });
  test('followup messages add only a budget, remove only rooms, and preserve type, purpose and place', () async {
    final ai = Wave3AiFake(), properties = Wave3PropertiesFake();
    final session = SmartSearchSession(ai, properties); addTearDown(session.dispose);
    await session.interpret('شقة إيجار في صنعاء، ثلاث غرف');
    await session.interpret('أقل سعر: مئة ألف');
    expect(ai.requests.last.filters, containsPair('search', 'صنعاء'));
    expect(properties.queries.last.filters, containsPair('max_monthly_rent', 100000));
    await session.interpret('أزل شرط الغرف');
    expect(session.state.filters.values, {'type': 'apartment', 'purpose': 'rent', 'search': 'صنعاء', 'max_price': 100000});
    session.remove('budget');
    expect(session.state.filters.values, {'type': 'apartment', 'purpose': 'rent', 'search': 'صنعاء'});
    session.reset(); expect(session.state.filters.values, isEmpty); expect(session.state.rows, isEmpty);
  });

  test('a late model response cannot undo a newer manual choice or explicit reset', () async {
    final delayed = Completer<Map<String, dynamic>>();
    final ai = Wave3AiFake()..onRefine = (_, __, ___) => delayed.future;
    final session = SmartSearchSession(ai, Wave3PropertiesFake()); addTearDown(session.dispose);
    final pending = session.interpret('شقة');
    session.replaceManually(SmartSearchFilters.fromMap({'type': 'land', 'search': 'تعز'}));
    delayed.complete({'revision': 0, 'filters': {'type': 'apartment', 'search': 'صنعاء'}}); await pending;
    expect(session.state.filters.values, {'type': 'land', 'search': 'تعز'});
    final resetResponse = Completer<Map<String, dynamic>>(); ai.onRefine = (_, __, ___) => resetResponse.future;
    final before = session.state.revision, resetPending = session.interpret('غير الموقع'); session.reset();
    resetResponse.complete({'revision': before, 'filters': {'search': 'عدن'}}); await resetPending;
    expect(session.state.filters.values, isEmpty);
  });

  test('old results never replace a newer query and pagination keeps real IDs unique', () async {
    final old = Completer<(List<PropertySummary>, bool)>();
    final properties = Wave3PropertiesFake()..onSearch = (f, page) async {
      if (f['type'] == 'land') return old.future;
      return page == 1 ? ([wave3Property(11)], true) : ([wave3Property(11), wave3Property(12)], false);
    };
    final session = SmartSearchSession(Wave3AiFake(), properties); addTearDown(session.dispose);
    session.replaceManually(SmartSearchFilters.fromMap({'type': 'land'}));
    session.replaceManually(SmartSearchFilters.fromMap({'type': 'apartment'}));
    await Future<void>.delayed(Duration.zero); await Future<void>.delayed(Duration.zero);
    old.complete(([wave3Property(99)], false)); await Future<void>.delayed(Duration.zero);
    expect(session.state.rows.map((row) => row.id), [11]);
    await session.search(more: true); expect(session.state.rows.map((row) => row.id), [11, 12]);
    expect(session.state.more, false);
  });

  test('unavailable model retains filters within the journey and full exit clears it', () async {
    final ai = Wave3AiFake();
    final container = ProviderContainer(overrides: [aiRepositoryProvider.overrideWithValue(ai), propertyRepositoryProvider.overrideWithValue(Wave3PropertiesFake())]);
    addTearDown(container.dispose);
    final listener = container.listen(smartSearchSessionProvider, (_, __) {});
    final session = container.read(smartSearchSessionProvider.notifier); final journey=session.beginJourney(); await session.interpret('شقة إيجار في صنعاء');
    ai.onRefine = (_, __, ___) async => throw StateError('unavailable'); await session.interpret('سعر أقل');
    expect(session.state.aiError, isNotNull); expect(session.state.rows.single.id, 11);
    listener.close(); await container.pump();
    expect(container.read(smartSearchSessionProvider).filters.values['search'], 'صنعاء');
    expect(identical(container.read(smartSearchSessionProvider.notifier), session), true);
    session.endJourney(journey);await container.pump();expect(container.read(smartSearchSessionProvider).filters.values,isEmpty);
  });

  test('context removes irrelevant chips and nullable booleans keep explicit false and rental currency', () {
    final filters = SmartSearchFilters.fromMap({'type': 'apartment', 'purpose': 'rent', 'max_price': 150000, 'has_parking': 0});
    expect(filters.apiFilters, containsPair('has_parking', 0)); expect(filters.apiFilters, containsPair('max_monthly_rent', 150000));
    expect(filters.apiFilters, containsPair('currency', 'YER'));
    expect(filters.chips.map((chip) => chip.$2), contains('بدون موقف'));
    expect(SmartSearchFilters.fromMap({...filters.values, 'type': 'land', 'min_bedrooms': 4, 'floor_number': '3'}).values.keys,
      isNot(anyOf(contains('has_elevator'), contains('min_bedrooms'), contains('floor_number'))));
    expect(SmartSearchFilters.fromMap({'type':'apartment','purpose':'sale','has_elevator':false}).values.containsKey('has_elevator'),false);
    expect(SmartSearchFilters.fromMap({'type':'apartment','purpose':'rent','has_elevator':false}).values.containsKey('has_elevator'),false);
    expect(SmartSearchFilters.fromMap({'type': 'floor'}).values, {'type': 'apartment', 'unit_occupies_entire_floor': true});
  });
}
