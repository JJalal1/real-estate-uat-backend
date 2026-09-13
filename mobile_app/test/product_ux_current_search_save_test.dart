import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discovery can seed a saved search from current filters and map area', () {
    final source = File(
      'lib/features/map/presentation/map_screen.dart',
    ).readAsStringSync();

    expect(source, contains('SavedSearchBuilderScreen'));
    expect(source, contains('_currentSavedSearchFilters'));
    expect(source, contains("'purpose': _filterPurpose"));
    expect(source, contains("'min_price': _filterMinPrice"));
    expect(source, contains("'search': _searchText.trim()"));
    expect(source, contains("'south': bounds.southwest.latitude"));
    expect(source, contains("'latitude': _center.latitude"));
    expect(source, contains("'radius_km': _defaultRadiusKm"));
    expect(source, contains('حفظ البحث الحالي'));
    expect(source, contains('حفظ البحث'));
  });
}
