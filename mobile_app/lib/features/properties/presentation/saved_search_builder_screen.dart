import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/saved_search_repository.dart';

class SavedSearchBuilderScreen extends ConsumerStatefulWidget {
  const SavedSearchBuilderScreen({
    this.initialFilters = const <String, dynamic>{},
    super.key,
  });

  final Map<String, dynamic> initialFilters;

  @override
  ConsumerState<SavedSearchBuilderScreen> createState() => _SavedSearchBuilderScreenState();
}

class _SavedSearchBuilderScreenState extends ConsumerState<SavedSearchBuilderScreen> {
  late final TextEditingController _name;
  late final TextEditingController _keywords;
  late final TextEditingController _maxPrice;
  late final TextEditingController _minBedrooms;
  String? _purpose;
  String? _type;
  String _frequency = 'instant';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final filters = widget.initialFilters;
    _purpose = _nullable(filters['purpose']);
    _type = _nullable(filters['type']);
    _keywords = TextEditingController(text: _nullable(filters['search']) ?? '');
    _maxPrice = TextEditingController(text: _numberText(filters['max_price']));
    _minBedrooms = TextEditingController(text: _numberText(filters['min_bedrooms']));
    _name = TextEditingController(text: _suggestedName(filters));
  }

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    _maxPrice.dispose();
    _minBedrooms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'حفظ البحث الحالي'),
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
                  Text('خلّ التطبيق يتابع لك', style: Theme.of(context).textTheme.titleLarge),
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
                ButtonSegment(value: 'sale', label: Text('شراء'), icon: Icon(Icons.sell_outlined)),
                ButtonSegment(value: 'rent', label: Text('إيجار'), icon: Icon(Icons.key_outlined)),
              ],
              selected: _purpose == null ? const <String>{} : {_purpose!},
              emptySelectionAllowed: true,
              onSelectionChanged: (value) => setState(() => _purpose = value.isEmpty ? null : value.first),
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
            const SizedBox(height: AppSpacing.s12),
            TextField(
              controller: _maxPrice,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'أعلى سعر (اختياري)',
                suffixText: 'ريال',
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            TextField(
              controller: _minBedrooms,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'أقل عدد غرف (اختياري)'),
            ),
            const SizedBox(height: AppSpacing.s20),
            const AppSectionHeader(
              title: 'التنبيه',
              subtitle: 'التنبيه الفوري يعمل الآن. لن نظهر الملخص اليومي قبل تشغيل جدولة موثوقة له.',
            ),
            const SizedBox(height: AppSpacing.s8),
            RadioListTile<String>(
              value: 'instant',
              groupValue: _frequency,
              title: const Text('تنبيه فوري'),
              subtitle: const Text('عند نشر عقار جديد يطابق البحث.'),
              onChanged: (value) => setState(() => _frequency = value ?? 'instant'),
            ),
            RadioListTile<String>(
              value: 'off',
              groupValue: _frequency,
              title: const Text('حفظ بدون تنبيهات'),
              onChanged: (value) => setState(() => _frequency = value ?? 'off'),
            ),
            const SizedBox(height: AppSpacing.s20),
            AppButton(
              label: _saving ? 'جارٍ الحفظ...' : 'حفظ البحث',
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

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسمًا واضحًا للبحث.')),
      );
      return;
    }
    final filters = <String, dynamic>{
      ...widget.initialFilters,
      if (_purpose != null) 'purpose': _purpose,
      if (_type != null) 'type': _type,
      if (_keywords.text.trim().isNotEmpty) 'search': _keywords.text.trim(),
      if (double.tryParse(_maxPrice.text.replaceAll(',', '').trim()) != null)
        'max_price': double.parse(_maxPrice.text.replaceAll(',', '').trim()),
      if (int.tryParse(_minBedrooms.text.trim()) != null)
        'min_bedrooms': int.parse(_minBedrooms.text.trim()),
    };
    if (_purpose == null) filters.remove('purpose');
    if (_type == null) filters.remove('type');
    if (_keywords.text.trim().isEmpty) filters.remove('search');
    if (_maxPrice.text.trim().isEmpty) filters.remove('max_price');
    if (_minBedrooms.text.trim().isEmpty) filters.remove('min_bedrooms');

    if (filters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد شرطًا واحدًا على الأقل حتى يكون البحث مفيدًا.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(savedSearchRepositoryProvider).create(
            name: name,
            filters: filters,
            alertFrequency: _frequency,
          );
      ref.read(savedSearchRevisionProvider.notifier).state++;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String? _nullable(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

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
