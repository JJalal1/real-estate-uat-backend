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
import '../domain/arabic_price_words.dart';
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
  final _documentOwnerNameController = TextEditingController();
  final _ownerRelationshipNoteController = TextEditingController();

  int _step = 0;
  String _purpose = 'sale';
  String _type = 'apartment';
  String _areaUnit = 'sqm';
  String? _parkingChoice;
  String? _tenureType;
  String? _buildingFacade;
  double? _latitude;
  double? _longitude;
  bool _resolvingAddress = false;
  bool _addressAutofillAttempted = false;
  bool _submitting = false;
  bool _replaceImages = false;
  List<String> _imagePaths = <String>[];
  List<String> _proofPaths = <String>[];
  String? _ownershipProofPath;
  String? _ownershipDocumentType;
  String? _ownerRelationshipType;

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
    _parkingChoice = property.hasParking == null
        ? null
        : (property.hasParking! ? 'yes' : 'no');
    _tenureType = property.tenureType;
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
    _ownershipDocumentType = property.ownershipDocumentType;
    _documentOwnerNameController.text = property.documentOwnerName ?? '';
    _ownerRelationshipType = property.ownerRelationshipType;
    _ownerRelationshipNoteController.text = property.ownerRelationshipNote ?? '';
  }

  @override
  void dispose() {
    unawaited(
      _mediaPicker.clearTemporaryFiles(<String>[
        ..._imagePaths,
        ..._proofPaths,
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
    _documentOwnerNameController.dispose();
    _ownerRelationshipNoteController.dispose();
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
        if (_requiresSaleTenure) ...[
          const SizedBox(height: 18),
          const Text(
            'نوع ملكية العقار *',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment<String>(value: 'freehold', label: Text('حر')),
              ButtonSegment<String>(value: 'waqf', label: Text('وقف')),
            ],
            selected: _tenureType == null ? <String>{} : <String>{_tenureType!},
            onSelectionChanged: (value) {
              if (value.isNotEmpty) {
                setState(() => _tenureType = value.first);
              }
            },
          ),
          const SizedBox(height: 4),
          Text(
            'يظهر هذا الخيار للعقارات المعروضة للبيع من نوع شقة أو منزل أو فيلا أو أرض أو مزرعة.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment<String>(
                  value: 'yes',
                  label: Text('يوجد'),
                  icon: Icon(Icons.local_parking)),
              ButtonSegment<String>(
                  value: 'no',
                  label: Text('لا يوجد'),
                  icon: Icon(Icons.block)),
            ],
            selected: _parkingChoice == null
                ? <String>{}
                : <String>{_parkingChoice!},
            onSelectionChanged: (value) {
              // Once the user chooses yes/no, do not let a second tap silently
              // clear the required value. This fixes the false "حدد الموقف" error.
              if (value.isNotEmpty) {
                setState(() => _parkingChoice = value.first);
              }
            },
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

  bool get _requiresSaleTenure =>
      _purpose == 'sale' &&
      const {'apartment', 'house', 'villa', 'land', 'farm'}.contains(_type);

  bool? get _parkingValue {
    if (!_requiresStructureDetails || _parkingChoice == null) return null;
    return _parkingChoice == 'yes';
  }

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
          keyboardType: TextInputType.number,
          inputFormatters: const [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'السعر بالريال اليمني',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.payments_outlined),
            helperText: arabicRiyalAmountInWords(_priceController.text),
            helperMaxLines: 2,
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
    final user = ref.watch(authControllerProvider).asData?.value;
    final isOwnerProfile = user?.isOwner == true;
    final isProfessionalAdvertiser = user?.isBroker == true || user?.isOffice == true;
    final existingOwnershipProof = widget.existingProperty?.ownershipProofPresent == true;

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
        if (isProfessionalAdvertiser)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                user?.isOffice == true
                    ? 'حساب مكتب العقارات الموثق لا يرفع مستند ملكية كجزء من توثيق المكتب. الإعلان نفسه سيظل خاضعاً للمراجعة وقواعد منع التكرار.'
                    : 'حساب الدلال الموثق لا يرفع بصائر العقارات عند توثيق حسابه؛ لأنه لا يُعامل كمالك للعقار. الإعلان نفسه سيظل خاضعاً للمراجعة وقواعد منع التكرار.',
              ),
            ),
          )
        else if (isOwnerProfile) ...[
          const Text(
            'إثبات علاقة المالك بهذا العقار',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'هويتك موثقة مرة واحدة في حسابك. هنا نتحقق بشكل مستقل من علاقتك بهذا العقار فقط.',
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _ownershipDocumentType,
            decoration: const InputDecoration(
              labelText: 'نوع مستند العقار',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'purchase_deed', child: Text('بصيرة شراء')),
              DropdownMenuItem(value: 'registry_record', child: Text('سند / قيد سجل عقاري')),
              DropdownMenuItem(value: 'partition_deed', child: Text('فصل قسمة')),
              DropdownMenuItem(value: 'court_judgment', child: Text('حكم قضائي')),
              DropdownMenuItem(value: 'inheritance_document', child: Text('مستند إرث')),
              DropdownMenuItem(value: 'ownership_contract', child: Text('عقد تمليك')),
              DropdownMenuItem(value: 'other', child: Text('مستند آخر مناسب')),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _ownershipDocumentType = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _documentOwnerNameController,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'اسم صاحب الحق كما يظهر في مستند العقار',
              hintText: 'اكتب الاسم الموجود في المستند',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _ownerRelationshipType,
            decoration: const InputDecoration(
              labelText: 'صفتك بالنسبة للعقار',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'owner', child: Text('مالك مباشر')),
              DropdownMenuItem(value: 'agent', child: Text('وكيل')),
              DropdownMenuItem(value: 'heir', child: Text('وارث')),
              DropdownMenuItem(value: 'co_owner', child: Text('شريك في الملكية')),
              DropdownMenuItem(value: 'other', child: Text('صفة أخرى')),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() => _ownerRelationshipType = value),
          ),
          if (_ownerRelationshipType != null &&
              _ownerRelationshipType != 'owner') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _ownerRelationshipNoteController,
              enabled: !_submitting,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: _ownerRelationshipType == 'other'
                    ? 'وضح صفتك وعلاقتك بالعقار'
                    : 'تفاصيل العلاقة أو التفويض (اختياري)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _RequiredDocumentPicker(
            label: 'مستند ملكية / علاقة العقار',
            selected: _ownershipProofPath != null || existingOwnershipProof,
            onTap: () => _pickRequiredDocument('ownership_proof'),
          ),
          if (existingOwnershipProof && _ownershipProofPath == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('يوجد مستند علاقة مرفوع سابقاً لهذا العقار.'),
            ),
          if (_ownerRelationshipType == 'owner')
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'عند اختيار «مالك مباشر» سيقارن النظام الاسم الذي أدخلته من المستند مع الاسم الرباعي في حسابك. إذا لم يتطابق، اختر الصفة الصحيحة مثل وكيل أو وارث أو شريك.',
                ),
              ),
            ),
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
        if (_requiresSaleTenure)
          _ReviewRow(
            label: 'الملكية',
            value: _tenureType == 'waqf' ? 'وقف' : 'حر',
          ),
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
            value: _parkingChoice == 'yes' ? 'يوجد' : 'لا يوجد',
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
                      ? (_isEditing ? 'حفظ وإرسال للمراجعة' : 'نشر الإعلان')
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
    if (step == 0) {
      if (_titleController.text.trim().length < 4) {
        return 'اكتب عنواناً واضحاً من 4 أحرف على الأقل.';
      }
      if (_requiresSaleTenure && _tenureType == null) {
        return 'حدد نوع الملكية: حر أو وقف.';
      }
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
      if (_requiresStructureDetails && _parkingChoice == null) {
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
    if (step == 4) {
      final user = ref.read(authControllerProvider).asData?.value;
      if (user?.isOwner == true) {
        if (_ownershipDocumentType == null) {
          return 'اختر نوع مستند ملكية أو علاقة العقار.';
        }
        if (_documentOwnerNameController.text.trim().length < 3) {
          return 'اكتب اسم صاحب الحق كما يظهر في مستند العقار.';
        }
        if (_ownerRelationshipType == null) {
          return 'حدد صفتك بالنسبة للعقار.';
        }
        if (_ownershipProofPath == null &&
            widget.existingProperty?.ownershipProofPresent != true) {
          return 'ارفع مستند ملكية أو علاقة هذا العقار.';
        }
        if (_ownerRelationshipType == 'owner' &&
            _normalizedName(_documentOwnerNameController.text) !=
                _normalizedName(user!.name)) {
          return 'الاسم في مستند العقار لا يطابق الاسم الرباعي في الحساب. اختر صفتك الصحيحة مثل وكيل أو وارث أو شريك.';
        }
        if (_ownerRelationshipType == 'other' &&
            _ownerRelationshipNoteController.text.trim().length < 3) {
          return 'وضح صفتك أو علاقتك بالعقار.';
        }
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
    if (kind != 'ownership_proof') return;
    try {
      final paths = await _mediaPicker.pickImages();
      if (!mounted || paths.isEmpty) return;
      final selected = paths.first;
      await _mediaPicker.clearTemporaryFiles(paths.skip(1));
      if (!mounted) return;
      final old = _ownershipProofPath;
      setState(() => _ownershipProofPath = selected);
      if (old != null && old != selected) {
        await _mediaPicker.clearTemporaryFiles([old]);
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
    for (var step = 0; step <= 4; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) {
        setState(() => _step = step);
        _showMessage(message);
        return;
      }
    }

    final user = ref.read(authControllerProvider).asData?.value;

    final input = PropertyListingInput(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      purpose: _purpose,
      type: _type,
      tenureType: _requiresSaleTenure ? _tenureType : null,
      price: double.parse(_priceController.text.trim()),
      areaValue: double.parse(_areaController.text.trim()),
      areaUnit: _areaUnit,
      bedrooms: _requiresResidentialDetails
          ? _optionalInt(_bedroomsController)
          : null,
      bathrooms: _requiresResidentialDetails
          ? _optionalInt(_bathroomsController)
          : null,
      hasParking: _parkingValue,
      buildingFacade: _requiresStructureDetails ? _buildingFacade : null,
      address: _composedAddress,
      latitude: _latitude!,
      longitude: _longitude!,
      contactPhone: _phoneController.text.trim(),
      contactWhatsapp: _whatsappController.text.trim(),
      ownershipDocumentType:
          user?.isOwner == true ? _ownershipDocumentType : null,
      documentOwnerName:
          user?.isOwner == true ? _documentOwnerNameController.text.trim() : null,
      ownerRelationshipType:
          user?.isOwner == true ? _ownerRelationshipType : null,
      ownerRelationshipNote: user?.isOwner == true
          ? _ownerRelationshipNoteController.text.trim()
          : null,
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
              submitForReview: true,
              proofPaths: _proofPaths,
              ownershipProofPath: _ownershipProofPath,
            )
          : await repository.createListing(
              input,
              imagePaths: _imagePaths,
              submitForReview: true,
              proofPaths: _proofPaths,
              ownershipProofPath: _ownershipProofPath,
            );

      if (!mounted) {
        return;
      }
      ref.read(propertyDataRevisionProvider.notifier).state++;
      final uploadedPaths = <String>[
        ..._imagePaths,
        ..._proofPaths,
        if (_ownershipProofPath != null) _ownershipProofPath!,
      ];
      _imagePaths = <String>[];
      _proofPaths = <String>[];
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
            ? 'تم حفظ التعديلات وإرسال الإعلان مباشرة إلى فريق المراجعة.'
            : 'تم استلام الإعلان وإرساله مباشرة إلى فريق المراجعة. حالة الإعلان: قيد المراجعة.',
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

  String _normalizedName(String value) {
    var text = value.trim().toLowerCase();
    const replacements = <String, String>{
      'أ': 'ا',
      'إ': 'ا',
      'آ': 'ا',
      'ى': 'ي',
      'ؤ': 'و',
      'ئ': 'ي',
      'ة': 'ه',
    };
    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
    return text.replaceAll(RegExp(r'\s+'), ' ');
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
