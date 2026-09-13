import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved search builder preserves and edits the full supported filter set', () {
    final builder = File(
      'lib/features/properties/presentation/saved_search_builder_screen.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/properties/data/saved_search_repository.dart',
    ).readAsStringSync();

    for (final key in <String>[
      'min_price',
      'max_price',
      'min_bedrooms',
      'min_bathrooms',
      'min_area_m2',
      'max_area_m2',
      'latitude',
      'longitude',
      'radius_km',
      'south',
      'west',
      'north',
      'east',
    ]) {
      expect(builder, contains("'$key'"), reason: 'Missing saved-search filter $key');
    }

    expect(builder, contains('existingSearch'));
    expect(builder, contains('حفظ التعديلات'));
    expect(builder, contains('إزالة قيد الموقع'));
    expect(repository, contains('Future<SavedPropertySearch> update('));
    expect(repository, contains("'/saved-searches/\$id'"));
  });

  test('saved searches expose an edit action without enabling deferred daily scheduling', () {
    final screen = File(
      'lib/features/properties/presentation/saved_searches_screen.dart',
    ).readAsStringSync();
    final builder = File(
      'lib/features/properties/presentation/saved_search_builder_screen.dart',
    ).readAsStringSync();

    expect(screen, contains("value: 'edit'"));
    expect(screen, contains('SavedSearchBuilderScreen(existingSearch: widget.search)'));
    expect(builder, contains('التنبيه الفوري يعمل الآن'));
    expect(builder, contains("value: 'instant'"));
    expect(builder, contains("value: 'off'"));
    expect(builder, isNot(contains("onChanged: (value) => setState(() => _frequency = value ?? 'daily')")));
  });
}
