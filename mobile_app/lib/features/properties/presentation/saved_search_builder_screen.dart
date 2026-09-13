import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/saved_search_repository.dart';
import '../domain/saved_property_search.dart';

class SavedSearchBuilderScreen extends ConsumerStatefulWidget {
  const SavedSearchBuilderScreen({
    this.initialFilters = const <String, dynamic>{},
    this.existingSearch,
    super.key,
  });

  final Map<String, dynamic> initialFilters;
  final SavedPropertySearch? existingSearch;

  @override
  ConsumerState<SavedSearchBuilderScreen> createState() =>
      _SavedSearchBuilderScreenState();
}

class _SavedSearchBuilderScreenState
    extends ConsumerState<SavedSearchBuilderScreen> {
  late final TextEditingController _name;
  late final TextEditingController _keywords;
  late final TextEditingController _minPrice;
  late final TextEditingController _maxPrice;
  late final TextEditingController _minBedrooms;
  late final TextEditingController _minBathrooms;
  late final TextEditingController _minArea;
  late final TextEditingController _maxArea;
  late Map<String, dynamic> _baseFilters;
  String? _purpose;
  String? _type;
  String _frequency = 'instant';
  bool _saving = false;

  bool get _editing => widget.existingSearch != null;

  @override
  void initState() {
    super.initState();
    final filters = widget.existingSearch?.filters ?? widget.initialFilters;
    _baseFilters = Map<String, dynamic>.from(filters);
    _purpose = _nullable(filters['purpose']);
    _type = _nullable(filters['type']);
    _keywords = TextEditingController(text: _nullable(filters['search']) ?? '');
    _minPrice = TextEditingController(text: _numberText(filters['min_price']));
    _maxPrice = TextEditingController(text: _numberText(filters['max_price']));
    _minBedrooms =
        TextEditingController(text: _numberText(filters['min_bedrooms']));
    _minBathrooms =
        TextEditingController(text: _numberText(filters['min_bathrooms']));
    _minArea =
        TextEditingController(text: _numberText(filters['min_area_m2']));
    _maxArea =
        TextEditingController(text: _numberText(filters['max_area_m2']));
    _name = TextEditingController(
      text: widget.existingSearch?.name ?? _suggestedName(filters),
    );
    _frequency = widget.existingSearch?.alertFrequency ?? 'instant';
  }

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    _minPrice.dispose();
    _maxPrice.dispose();
    _minBedrooms.dispose();
    _minBathrooms.dispose();
    _minArea.dispose();
    _maxArea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: _editing ? 'تعديل البحث المحفوظ' : 'حفظ بحث جديد',
        ),
        body: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s16,
            AppLayout.compactPageGutter,
            AppSpacing.s40,
          ),
          children: [
            AppSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _editing ? 'عدّل شروط البحث' : 'خلّ التطبيق يتابع لك',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'نحفظ شروط البحث في حسابك ونرسل تنبيهًا عند نشر عقار جديد يطابقها.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'اسم البحث',
                hintText: 'مثال: شقة غرفتين في صنعاء',
                prefixIcon: Icon(Icons.bookmark_add_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'sale',
                  label: Text('شراء'),
                  icon: Icon(Icons.sell_outlined),
                ),
                ButtonSegment(
                  value: 'rent',
                  label: Text('إيجار'),
                  icon: Icon(Icons.key_outlined),
                ),
              ],
              selected: _purpose == null ? const <String>{} : {_purpose!},
              emptySelectionAllowed: true,
              onSelectionChanged: (value) =>
                  setState(() => _purpose = value.isEmpty ? null : value.first),
            ),
            const SizedBox(height: AppSpacing.s12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'نوع العقار'),
              items: const [
                DropdownMenuItem(value: 'apartment', child: Text('شقة')),
                DropdownMenuItem(value: 'house', child: Text('منزل')),
                DropdownMenuItem(value: 'villa', child: Text('فيلا')),
                DropdownMenuItem(value: 'land', child: Text('أرض')),
                DropdownMenuItem(value: 'shop', child: Text('محل')),
                DropdownMenuItem(value: 'office', child: Text('مكتب')),
                DropdownMenuItem(value: 'farm', child: Text('مزرعة')),
              ],
              onChanged: (value) => setState(() => _type = value),
            ),
            const SizedBox(height: AppSpacing.s12),
            TextField(
              controller: _keywords,
              decoration: const InputDecoration(
                labelText: 'كلمات البحث (اختياري)',
                hintText: 'حي، شارع، وصف...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            const AppSectionHeader(
              title: 'السعر',
              subtitle: 'اترك أي خانة فارغة إذا ما تبغى تحددها.',
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minPrice,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'أقل سعر',
                      suffixText: 'ريال',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: TextField(
                    controller: _maxPrice,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'أعلى سعر',
                      suffixText: 'ريال',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s20),
            const AppSectionHeader(title: 'المواصفات'),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minBedrooms,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'أقل عدد غرف'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: TextField(
                    controller: _minBathrooms,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'أقل عدد حمامات'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minArea,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'أقل مساحة',
                      suffixText: 'م²',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: TextField(
                    controller: _maxArea,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'أعلى مساحة',
                      suffixText: 'م²',
                    ),
                  ),
                ),
              ],
            ),
            if (_hasLocationFilter) ...[
              const SizedBox(height: AppSpacing.s20),
              const AppSectionHeader(title: 'الموقع المحفوظ'),
              const SizedBox(height: AppSpacing.s8),
              AppSurface(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _locationSummary,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          TextButton.icon(
                            onPressed: _removeLocationFilter,
                            icon: const Icon(Icons.location_off_outlined),
                            label: const Text('إزالة قيد الموقع'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s20),
            const AppSectionHeader(
              title: 'التنبيه',
              subtitle:
                  'التنبيه الفوري يعمل الآن. لن نظهر الملخص اليومي كخيار جديد قبل تشغيل جدولة موثوقة له.',
            ),
            const SizedBox(height: AppSpacing.s8),
            RadioListTile<String>(
              value: 'instant',
              groupValue: _frequency,
              title: const Text('تنبيه فوري'),
              subtitle: const Text('عند نشر عقار جديد يطابق البحث.'),
              onChanged: (value) =>
                  setState(() => _frequency = value ?? 'instant'),
            ),
            RadioListTile<String>(
              value: 'off',
              groupValue: _frequency,
              title: const Text('حفظ بدون تنبيهات'),
              onChanged: (value) =>
                  setState(() => _frequency = value ?? 'off'),
            ),
            if (_frequency == 'daily')
              const RadioListTile<String>(
                value: 'daily',
                groupValue: 'daily',
                title: Text('ملخص يومي محفوظ سابقًا'),
                subtitle: Text(
                  'هذا الخيار غير متاح لعمليات إنشاء جديدة حاليًا. اختر الفوري أو بدون تنبيهات إذا أردت تغييره.',
                ),
                onChanged: null,
              ),
            const SizedBox(height: AppSpacing.s20),
            AppButton(
              label: _saving
                  ? 'جارٍ الحفظ...'
                  : _editing
                      ? 'حفظ التعديلات'
                      : 'حفظ البحث',
              icon: _frequency == 'instant'
                  ? Icons.notifications_active_outlined
                  : Icons.bookmark_add_outlined,
              loading: _saving,
              onPressed: _saving ? null : _save,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasLocationFilter => const [
        'latitude',
        'longitude',
        'radius_km',
        'south',
        'west',
        'north',
        'east',
      ].any(_baseFilters.containsKey);

  String get _locationSummary {
    final radius = _numberText(_baseFilters['radius_km']);
    if (_baseFilters['latitude'] != null &&
        _baseFilters['longitude'] != null &&
        radius.isNotEmpty) {
      return 'البحث مقيد بنطاق $radius كم حول نقطة محفوظة على الخريطة.';
    }
    if (_baseFilters['south'] != null &&
        _baseFilters['west'] != null &&
        _baseFilters['north'] != null &&
        _baseFilters['east'] != null) {
      return 'البحث مقيد بالمنطقة المحددة عند حفظه من الخريطة.';
    }
    return 'يوجد قيد موقع محفوظ ضمن شروط هذا البحث.';
  }

  void _removeLocationFilter() {
    setState(() {
      for (final key in const [
        'latitude',
        'longitude',
        'radius_km',
        'south',
        'west',
        'north',
        'east',
      ]) {
        _baseFilters.remove(key);
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showMessage('اكتب اسمًا واضحًا للبحث.');
      return;
    }

    final minPriceText = _cleanNumber(_minPrice.text);
    final maxPriceText = _cleanNumber(_maxPrice.text);
    final minBedroomsText = _minBedrooms.text.trim();
    final minBathroomsText = _minBathrooms.text.trim();
    final minAreaText = _cleanNumber(_minArea.text);
    final maxAreaText = _cleanNumber(_maxArea.text);

    final minPrice = double.tryParse(minPriceText);
    final maxPrice = double.tryParse(maxPriceText);
    final minBedrooms = int.tryParse(minBedroomsText);
    final minBathrooms = int.tryParse(minBathroomsText);
    final minArea = double.tryParse(minAreaText);
    final maxArea = double.tryParse(maxAreaText);

    if (minPriceText.isNotEmpty && minPrice == null) {
      _showMessage('أدخل أقل سعر بشكل صحيح.');
      return;
    }
    if (maxPriceText.isNotEmpty && maxPrice == null) {
      _showMessage('أدخل أعلى سعر بشكل صحيح.');
      return;
    }
    if (minBedroomsText.isNotEmpty && minBedrooms == null) {
      _showMessage('أدخل عدد الغرف بشكل صحيح.');
      return;
    }
    if (minBathroomsText.isNotEmpty && minBathrooms == null) {
      _showMessage('أدخل عدد الحمامات بشكل صحيح.');
      return;
    }
    if (minAreaText.isNotEmpty && minArea == null) {
      _showMessage('أدخل أقل مساحة بشكل صحيح.');
      return;
    }
    if (maxAreaText.isNotEmpty && maxArea == null) {
      _showMessage('أدخل أعلى مساحة بشكل صحيح.');
      return;
    }
    if (minPrice != null && maxPrice != null && minPrice > maxPrice) {
      _showMessage('أقل سعر يجب أن يكون أقل من أو يساوي أعلى سعر.');
      return;
    }
    if (minArea != null && maxArea != null && minArea > maxArea) {
      _showMessage('أقل مساحة يجب أن تكون أقل من أو تساوي أعلى مساحة.');
      return;
    }

    final filters = Map<String, dynamic>.from(_baseFilters);
    for (final key in const [
      'purpose',
      'type',
      'search',
      'min_price',
      'max_price',
      'min_bedrooms',
      'min_bathrooms',
      'min_area_m2',
      'max_area_m2',
    ]) {
      filters.remove(key);
    }
    if (_purpose != null) filters['purpose'] = _purpose;
    if (_type != null) filters['type'] = _type;
    if (_keywords.text.trim().isNotEmpty) {
      filters['search'] = _keywords.text.trim();
    }
    if (minPrice != null) filters['min_price'] = minPrice;
    if (maxPrice != null) filters['max_price'] = maxPrice;
    if (minBedrooms != null) filters['min_bedrooms'] = minBedrooms;
    if (minBathrooms != null) filters['min_bathrooms'] = minBathrooms;
    if (minArea != null) filters['min_area_m2'] = minArea;
    if (maxArea != null) filters['max_area_m2'] = maxArea;

    if (filters.isEmpty) {
      _showMessage('حدد شرطًا واحدًا على الأقل حتى يكون البحث مفيدًا.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = ref.read(savedSearchRepositoryProvider);
      final existing = widget.existingSearch;
      if (existing == null) {
        await repository.create(
          name: name,
          filters: filters,
          alertFrequency: _frequency,
        );
      } else {
        await repository.update(
          existing.id,
          name: name,
          filters: filters,
          alertFrequency: _frequency,
        );
      }
      ref.read(savedSearchRevisionProvider.notifier).state++;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _cleanNumber(String value) => value.replaceAll(',', '').trim();

String _numberText(dynamic value) {
  if (value == null) return '';
  final number = value is num ? value : num.tryParse(value.toString());
  if (number == null) return '';
  return number % 1 == 0 ? number.toInt().toString() : number.toString();
}

String _suggestedName(Map<String, dynamic> filters) {
  final parts = <String>[];
  final purpose = _nullable(filters['purpose']);
  final type = _nullable(filters['type']);
  final search = _nullable(filters['search']);
  if (purpose != null) parts.add(purpose == 'rent' ? 'إيجار' : 'شراء');
  if (type != null) parts.add(_typeLabel(type));
  if (search != null) parts.add(search);
  return parts.isEmpty ? '' : parts.join(' • ');
}

String _typeLabel(String type) => switch (type) {
      'apartment' => 'شقة',
      'house' => 'منزل',
      'villa' => 'فيلا',
      'land' => 'أرض',
      'shop' => 'محل',
      'office' => 'مكتب',
      'farm' => 'مزرعة',
      _ => type,
    };
