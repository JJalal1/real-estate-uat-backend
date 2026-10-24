import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/map/data/property_discovery_history_store.dart';

void main() {
  test('parallel filter updates persist latest state and preserve recent queries', () async {
    final dir = await Directory.systemTemp.createTemp('aqer-discovery-atomic-');
    addTearDown(() => dir.delete(recursive: true));
    final first = PropertyDiscoveryHistoryStore(supportDirectory: () async => dir);
    final second = PropertyDiscoveryHistoryStore(supportDirectory: () async => dir);
    await Future.wait([
      first.record(query: 'صنعاء', filters: {'governorate': 'صنعاء'}),
      second.record(query: 'إب', filters: {'governorate': 'إب', 'type': 'apartment'}),
      first.record(query: 'تعز', filters: {'governorate': 'تعز'}),
    ]);
    final current = await first.load();
    expect(current.lastFilters, {'governorate': 'تعز'});
    expect(current.recentSearches, ['تعز', 'إب', 'صنعاء']);
    final disk = File('${dir.path}/property_discovery_history_v1.json');
    expect(jsonDecode(await disk.readAsString()), isA<Map>());
    expect(dir.listSync().whereType<File>().map((file) => file.path).toList(),
        [disk.path]);
  });

  test('recent queries remain unique and bounded to five without mutating input', () async {
    final dir = await Directory.systemTemp.createTemp('aqer-discovery-atomic-');
    addTearDown(() => dir.delete(recursive: true));
    final store = PropertyDiscoveryHistoryStore(supportDirectory: () async => dir);
    final source = <String, dynamic>{'search': 'أول'};
    final writes = <Future<void>>[];
    for (final q in ['أول', 'ثاني', 'ثالث', 'رابع', 'خامس', 'سادس', 'أول']) {
      writes.add(store.record(query: q, filters: source));
    }
    source['search'] = 'تغير بعد الطلب';
    await Future.wait(writes);
    final result = await store.load();
    expect(result.lastFilters, {'search': 'أول'});
    expect(result.recentSearches, ['أول', 'سادس', 'خامس', 'رابع', 'ثالث']);
  });

  test('filesystem error never overwrites a previous successful snapshot', () async {
    final dir = await Directory.systemTemp.createTemp('aqer-discovery-atomic-');
    addTearDown(() => dir.delete(recursive: true));
    final store = PropertyDiscoveryHistoryStore(supportDirectory: () async => dir);
    await store.record(query: 'موجود', filters: {'type': 'house'});
    final before = await store.load();
    final bad = PropertyDiscoveryHistoryStore(
      supportDirectory: () async => Directory('${dir.path}/missing/child'),
    );
    await bad.record(query: 'خطأ', filters: {'type': 'farm'});
    final after = await store.load();
    expect(after.recentSearches, before.recentSearches);
    expect(after.lastFilters, before.lastFilters);
    await store.record(query: 'تعافى', filters: {'type': 'shop'});
    expect((await store.load()).recentSearches.first, 'تعافى');
  });
}
