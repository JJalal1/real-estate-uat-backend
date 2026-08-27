import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/regions/domain/region_models.dart';

void main() {
  test('region cell parses GeoJSON longitude latitude order', () {
    final cell = RegionCell.fromJson({
      'id': 8,
      'governorate': {'id': 2, 'name_ar': 'صنعاء'},
      'code': 'SANA_A1',
      'name_ar': 'ألف',
      'is_active': true,
      'is_reserved': true,
      'active_broker': {'id': 7, 'name': 'دلال الاختبار'},
      'boundary': {
        'type': 'Polygon',
        'coordinates': [
          [
            [44.19, 15.36],
            [44.20, 15.36],
            [44.20, 15.37],
            [44.19, 15.36],
          ]
        ],
      },
      'assignment_history': [],
    });
    expect(cell.boundary.length, 3);
    expect(cell.boundary.first.latitude, 15.36);
    expect(cell.boundary.first.longitude, 44.19);
    expect(cell.isReserved, isTrue);
    expect(cell.activeBroker?.id, 7);
  });

  test('assignment history keeps ended and active records', () {
    final cell = RegionCell.fromJson({
      'id': 9,
      'governorate': {'id': 2, 'name_ar': 'صنعاء'},
      'code': 'SANA_A2',
      'name_ar': 'باء',
      'is_active': true,
      'is_reserved': false,
      'boundary': {'type': 'Polygon', 'coordinates': []},
      'assignment_history': [
        {
          'id': 1,
          'broker_user_id': 3,
          'broker_name': 'قديم',
          'starts_at': '2026-08-19T00:00:00Z',
          'ends_at': '2026-08-19T01:00:00Z'
        },
        {
          'id': 2,
          'broker_user_id': 4,
          'broker_name': 'حالي',
          'starts_at': '2026-08-19T01:00:00Z',
          'ends_at': null
        },
      ],
    });
    expect(cell.assignmentHistory.length, 2);
    expect(cell.assignmentHistory.first.endsAt, isNotNull);
    expect(cell.assignmentHistory.last.endsAt, isNull);
  });
}
