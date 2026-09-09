from pathlib import Path

map_path = Path('mobile_app/lib/features/map/presentation/map_screen.dart')
source = map_path.read_text()

old_import = "import '../../properties/domain/property_marker.dart';\n"
if 'saved_search_builder_screen.dart' not in source:
    assert old_import in source
    source = source.replace(
        old_import,
        old_import + "import '../../properties/presentation/saved_search_builder_screen.dart';\n",
        1,
    )

marker = "  void _openAddProperty() {\n    context.push('/add-property');\n  }\n"
methods = r'''
  Map<String, dynamic> _currentSavedSearchFilters() {
    final bounds = _selectedAreaBounds;
    final filters = <String, dynamic>{
      if (_filterPurpose != null) 'purpose': _filterPurpose,
      if (_filterType != null) 'type': _filterType,
      if (_filterMinPrice != null) 'min_price': _filterMinPrice,
      if (_filterMaxPrice != null) 'max_price': _filterMaxPrice,
      if (_filterMinBedrooms != null) 'min_bedrooms': _filterMinBedrooms,
      if (_filterMinBathrooms != null) 'min_bathrooms': _filterMinBathrooms,
      if (_filterMinArea != null) 'min_area_m2': _filterMinArea,
      if (_filterMaxArea != null) 'max_area_m2': _filterMaxArea,
      if (_searchText.trim().isNotEmpty) 'search': _searchText.trim(),
    };
    if (bounds != null) {
      filters.addAll({
        'south': bounds.southwest.latitude,
        'west': bounds.southwest.longitude,
        'north': bounds.northeast.latitude,
        'east': bounds.northeast.longitude,
      });
    } else {
      filters.addAll({
        'latitude': _center.latitude,
        'longitude': _center.longitude,
        'radius_km': _defaultRadiusKm,
      });
    }
    return filters;
  }

  Future<void> _saveCurrentSearch() async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) {
      setAuthReturnLocation(ref, '/');
      await context.push('/auth');
      if (!mounted || ref.read(authControllerProvider).asData?.value == null) {
        return;
      }
    }
    final currentUser = ref.read(authControllerProvider).asData?.value;
    if (currentUser == null) return;
    if (!currentUser.isActive) {
      setAuthReturnLocation(ref, '/');
      await context.push('/verify-phone');
      if (!mounted || ref.read(authControllerProvider).asData?.value?.isActive != true) {
        return;
      }
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SavedSearchBuilderScreen(
          initialFilters: _currentSavedSearchFilters(),
        ),
      ),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ البحث وسيصلك تنبيه عند ظهور عقار مطابق.'),
      ),
    );
  }

'''
if '_currentSavedSearchFilters()' not in source:
    assert marker in source
    source = source.replace(marker, methods + marker, 1)

controls_old = '''        children: [
          Material(
            elevation: 5,
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: _beginAreaSelection,'''
controls_new = '''        children: [
          Material(
            elevation: 5,
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: _saveCurrentSearch,
              borderRadius: BorderRadius.circular(18),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_active_outlined, color: AppTheme.brand),
                    SizedBox(width: 7),
                    Text(
                      'حفظ البحث',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            elevation: 5,
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: _beginAreaSelection,'''
if 'onTap: _saveCurrentSearch' not in source:
    assert controls_old in source
    source = source.replace(controls_old, controls_new, 1)

appbar_old = '''          actions: [
            IconButton.filledTonal(
              tooltip: 'بحث وتصفية','''
appbar_new = '''          actions: [
            IconButton.filledTonal(
              tooltip: 'حفظ البحث الحالي',
              onPressed: _saveCurrentSearch,
              icon: const Icon(Icons.notifications_active_outlined),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'بحث وتصفية','''
if "tooltip: 'حفظ البحث الحالي'" not in source:
    assert appbar_old in source
    source = source.replace(appbar_old, appbar_new, 1)

map_path.write_text(source)

current_search_test = Path('mobile_app/test/product_ux_current_search_save_test.dart')
current_search_test.write_text(r'''import 'dart:io';

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
''')

services_test = Path('mobile_app/test/uat_services_hub_navigation_test.dart')
services_source = services_test.read_text()
old_label = "'مؤشر السوق داخل صفحة العقار'"
new_label = "'مؤشرات الأسعار داخل صفحة العقار'"
if old_label in services_source:
    services_source = services_source.replace(old_label, new_label, 1)
assert new_label in services_source
services_test.write_text(services_source)
