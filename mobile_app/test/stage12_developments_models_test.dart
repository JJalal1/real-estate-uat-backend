import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/developments/domain/development_models.dart';

void main() {
  test('Stage 12 development details parse developer and units', () {
    final details = DevelopmentDetails.fromJson({
      'id': 12,
      'developer_id': 3,
      'name': 'Project Twelve',
      'slug': 'project-twelve',
      'status': 'published',
      'completion_status': 'under_construction',
      'units_count': 1,
      'available_units_count': 1,
      'developer': {
        'id': 3,
        'name': 'Developer',
        'slug': 'developer',
        'status': 'active'
      },
      'units': [
        {
          'id': 8,
          'code': 'A-1',
          'title': 'Apartment A1',
          'unit_type': 'apartment',
          'area_m2': '145.5',
          'price': 25000000,
          'currency': 'YER',
          'status': 'available'
        }
      ],
    });
    expect(details.summary.id, 12);
    expect(details.summary.developer?.name, 'Developer');
    expect(details.units.single.areaM2, 145.5);
    expect(details.units.single.status, 'available');
  });

  test('Stage 12 developer projects count parses numeric strings', () {
    final developer = DeveloperSummary.fromJson({
      'id': '5',
      'name': 'D',
      'slug': 'd',
      'status': 'active',
      'projects_count': '4'
    });
    expect(developer.id, 5);
    expect(developer.projectsCount, 4);
  });
}
