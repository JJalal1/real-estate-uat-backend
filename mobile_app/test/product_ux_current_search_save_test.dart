import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/properties/domain/saved_property_search.dart';

void main() {
  test('discovery hides new saved-search entry points and preserves current criteria', () {
    final source = File(
      'lib/features/map/presentation/map_screen.dart',
    ).readAsStringSync();
    final assisted = File(
      'lib/features/discovery/presentation/assisted_search_screen.dart',
    ).readAsStringSync();

    for (final discovery in [source, assisted]) {
      expect(discovery, isNot(contains('SavedSearchBuilderScreen')));
      expect(discovery, isNot(contains('حفظ البحث الحالي')));
      expect(discovery, isNot(contains('حفظ البحث')));
    }
    expect(source, contains("'purpose': _filterPurpose"));
    expect(source, contains("'min_price': _filterMinPrice"));
    expect(source, contains("'search': _searchText.trim()"));
    expect(source, contains("'south': _selectedAreaBounds!.southwest.latitude"));
    expect(source, contains("'latitude': _center.latitude"));
    expect(source, contains("'radius_km': _radiusKm"));
    expect(source, contains('encodedRing'));
    expect(source, contains('_currentSmartFilters().apiFilters'));
  });

  test('existing saved searches retain rental criteria, map area and alert settings', () {
    const filters = <String, dynamic>{
      'type': 'apartment',
      'purpose': 'rent',
      'search': 'إب',
      'min_monthly_rent': 50000,
      'max_monthly_rent': 100000,
      'currency': 'YER',
      'latitude': 13.9667,
      'longitude': 44.1833,
      'radius_km': 5,
      'south': 13.95,
      'west': 44.16,
      'north': 13.99,
      'east': 44.20,
    };
    final saved = SavedPropertySearch.fromJson({
      'id': 7,
      'name': 'شقق إب القديمة',
      'filters': filters,
      'alert_frequency': 'daily',
      'is_active': true,
      'matching_count': 3,
      'last_checked_at': '2026-10-20T10:30:00Z',
    });

    expect(saved.id, 7);
    expect(saved.name, 'شقق إب القديمة');
    expect(saved.filters, filters);
    expect(SmartSearchFilters.fromApiFilters(saved.filters).apiFilters, filters);
    expect(saved.alertFrequency, 'daily');
    expect(savedSearchAlertLabel(saved.alertFrequency), 'ملخص يومي');
    expect(saved.isActive, isTrue);
    expect(saved.matchingCount, 3);
    expect(saved.lastCheckedAt, DateTime.utc(2026, 10, 20, 10, 30));
  });
}
