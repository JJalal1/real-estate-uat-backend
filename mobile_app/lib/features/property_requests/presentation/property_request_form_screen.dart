import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/domain/yemen_admin_divisions.dart';
import '../data/property_request_repository.dart';
import '../domain/property_request_models.dart';

class PropertyRequestFormScreen extends ConsumerStatefulWidget {
  const PropertyRequestFormScreen({super.key, this.request});

  final PropertyRequestModel? request;

  @override
  ConsumerState<PropertyRequestFormScreen> createState() => _State();
}

class _State extends ConsumerState<PropertyRequestFormScreen> {
  final _form = GlobalKey<FormState>();
  late String operation;
  late String type;
  late String governorate;
  String? district;
  late final Map<String, TextEditingController> controllers;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    operation = request?.operationType ?? 'sale';
    type = request?.propertyType ?? 'apartment';
    governorate = YemenAdminDivisions.districtsByGovernorate
            .containsKey(request?.governorate)
        ? request!.governorate
        : YemenAdminDivisions.districtsByGovernorate.keys.first;
    final districts = YemenAdminDivisions.districtsByGovernorate[governorate]!;
    district = districts.contains(request?.district) ? request?.district : null;
    controllers = {
      'area': TextEditingController(text: request?.area),
      'budget_min': TextEditingController(text: request?.budgetMin.toString()),
      'budget_max': TextEditingController(text: request?.budgetMax.toString()),
      'requested_area_min':
          TextEditingController(text: request?.requestedAreaMin?.toString()),
      'requested_area_max':
          TextEditingController(text: request?.requestedAreaMax?.toString()),
      'rooms': TextEditingController(text: request?.rooms?.toString()),
      'additional_specifications':
          TextEditingController(text: request?.additionalSpecifications),
      'active_duration_days':
          TextEditingController(text: (request?.activeDurationDays ?? 30).toString()),
    };
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final districts = YemenAdminDivisions.districtsByGovernorate[governorate]!;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.request == null ? 'طلب عقار جديد' : 'تعديل الطلب'),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: operation,
                decoration: const InputDecoration(labelText: 'نوع العملية'),
                items: const [
                  DropdownMenuItem(value: 'sale', child: Text('شراء')),
                  DropdownMenuItem(value: 'rent', child: Text('إيجار')),
                ],
                onChanged: (value) => setState(() => operation = value!),
              ),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'نوع العقار'),
                items: const ['apartment', 'house', 'villa', 'land', 'shop', 'office', 'farm']
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setState(() => type = value!),
              ),
              DropdownButtonFormField<String>(
                value: governorate,
                decoration: const InputDecoration(labelText: 'المحافظة'),
                items: YemenAdminDivisions.districtsByGovernorate.keys
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setState(() {
                  governorate = value!;
                  district = null;
                }),
              ),
              DropdownButtonFormField<String>(
                value: district,
                decoration: const InputDecoration(labelText: 'المديرية'),
                items: districts
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setState(() => district = value),
              ),
              for (final key in const [
                'area',
                'budget_min',
                'budget_max',
                'requested_area_min',
                'requested_area_max',
                'rooms',
                'additional_specifications',
                'active_duration_days',
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: controllers[key],
                    keyboardType: _numericKeys.contains(key) ? TextInputType.number : null,
                    maxLines: key == 'additional_specifications' ? 3 : 1,
                    decoration: InputDecoration(
                      labelText: _label(key),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => _validate(key, value),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ الطلب'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _numericKeys = {
    'budget_min', 'budget_max', 'requested_area_min', 'requested_area_max',
    'rooms', 'active_duration_days',
  };

  String? _validate(String key, String? value) {
    if (['budget_min', 'budget_max', 'active_duration_days'].contains(key)
        && (value == null || value.trim().isEmpty)) return 'مطلوب';
    if (_numericKeys.contains(key) && value?.trim().isNotEmpty == true
        && num.tryParse(value!.trim()) == null) return 'أدخل رقمًا صحيحًا';
    if (key == 'budget_max' && _double('budget_max') != null
        && _double('budget_min') != null
        && _double('budget_max')! < _double('budget_min')!) return 'يجب ألا تقل عن الحد الأدنى';
    if (key == 'requested_area_max' && _number('requested_area_max') != null
        && _number('requested_area_min') != null
        && _number('requested_area_max')! < _number('requested_area_min')!) return 'يجب ألا تقل عن الحد الأدنى';
    return null;
  }

  String _label(String key) => const {
        'area': 'المنطقة', 'budget_min': 'الميزانية الدنيا',
        'budget_max': 'الميزانية العليا', 'requested_area_min': 'المساحة الدنيا (م²)',
        'requested_area_max': 'المساحة العليا (م²)', 'rooms': 'الغرف',
        'additional_specifications': 'مواصفات إضافية',
        'active_duration_days': 'مدة النشاط بالأيام',
      }[key]!;

  int? _number(String key) => int.tryParse(controllers[key]!.text.trim());
  double? _double(String key) => double.tryParse(controllers[key]!.text.trim());
  String? _text(String key) {
    final value = controllers[key]!.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final data = {
        'operation_type': operation, 'property_type': type,
        'governorate': governorate, 'district': district,
        'area': _text('area'), 'budget_min': _double('budget_min'),
        'budget_max': _double('budget_max'), 'currency': 'YER',
        'requested_area_min': _number('requested_area_min'),
        'requested_area_max': _number('requested_area_max'),
        'rooms': _number('rooms'),
        'additional_specifications': _text('additional_specifications'),
        'active_duration_days': _number('active_duration_days'),
      };
      final repository = ref.read(propertyRequestRepositoryProvider);
      if (widget.request == null) {
        await repository.create(data);
      } else {
        await repository.update(widget.request!.id, data);
      }
      ref.invalidate(myPropertyRequestsProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
