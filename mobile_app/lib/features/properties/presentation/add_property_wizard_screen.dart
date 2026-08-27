import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../account/data/auth_controller.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_location_address.dart';
import 'property_location_picker_screen.dart';

class AddPropertyWizardScreen extends ConsumerStatefulWidget {
  const AddPropertyWizardScreen({
    super.key,
    this.existingProperty,
  });

  final PropertyDetails? existingProperty;

  @override
  ConsumerState<AddPropertyWizardScreen> createState() =>
      _AddPropertyWizardScreenState();
}

class _AddPropertyWizardScreenState
    extends ConsumerState<AddPropertyWizardScreen> {
  final _mediaPicker = const Stage5MediaPicker();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _areaController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _bathroomsController = TextEditingController();
  final _governorateController = TextEditingController();
  final _districtController = TextEditingController();
  final _streetController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();

  int _step = 0;
  String _purpose = 'sale';
  String _type = 'apartment';
  String _areaUnit = 'sqm';
  bool? _hasParking;
  String? _buildingFacade;
  double? _latitude;
  double? _longitude;
  bool _resolvingAddress = false;
  bool _addressAutofillAttempted = false;
  bool _submitting = false;
  bool _replaceImages = false;
  List<String> _imagePaths = <String>[];
  List<String> _proofPaths = <String>[];
  String? _ownerIdFrontPath;
  String? _ownerIdBackPath;
  String? _ownerSelfiePath;
  String? _ownershipProofPath;

  bool get _isEditing => widget.existingProperty != null;

  @override
  void initState() {
    super.initState();
    final property = widget.existingProperty;
    if (property == null) {
      return;
    }

    _purpose = property.purpose;
    _type = property.type;
    _titleController.text = property.title;
    _descriptionController.text = property.description ?? '';
    _priceController.text = property.price.toStringAsFixed(0);
    _areaController.text = property.areaValue != null
        ? formatPropertyAreaValue(property.areaValue!)
        : property.areaM2?.toString() ?? '';
    _areaUnit = property.areaUnit ?? 'sqm';
    _hasParking = property.hasParking;
    _buildingFacade = property.buildingFacade;
    _bedroomsController.text = property.bedrooms?.toString() ?? '';
    _bathroomsController.text = property.bathrooms?.toString() ?? '';
    final storedAddress =
        PropertyLocationAddress.fromStoredAddress(property.address);
    _governorateController.text = storedAddress.governorate ?? '';
    _districtController.text = storedAddress.district ?? '';
    _streetController.text = storedAddress.street ?? '';
    _latitude = property.latitude;
    _longitude = property.longitude;
    _phoneController.text = property.contactPhone ?? '';
    _whatsappController.text = property.contactWhatsapp ?? '';
  }

  @override
  void dispose() {
    unawaited(
      _mediaPicker.clearTemporaryFiles(<String>[
        ..._imagePaths,
        ..._proofPaths,
        if (_ownerIdFrontPath != null) _ownerIdFrontPath!,
        if (_ownerIdBackPath != null) _ownerIdBackPath!,
        if (_ownerSelfiePath != null) _ownerSelfiePath!,
        if (_ownershipProofPath != null) _ownershipProofPath!,
      ]).catchError((_) {}),
    );
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _areaController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    _governorateController.dispose();
    _districtController.dispose();
    _streetController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'تعديل العقار' : 'إضافة عقار'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              _ProgressHeader(step: _step),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _stepBasics();
      case 1:
        return _stepLocation();
      case 2:
        return _stepSpecifications();
      case 3:
        return _stepPriceAndContact();
      default:
        return _stepImagesAndReview();
    }
  }

  Widget _stepBasics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          title: 'نوع الإعلان والعقار',
          subtitle: 'اختر الغرض والنوع ثم اكتب عنواناً واضحاً للإعلان.',
        ),
        const SizedBox(height: 20),
        const Text('الغرض', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'sale', label: Text('للبيع')),
            ButtonSegment(value: 'rent', label: Text('للإيجار')),
          ],
          selected: {_purpose},
          onSelectionChanged: (value) => setState(() => _purpose = value.first),
        ),
        const SizedBox(height: 18),
        const Text('نوع العقار', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _types.entries
              .map(
                (entry) => ChoiceChip(
                  label: Text(entry.value),
                  selected: _type == entry.key,
                  onSelected: (_) => setState(() => _type = entry.key),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleController,
          maxLength: 160,
          decoration: const InputDecoration(
            labelText: 'عنوان الإعلان',
            hintText: 'مثال: شقة واسعة في حي حدة',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _stepLocation() {
    final hasLocation = _latitude != null && _longitude != null;
    final hasAnyAddress = _governorateController.text.trim().isNotEmpty ||
        _districtController.text.trim().isNotEmpty ||
        _streetController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          title: 'موقع العقار',
          subtitle:
              'حدد الموقع أولاً. بعد الاختيار سيعبئ البرنامج المحافظة والحي والشارع تلقائياً، وبعدها يمكنك تعديلها إذا رغبت.',
        ),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hasLocation
                ? const Color(0xFFEAF7F0)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasLocation
                  ? const Color(0xFF2E7D32)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasLocation
                    ? Icons.check_circle_outline
                    : Icons.location_searching,
                color: hasLocation ? const Color(0xFF2E7D32) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasLocation
                      ? 'تم تحديد نقطة العقار. معلومات العنوان أدناه يتم جلبها تلقائياً من هذه النقطة.'
                      : 'اختر موقع العقار من الخريطة أو استخدم موقعك الحالي. لا تحتاج لكتابة العنوان قبل اختيار الموقع.',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _resolvingAddress ? null : _selectLocationOnMap,
            icon: const Icon(Icons.location_on_rounded),
            label: const Text('تحديد الموقع على الخريطة'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _resolvingAddress ? null : _useCurrentLocation,
            icon: const Icon(Icons.my_location),
            label: const Text('استخدام موقعي الحالي'),
          ),
        ),
        if (_resolvingAddress) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'جارٍ تعبئة المحافظة والحي والشارع تلقائياً…',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'بيانات العنوان',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          hasLocation
              ? 'هذه القيم يعبئها البرنامج من الموقع المحدد. يمكنك تعديلها يدوياً فقط إذا احتجت.'
              : 'ستتفعّل هذه الحقول وتُملأ تلقائياً بعد تحديد الموقع.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _governorateController,
          readOnly: !hasLocation || _resolvingAddress,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'المحافظة *',
            hintText: hasLocation
                ? 'جارٍ تحديد المحافظة من الموقع…'
                : 'تُعبأ تلقائياً بعد تحديد الموقع',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.account_balance_outlined),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _districtController,
          readOnly: !hasLocation || _resolvingAddress,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'المنطقة / الحي',
            hintText: hasLocation
                ? 'جارٍ تحديد الحي من الموقع…'
                : 'يُعبأ تلقائياً بعد تحديد الموقع',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.location_city_outlined),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _streetController,
          readOnly: !hasLocation || _resolvingAddress,
          maxLength: 160,
          decoration: InputDecoration(
            labelText: 'الشارع',
            hintText: hasLocation
                ? 'جارٍ تحديد الشارع من الموقع…'
                : 'يُعبأ تلقائياً بعد تحديد الموقع',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.route_outlined),
          ),
        ),
        if (hasLocation && _addressAutofillAttempted && !hasAnyAddress) ...[
          const SizedBox(height: 4),
          const Text(
            'تعذر جلب العنوان تلقائياً من مزود الخرائط في المحاولة السابقة.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
        if (hasLocation && !_resolvingAddress) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _retryAddressAutofill,
              icon: const Icon(Icons.autorenew_rounded),
              label: const Text('إعادة تعبئة العنوان تلقائياً'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepSpecifications() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          title: 'مواصفات العقار',
          subtitle:
              'الحقول المطلوبة تتغير حسب نوع العقار حتى لا نطلب معلومات غير مناسبة.',
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _areaController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'المساحة *',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _areaUnit,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'وحدة القياس *',
                  border: OutlineInputBorder(),
                ),
                items: propertyAreaUnitLabels.entries
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child:
                            Text(entry.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _areaUnit = value);
                },
              ),
            ),
          ],
        ),
        if (_requiresResidentialDetails) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bedroomsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'غرف النوم *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _bathroomsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الحمامات *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_requiresStructureDetails) ...[
          const SizedBox(height: 18),
          const Text('هل يوجد موقف سيارة؟ *',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment<bool>(
                  value: true,
                  label: Text('يوجد'),
                  icon: Icon(Icons.local_parking)),
              ButtonSegment<bool>(
                  value: false,
                  label: Text('لا يوجد'),
                  icon: Icon(Icons.block)),
            ],
            selected: _hasParking == null ? <bool>{} : <bool>{_hasParking!},
            onSelectionChanged: (value) => setState(
                () => _hasParking = value.isEmpty ? null : value.first),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _buildingFacade,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'واجهة البناء *',
              border: OutlineInputBorder(),
            ),
            hint: const Text('اختر الواجهة'),
            items: propertyFacadeLabels.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _buildingFacade = value),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _descriptionController,
          minLines: 5,
          maxLines: 8,
          maxLength: 5000,
          decoration: const InputDecoration(
            labelText: 'وصف العقار',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  bool get _requiresResidentialDetails =>
      const {'apartment', 'house', 'villa'}.contains(_type);

  bool get _requiresStructureDetails =>
      const {'apartment', 'house', 'villa', 'shop', 'office'}.contains(_type);

  Widget _stepPriceAndContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          title: 'السعر والتواصل',
          subtitle:
              'السعر مطلوب، أما أرقام التواصل فهي اختيارية لأن المراسلة داخل التطبيق متاحة.',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'السعر بالريال اليمني',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف (اختياري)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _whatsappController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم واتساب (اختياري)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.chat_outlined),
          ),
        ),
      ],
    );
  }

  Widget _stepImagesAndReview() {
    final existingCount = widget.existingProperty?.images.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          title: 'الصور والمراجعة',
          subtitle: 'يمكن اختيار حتى 12 صورة. أول صورة ستكون الصورة الرئيسية.',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _imagePaths.isEmpty
                  ? 'اختيار الصور'
                  : 'تم اختيار ${_imagePaths.length} صورة',
            ),
          ),
        ),
        if (_isEditing && existingCount > 0) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _replaceImages,
            contentPadding: EdgeInsets.zero,
            title: Text(
              _imagePaths.isEmpty
                  ? 'حذف جميع الصور الحالية'
                  : 'استبدال الصور القديمة بالصور المختارة',
            ),
            subtitle: Text('الصور الحالية: $existingCount'),
            onChanged: (value) =>
                setState(() => _replaceImages = value ?? false),
          ),
        ],
        const SizedBox(height: 18),
        if (ref.watch(authControllerProvider).asData?.value?.isBroker == true)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'حساب الدلال الموثق لا يحتاج رفع إثبات ملكية لكل إعلان. يمكنه نشر أي عقار غير منشور مسبقاً، ويظل الإعلان خاضعاً لمراجعة الدعم.'),
            ),
          )
        else ...[
          const Text(
            'إثبات هوية المالك وملكية العقار',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('هذه الصور خاصة بفريق الدعم ولا تظهر للعامة.'),
          const SizedBox(height: 8),
          _RequiredDocumentPicker(
              label: 'صورة البطاقة الأمامية',
              selected: _ownerIdFrontPath != null,
              onTap: () => _pickRequiredDocument('owner_id_front')),
          _RequiredDocumentPicker(
              label: 'صورة البطاقة الخلفية',
              selected: _ownerIdBackPath != null,
              onTap: () => _pickRequiredDocument('owner_id_back')),
          _RequiredDocumentPicker(
              label: 'صورة سلفي لصاحب العقار',
              selected: _ownerSelfiePath != null,
              onTap: () => _pickRequiredDocument('owner_selfie')),
          _RequiredDocumentPicker(
              label: 'ما يثبت ملكية العقار',
              selected: _ownershipProofPath != null,
              onTap: () => _pickRequiredDocument('ownership_proof')),
        ],
        if (_imagePaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SizedBox.square(
                dimension: 104,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(_imagePaths[index]),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFE7F5F1),
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: IconButton.filled(
                        tooltip: 'إزالة الصورة',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeImageAt(index),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        _ReviewRow(label: 'العنوان', value: _titleController.text.trim()),
        _ReviewRow(
            label: 'الغرض', value: _purpose == 'sale' ? 'للبيع' : 'للإيجار'),
        _ReviewRow(label: 'النوع', value: _types[_type] ?? _type),
        _ReviewRow(
            label: 'السعر', value: '${_priceController.text.trim()} YER'),
        _ReviewRow(label: 'الموقع', value: _composedAddress),
        _ReviewRow(
          label: 'المساحة',
          value:
              '${_areaController.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}',
        ),
        if (_requiresStructureDetails)
          _ReviewRow(
            label: 'الموقف',
            value: _hasParking == true ? 'يوجد' : 'لا يوجد',
          ),
        if (_requiresStructureDetails)
          _ReviewRow(
            label: 'الواجهة',
            value: propertyFacadeLabel(_buildingFacade),
          ),
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => setState(() => _step--),
                child: const Text('السابق'),
              ),
            ),
          if (_step > 0) const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _submitting
                  ? null
                  : _step == 4
                      ? _submit
                      : _next,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_step == 4
                      ? (_isEditing ? 'حفظ التعديلات' : 'نشر الإعلان')
                      : 'التالي'),
            ),
          ),
        ],
      ),
    );
  }

  void _next() {
    final message = _validationMessageForStep(_step);
    if (message != null) {
      _showMessage(message);
      return;
    }
    setState(() => _step++);
  }

  String? _validationMessageForStep(int step) {
    if (step == 0 && _titleController.text.trim().length < 4) {
      return 'اكتب عنواناً واضحاً من 4 أحرف على الأقل.';
    }
    if (step == 1) {
      if (_governorateController.text.trim().length < 2) {
        return 'اكتب اسم المحافظة أو حدده من الخريطة.';
      }
      if (_composedAddress.length < 3) {
        return 'أكمل معلومات موقع العقار.';
      }
      if (_latitude == null || _longitude == null) {
        return 'حدد موقع العقار باستخدام موقعك الحالي أو الخريطة.';
      }
    }
    if (step == 2) {
      final area = double.tryParse(_areaController.text.trim());
      if (area == null || area <= 0) {
        return 'أدخل مساحة صحيحة للعقار.';
      }
      if (_requiresResidentialDetails) {
        final bedrooms = _optionalInt(_bedroomsController);
        final bathrooms = _optionalInt(_bathroomsController);
        if (bedrooms == null || bedrooms < 1) {
          return 'أدخل عدد غرف النوم.';
        }
        if (bathrooms == null || bathrooms < 1) {
          return 'أدخل عدد الحمامات.';
        }
      }
      if (_requiresStructureDetails && _hasParking == null) {
        return 'حدد هل يوجد موقف سيارة أم لا.';
      }
      if (_requiresStructureDetails && _buildingFacade == null) {
        return 'اختر واجهة البناء.';
      }
    }
    if (step == 3) {
      final price = double.tryParse(_priceController.text.trim());
      if (price == null || price <= 0) {
        return 'أدخل سعراً صحيحاً.';
      }
    }
    return null;
  }

  Future<void> _useCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        final openSettings = await _showLocationSettingsDialog();
        if (openSettings == true) {
          await Geolocator.openLocationSettings();
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        final openSettings = await _showAppLocationPermissionDialog();
        if (openSettings == true) {
          await Geolocator.openAppSettings();
        }
        return;
      }
      if (permission == LocationPermission.denied) {
        _showMessage(
          'لم يتم منح إذن الموقع. يمكنك تحديد موقع العقار على الخريطة بدلاً من ذلك.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      await _resolveAndFillAddress(
        position.latitude,
        position.longitude,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _resolvingAddress = false);
      }
      _showMessage('تعذر الحصول على الموقع الحالي. يمكنك تحديده على الخريطة.');
    }
  }

  Future<bool?> _showLocationSettingsDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('خدمة الموقع غير مفعلة'),
        content: const Text(
          'لاستخدام موقعك الحالي، فعّل خدمة الموقع في الهاتف. يمكنك أيضاً اختيار موقع العقار يدوياً على الخريطة دون تشغيل GPS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ليس الآن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('فتح إعدادات الموقع'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showAppLocationPermissionDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إذن الموقع متوقف'),
        content: const Text(
          'تم منع إذن الموقع لهذا التطبيق من إعدادات الهاتف. افتح إعدادات التطبيق للسماح بالموقع، أو حدد موقع العقار على الخريطة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ليس الآن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('فتح إعدادات التطبيق'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectLocationOnMap() async {
    final selection =
        await Navigator.of(context).push<PropertyLocationSelection>(
      MaterialPageRoute<PropertyLocationSelection>(
        builder: (_) => PropertyLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          reverseLookup: (latitude, longitude) =>
              ref.read(propertyRepositoryProvider).resolveLocationAddress(
                    latitude: latitude,
                    longitude: longitude,
                  ),
        ),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _latitude = selection.latitude;
      _longitude = selection.longitude;
    });
    await _resolveAndFillAddress(
      selection.latitude,
      selection.longitude,
      initial: selection.address,
    );
  }

  Future<void> _retryAddressAutofill() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) return;
    await _resolveAndFillAddress(latitude, longitude);
  }

  Future<void> _resolveAndFillAddress(
    double latitude,
    double longitude, {
    PropertyLocationAddress initial = const PropertyLocationAddress(),
  }) async {
    if (!mounted) return;
    setState(() {
      _resolvingAddress = true;
      _addressAutofillAttempted = true;
    });

    var address = initial;
    if (!address.isComplete) {
      final resolved = await _resolveAddress(latitude, longitude);
      address = resolved.mergeFallback(address);
    }
    if (address.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final retry = await _resolveAddress(latitude, longitude);
      address = retry.mergeFallback(address);
    }

    if (!mounted) return;
    _applyResolvedAddress(address, replaceAll: true);
    setState(() => _resolvingAddress = false);

    if (address.isComplete) {
      _showMessage(
        'تم تحديد الموقع وتعبئة المحافظة والحي والشارع تلقائياً. يمكنك تعديلها إذا رغبت.',
      );
    } else if (!address.isEmpty) {
      _showMessage(
        'تم تعبئة معلومات العنوان التي وجدها البرنامج تلقائياً. يمكنك إعادة المحاولة أو تعديل أي جزء عند الحاجة.',
      );
    } else {
      _showMessage(
        'تم تثبيت الموقع، لكن مزود العناوين لم يرجع بيانات الآن. اضغط إعادة تعبئة العنوان تلقائياً للمحاولة مرة أخرى.',
      );
    }
  }

  Future<PropertyLocationAddress> _resolveAddress(
    double latitude,
    double longitude,
  ) async {
    try {
      return await ref.read(propertyRepositoryProvider).resolveLocationAddress(
            latitude: latitude,
            longitude: longitude,
          );
    } catch (_) {
      return const PropertyLocationAddress();
    }
  }

  void _applyResolvedAddress(
    PropertyLocationAddress address, {
    bool replaceAll = false,
  }) {
    if (!mounted) return;
    setState(() {
      if (replaceAll || address.governorate != null) {
        _governorateController.text = address.governorate ?? '';
      }
      if (replaceAll || address.district != null) {
        _districtController.text = address.district ?? '';
      }
      if (replaceAll || address.street != null) {
        _streetController.text = address.street ?? '';
      }
    });
  }

  String get _composedAddress => PropertyLocationAddress(
        governorate: _governorateController.text,
        district: _districtController.text,
        street: _streetController.text,
      ).combined;

  Future<void> _pickImages() async {
    try {
      final paths = await _mediaPicker.pickImages();
      if (!mounted || paths.isEmpty) {
        return;
      }

      final selected =
          <String>{..._imagePaths, ...paths}.take(12).toList(growable: false);
      final discarded = paths.where((path) => !selected.contains(path));
      await _mediaPicker.clearTemporaryFiles(discarded);
      if (!mounted) {
        return;
      }

      setState(() {
        _imagePaths = selected;
        if (_isEditing) {
          _replaceImages = true;
        }
      });
    } on PlatformException catch (_) {
      _showMessage('تعذر فتح معرض الصور على هذا الجهاز.');
    } catch (_) {
      _showMessage('تعذر اختيار الصور.');
    }
  }

  Future<void> _pickRequiredDocument(String kind) async {
    try {
      final paths = await _mediaPicker.pickImages();
      if (!mounted || paths.isEmpty) return;
      final selected = paths.first;
      await _mediaPicker.clearTemporaryFiles(paths.skip(1));
      if (!mounted) return;
      String? old;
      setState(() {
        switch (kind) {
          case 'owner_id_front':
            old = _ownerIdFrontPath;
            _ownerIdFrontPath = selected;
            break;
          case 'owner_id_back':
            old = _ownerIdBackPath;
            _ownerIdBackPath = selected;
            break;
          case 'owner_selfie':
            old = _ownerSelfiePath;
            _ownerSelfiePath = selected;
            break;
          case 'ownership_proof':
            old = _ownershipProofPath;
            _ownershipProofPath = selected;
            break;
        }
      });
      if (old != null && old != selected) {
        await _mediaPicker.clearTemporaryFiles([old!]);
      }
    } on PlatformException {
      _showMessage('تعذر فتح معرض الصور لاختيار المستند.');
    } catch (_) {
      _showMessage('تعذر اختيار المستند.');
    }
  }

  Future<void> _removeImageAt(int index) async {
    if (index < 0 || index >= _imagePaths.length) {
      return;
    }
    final path = _imagePaths[index];
    setState(() => _imagePaths = List<String>.of(_imagePaths)..removeAt(index));
    try {
      await _mediaPicker.clearTemporaryFiles([path]);
    } catch (_) {
      // The operating system will eventually clear its cache directory.
    }
  }

  Future<void> _submit() async {
    for (var step = 0; step <= 3; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) {
        setState(() => _step = step);
        _showMessage(message);
        return;
      }
    }

    final user = ref.read(authControllerProvider).asData?.value;
    if (!_isEditing &&
        user?.isRegular == true &&
        (_ownerIdFrontPath == null ||
            _ownerIdBackPath == null ||
            _ownerSelfiePath == null ||
            _ownershipProofPath == null)) {
      setState(() => _step = 4);
      _showMessage(
          'يلزم رفع صورة البطاقة الأمامية والخلفية وصورة سلفي وما يثبت ملكية العقار.');
      return;
    }

    final input = PropertyListingInput(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      purpose: _purpose,
      type: _type,
      price: double.parse(_priceController.text.trim()),
      areaValue: double.parse(_areaController.text.trim()),
      areaUnit: _areaUnit,
      bedrooms: _requiresResidentialDetails
          ? _optionalInt(_bedroomsController)
          : null,
      bathrooms: _requiresResidentialDetails
          ? _optionalInt(_bathroomsController)
          : null,
      hasParking: _requiresStructureDetails ? _hasParking : null,
      buildingFacade: _requiresStructureDetails ? _buildingFacade : null,
      address: _composedAddress,
      latitude: _latitude!,
      longitude: _longitude!,
      contactPhone: _phoneController.text.trim(),
      contactWhatsapp: _whatsappController.text.trim(),
    );

    setState(() => _submitting = true);
    try {
      final repository = ref.read(propertyRepositoryProvider);
      final property = _isEditing
          ? await repository.updateListing(
              widget.existingProperty!.id,
              input,
              imagePaths: _imagePaths,
              replaceImages: _replaceImages,
              proofPaths: _proofPaths,
              ownerIdFrontPath: _ownerIdFrontPath,
              ownerIdBackPath: _ownerIdBackPath,
              ownerSelfiePath: _ownerSelfiePath,
              ownershipProofPath: _ownershipProofPath,
            )
          : await repository.createListing(
              input,
              imagePaths: _imagePaths,
              proofPaths: _proofPaths,
              ownerIdFrontPath: _ownerIdFrontPath,
              ownerIdBackPath: _ownerIdBackPath,
              ownerSelfiePath: _ownerSelfiePath,
              ownershipProofPath: _ownershipProofPath,
            );

      if (!mounted) {
        return;
      }
      ref.read(propertyDataRevisionProvider.notifier).state++;
      final uploadedPaths = <String>[
        ..._imagePaths,
        ..._proofPaths,
        if (_ownerIdFrontPath != null) _ownerIdFrontPath!,
        if (_ownerIdBackPath != null) _ownerIdBackPath!,
        if (_ownerSelfiePath != null) _ownerSelfiePath!,
        if (_ownershipProofPath != null) _ownershipProofPath!,
      ];
      _imagePaths = <String>[];
      _proofPaths = <String>[];
      _ownerIdFrontPath = null;
      _ownerIdBackPath = null;
      _ownerSelfiePath = null;
      _ownershipProofPath = null;
      try {
        await _mediaPicker.clearTemporaryFiles(uploadedPaths);
      } catch (_) {
        // Upload succeeded; cache cleanup must not turn success into failure.
      }
      if (!mounted) {
        return;
      }
      _showMessage(
        _isEditing
            ? 'تم حفظ التعديلات كمسودة وتحتاج إعادة إرسال للمراجعة.'
            : 'تم حفظ الإعلان كمسودة. أرسله للمراجعة من شاشة إعلاناتي.',
      );
      if (_isEditing) {
        Navigator.of(context).pop(property);
      } else {
        context.go('/properties/${property.id}');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(friendlyApiError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  int? _optionalInt(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) {
      return null;
    }
    return int.tryParse(text);
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('الخطوة ${step + 1} من 5'),
              const Spacer(),
              Text('${((step + 1) * 20)}%'),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(value: (step + 1) / 5),
        ],
      ),
    );
  }
}

class _RequiredDocumentPicker extends StatelessWidget {
  const _RequiredDocumentPicker(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(selected
              ? Icons.check_circle_outline
              : Icons.add_photo_alternate_outlined),
          title:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(selected ? 'تم اختيار الصورة' : 'اضغط لاختيار الصورة'),
          trailing: const Icon(Icons.chevron_left),
          onTap: onTap,
        ),
      );
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

const _types = <String, String>{
  'apartment': 'شقة',
  'house': 'منزل',
  'villa': 'فيلا',
  'land': 'أرض',
  'shop': 'محل',
  'office': 'مكتب',
  'farm': 'مزرعة',
};
