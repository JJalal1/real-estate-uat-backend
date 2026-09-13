import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/property_repository.dart';
import '../domain/arabic_price_words.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_location_address.dart';
import '../domain/property_sai.dart';
import 'property_location_picker_screen.dart';
import 'property_sai_configuration_sheet.dart';

class ListingEditorScreen extends ConsumerStatefulWidget {
  const ListingEditorScreen({super.key, this.existingProperty});

  final PropertyDetails? existingProperty;

  @override
  ConsumerState<ListingEditorScreen> createState() =>
      _ListingEditorScreenState();
}

class _ListingEditorScreenState extends ConsumerState<ListingEditorScreen> {
  static const _typeLabels = <String, String>{
    'apartment': 'شقة',
    'house': 'منزل',
    'villa': 'فيلا',
    'land': 'أرض',
    'shop': 'محل',
    'office': 'مكتب',
    'farm': 'مزرعة',
  };
  static const _saleTenureTypes = <String>{
    'apartment',
    'house',
    'villa',
    'land',
    'farm',
  };
  static const _residentialTypes = <String>{'apartment', 'house', 'villa'};
  static const _structureTypes = <String>{
    'apartment',
    'house',
    'villa',
    'shop',
    'office',
  };
  static const _ownershipDocumentTypes = <String, String>{
    'purchase_deed': 'بصيرة شراء',
    'registry_record': 'سند / قيد سجل عقاري',
    'partition_deed': 'فصل قسمة',
    'court_judgment': 'حكم قضائي',
    'inheritance_document': 'مستند إرث',
    'ownership_contract': 'عقد تمليك',
    'other': 'مستند آخر مناسب',
  };
  static const _relationshipTypes = <String, String>{
    'owner': 'مالك مباشر',
    'agent': 'وكيل',
    'heir': 'وارث',
    'co_owner': 'شريك في الملكية',
    'other': 'صفة أخرى',
  };

  final _mediaPicker = const Stage5MediaPicker();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _monthlyRent = TextEditingController();
  final _rentalTermMonths = TextEditingController();
  final _advanceMonths = TextEditingController();
  final _area = TextEditingController();
  final _bedrooms = TextEditingController();
  final _bathrooms = TextEditingController();
  final _governorate = TextEditingController();
  final _district = TextEditingController();
  final _street = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _documentOwnerName = TextEditingController();
  final _relationshipNote = TextEditingController();

  int _step = 0;
  String _purpose = 'sale';
  String _type = 'apartment';
  String _areaUnit = 'sqm';
  String? _tenureType;
  String? _parkingChoice;
  String? _facade;
  String? _ownershipDocumentType;
  String? _relationshipType;
  double? _latitude;
  double? _longitude;
  bool _busy = false;
  bool _resolvingLocation = false;
  bool _replaceImages = false;
  List<String> _imagePaths = <String>[];
  String? _ownershipProofPath;
  PropertyDetails? _workingDraft;
  PropertySaiEnvelope? _saiEnvelope;
  bool _saiBusy = false;
  String _priceDisplayMode = 'excludes_sai';

  PropertyDetails? get _existing => _workingDraft ?? widget.existingProperty;
  bool get _startedAsEditing => widget.existingProperty != null;
  bool get _isEditing => _existing != null;
  bool get _isSaiReady {
    final management = _saiEnvelope?.management;
    if (management == null || !management.configured) return false;
    if (!management.isProfessional) return true;
    final requested = management.requestedBrokerRatePercent ?? 0;
    return requested <= 0 || management.platformTermsStatus == 'accepted';
  }

  String get _saiDisplayText =>
      _saiEnvelope?.sai?.displayText ??
      _saiEnvelope?.management?.publicDisplayText ??
      (_isSaiReady ? 'تم تحديد السعي' : 'لم يتم تحديد السعي بعد');
  bool get _requiresSaleTenure =>
      _purpose == 'sale' && _saleTenureTypes.contains(_type);
  bool get _requiresResidential => _residentialTypes.contains(_type);
  bool get _requiresStructure => _structureTypes.contains(_type);
  bool? get _parkingValue =>
      _parkingChoice == null ? null : _parkingChoice == 'yes';
  bool get _visitorPaysSai => const {'buyer', 'tenant'}.contains(
        _saiEnvelope?.sai?.payer ?? _saiEnvelope?.management?.payer,
      );
  double? get _effectivePrice {
    if (_purpose == 'rent') {
      final monthly = double.tryParse(_monthlyRent.text.trim());
      final advance = int.tryParse(_advanceMonths.text.trim());
      if (monthly == null || monthly <= 0 || advance == null || advance <= 0) {
        return null;
      }
      return monthly * advance;
    }
    return double.tryParse(_price.text.trim());
  }

  String get _priceSummaryText {
    if (_purpose == 'rent') {
      final monthly = _monthlyRent.text.trim();
      final advance = _advanceMonths.text.trim();
      return monthly.isEmpty
          ? '—'
          : '$monthly YER شهرياً${advance.isEmpty ? '' : ' · مقدم $advance شهر'}';
    }
    return '${_price.text.trim()} YER';
  }

  @override
  void initState() {
    super.initState();
    _price.addListener(_onPriceChanged);
    _monthlyRent.addListener(_onPriceChanged);
    _advanceMonths.addListener(_onPriceChanged);
    final property = _existing;
    if (property == null) return;

    _purpose = property.purpose;
    _type = property.type;
    _tenureType = property.tenureType;
    _title.text = property.title;
    _description.text = property.description ?? '';
    _price.text = property.editablePrice.toStringAsFixed(0);
    _monthlyRent.text = property.monthlyRent?.toStringAsFixed(0) ?? '';
    _rentalTermMonths.text = property.rentalTermMonths?.toString() ?? '';
    _advanceMonths.text = property.advanceMonths?.toString() ?? '';
    _priceDisplayMode = property.priceDisplayMode ?? 'excludes_sai';
    _area.text = property.areaValue != null
        ? formatPropertyAreaValue(property.areaValue!)
        : property.areaM2?.toString() ?? '';
    _areaUnit = property.areaUnit ?? 'sqm';
    _bedrooms.text = property.bedrooms?.toString() ?? '';
    _bathrooms.text = property.bathrooms?.toString() ?? '';
    _parkingChoice = property.hasParking == null
        ? null
        : property.hasParking!
            ? 'yes'
            : 'no';
    _facade = property.buildingFacade;
    final address = PropertyLocationAddress.fromStoredAddress(property.address);
    _governorate.text = address.governorate ?? '';
    _district.text = address.district ?? '';
    _street.text = address.street ?? '';
    _latitude = property.latitude;
    _longitude = property.longitude;
    _phone.text = property.contactPhone ?? '';
    _whatsapp.text = property.contactWhatsapp ?? '';
    _ownershipDocumentType = property.ownershipDocumentType;
    _documentOwnerName.text = property.documentOwnerName ?? '';
    _relationshipType = property.ownerRelationshipType;
    _relationshipNote.text = property.ownerRelationshipNote ?? '';
    unawaited(_refreshSai(property.id));
  }

  @override
  void dispose() {
    _price.removeListener(_onPriceChanged);
    _monthlyRent.removeListener(_onPriceChanged);
    _advanceMonths.removeListener(_onPriceChanged);
    unawaited(
      _mediaPicker.clearTemporaryFiles(<String>[
        ..._imagePaths,
        if (_ownershipProofPath != null) _ownershipProofPath!,
      ]).catchError((_) {}),
    );
    for (final controller in <TextEditingController>[
      _title,
      _description,
      _price,
      _monthlyRent,
      _rentalTermMonths,
      _advanceMonths,
      _area,
      _bedrooms,
      _bathrooms,
      _governorate,
      _district,
      _street,
      _phone,
      _whatsapp,
      _documentOwnerName,
      _relationshipNote,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final correctionReason =
        _existing?.reviewStatus == 'returned_for_correction'
            ? _existing?.lastReviewReason
            : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: _isEditing ? 'تعديل الإعلان' : 'إضافة عقار',
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (correctionReason != null &&
                  correctionReason.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppLayout.compactPageGutter,
                    AppSpacing.s8,
                    AppLayout.compactPageGutter,
                    0,
                  ),
                  child: AppInlineMessage(
                    title: 'مطلوب تصحيح قبل إعادة الإرسال',
                    message: correctionReason,
                    tone: AppStatusTone.warning,
                  ),
                ),
              _ProgressHeader(step: _step),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppLayout.compactPageGutter,
                    AppSpacing.s8,
                    AppLayout.compactPageGutter,
                    AppSpacing.s24,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
        0 => _basicsStep(),
        1 => _locationStep(),
        2 => _specificationsStep(),
        3 => _priceStep(),
        _ => _mediaEvidenceReviewStep(),
      };

  Widget _basicsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'نوع الإعلان والعقار',
          subtitle: 'اختر الغرض والنوع واكتب عنواناً ووصفاً واضحين.',
        ),
        const SizedBox(height: AppSpacing.s16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'sale', label: Text('للبيع')),
            ButtonSegment(value: 'rent', label: Text('للإيجار')),
          ],
          selected: {_purpose},
          onSelectionChanged: _busy
              ? null
              : (values) => setState(() {
                    _purpose = values.first;
                    if (!_requiresSaleTenure) _tenureType = null;
                  }),
        ),
        const SizedBox(height: AppSpacing.s16),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: _typeLabels.entries
              .map(
                (entry) => ChoiceChip(
                  label: Text(entry.value),
                  selected: _type == entry.key,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                            _type = entry.key;
                            if (!_requiresSaleTenure) _tenureType = null;
                            if (!_requiresResidential) {
                              _bedrooms.clear();
                              _bathrooms.clear();
                            }
                            if (!_requiresStructure) {
                              _parkingChoice = null;
                              _facade = null;
                            }
                          }),
                ),
              )
              .toList(growable: false),
        ),
        if (_requiresSaleTenure) ...[
          const SizedBox(height: AppSpacing.s16),
          DropdownButtonFormField<String>(
            value: _tenureType,
            decoration: const InputDecoration(labelText: 'نوع الملكية *'),
            items: const [
              DropdownMenuItem(value: 'freehold', child: Text('حر')),
              DropdownMenuItem(value: 'waqf', child: Text('وقف')),
            ],
            onChanged:
                _busy ? null : (value) => setState(() => _tenureType = value),
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
        AppTextField(
          controller: _title,
          label: 'عنوان الإعلان *',
          hint: 'مثال: شقة واسعة في حي حدة',
          enabled: !_busy,
        ),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _description,
          label: 'الوصف',
          hint: 'اكتب أهم تفاصيل العقار بوضوح.',
          enabled: !_busy,
          maxLines: 5,
        ),
      ],
    );
  }

  Widget _locationStep() {
    final hasLocation = _latitude != null && _longitude != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'موقع العقار',
          subtitle:
              'النقطة على الخريطة هي المرجع الأساسي، والعنوان يساعد البحث والمراجعة.',
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSurface(
          child: Row(
            children: [
              Icon(
                hasLocation
                    ? Icons.check_circle_outline
                    : Icons.location_on_outlined,
                color: hasLocation
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  hasLocation
                      ? 'تم تحديد الموقع: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}'
                      : 'لم يتم تحديد موقع العقار بعد.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'اختيار من الخريطة',
                icon: Icons.map_outlined,
                onPressed: _busy || _resolvingLocation ? null : _selectOnMap,
                expand: true,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: AppButton(
                label: 'تحديد موقعي الحالي',
                icon: Icons.my_location,
                onPressed:
                    _busy || _resolvingLocation ? null : _useCurrentLocation,
                expand: true,
              ),
            ),
          ],
        ),
        if (_resolvingLocation) ...[
          const SizedBox(height: AppSpacing.s12),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: AppSpacing.s20),
        AppTextField(
          controller: _governorate,
          label: 'المحافظة *',
          enabled: !_busy && hasLocation,
        ),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _district,
          label: 'المنطقة / الحي',
          enabled: !_busy && hasLocation,
        ),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _street,
          label: 'الشارع',
          enabled: !_busy && hasLocation,
        ),
      ],
    );
  }

  Widget _specificationsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'المواصفات',
          subtitle: 'أدخل المعلومات التي تساعد الباحث على مقارنة العقار بدقة.',
        ),
        const SizedBox(height: AppSpacing.s16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: AppTextField(
                controller: _area,
                label: 'عدد اللبن *',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                enabled: !_busy,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: _areaUnit,
                decoration: const InputDecoration(labelText: 'وحدة المساحة'),
                items: propertyAreaUnitLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child:
                            Text(entry.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _areaUnit = value ?? 'sqm'),
              ),
            ),
          ],
        ),
        if (_requiresResidential) ...[
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _bedrooms,
                  label: 'غرف النوم *',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppTextField(
                  controller: _bathrooms,
                  label: 'الحمامات *',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
            ],
          ),
        ],
        if (_requiresStructure) ...[
          const SizedBox(height: AppSpacing.s16),
          DropdownButtonFormField<String>(
            value: _parkingChoice,
            decoration: const InputDecoration(labelText: 'موقف سيارة *'),
            items: const [
              DropdownMenuItem(value: 'yes', child: Text('يوجد')),
              DropdownMenuItem(value: 'no', child: Text('لا يوجد')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _parkingChoice = value),
          ),
          const SizedBox(height: AppSpacing.s12),
          DropdownButtonFormField<String>(
            value: _facade,
            decoration: const InputDecoration(labelText: 'واجهة البناء *'),
            items: propertyFacadeLabels.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(growable: false),
            onChanged:
                _busy ? null : (value) => setState(() => _facade = value),
          ),
        ],
      ],
    );
  }

  Widget _priceStep() {
    final wordsSource = _purpose == 'rent' ? _monthlyRent.text : _price.text;
    final amountWords = arabicRiyalAmountInWords(wordsSource) ?? '';
    final initialAmount = _effectivePrice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: _purpose == 'rent' ? 'الإيجار والتواصل' : 'السعر والتواصل',
          subtitle: _purpose == 'rent'
              ? 'أدخل الإيجار الشهري ومدة التأجير وعدد أشهر المقدم.'
              : 'حدد السعر ووسائل التواصل التي تريد إظهارها للمهتمين.',
        ),
        const SizedBox(height: AppSpacing.s16),
        if (_purpose == 'sale')
          AppTextField(
            controller: _price,
            label: 'سعر البيع بالريال اليمني *',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_busy,
          )
        else ...[
          AppTextField(
            controller: _monthlyRent,
            label: 'الإيجار الشهري بالريال اليمني *',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_busy,
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _rentalTermMonths,
                  label: 'مدة التأجير بالأشهر *',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppTextField(
                  controller: _advanceMonths,
                  label: 'أشهر المقدم *',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
            ],
          ),
          if (initialAmount != null) ...[
            const SizedBox(height: AppSpacing.s8),
            AppInlineMessage(
              title: 'المبلغ الأساسي عند البداية',
              message: '${initialAmount.toStringAsFixed(0)} YER قبل السعي',
              tone: AppStatusTone.info,
            ),
          ],
        ],
        if (amountWords.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          AppInlineMessage(
            title: _purpose == 'rent'
                ? 'الإيجار الشهري بالحروف'
                : 'المبلغ بالحروف',
            message: amountWords,
            tone: AppStatusTone.info,
          ),
        ],
        if (_isSaiReady && _visitorPaysSai) ...[
          const SizedBox(height: AppSpacing.s16),
          Text('طريقة عرض السعر للباحث',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.s8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'excludes_sai', label: Text('السعر + السعي')),
              ButtonSegment(
                  value: 'includes_sai', label: Text('السعر شامل السعي')),
            ],
            selected: {_priceDisplayMode},
            onSelectionChanged: _busy
                ? null
                : (value) => setState(() => _priceDisplayMode = value.first),
          ),
          const SizedBox(height: AppSpacing.s8),
          const Text(
              'سيظهر للباحث إجمالي السعي والطرف الذي يتحمله فقط، بدون إظهار أي تقسيم داخلي.'),
        ],
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _phone,
          label: 'رقم الاتصال',
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _whatsapp,
          label: 'رقم واتساب',
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
      ],
    );
  }

  Widget _mediaEvidenceReviewStep() {
    final user = ref.watch(authControllerProvider).asData?.value;
    final isOwner = user?.isOwner == true;
    final isProfessional = user?.isBroker == true || user?.isOffice == true;
    final existingImages = _existing?.images.length ?? 0;
    final effectiveImages = _replaceImages
        ? _imagePaths.length
        : existingImages + _imagePaths.length;
    final existingOwnershipProof = _existing?.ownershipProofPresent == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'الصور والإثبات والمراجعة',
          subtitle:
              'احفظ كمسودة متى شئت، ثم أرسل للمراجعة فقط عندما يصبح الإعلان جاهزاً.',
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'صور الإعلان ($effectiveImages/12)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  AppButton(
                    label: 'إضافة صور',
                    icon: Icons.add_photo_alternate_outlined,
                    style: AppButtonStyle.tonal,
                    onPressed: _busy ? null : _pickImages,
                  ),
                ],
              ),
              if (_isEditing && existingImages > 0) ...[
                const SizedBox(height: AppSpacing.s8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('استبدال الصور الحالية بالكامل'),
                  subtitle: Text('الصور الحالية: $existingImages'),
                  value: _replaceImages,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _replaceImages = value),
                ),
              ],
              if (_imagePaths.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s8),
                SizedBox(
                  height: 118,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _imagePaths.length,
                    onReorder: _busy
                        ? (_, __) {}
                        : (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final path = _imagePaths.removeAt(oldIndex);
                              _imagePaths.insert(newIndex, path);
                            });
                          },
                    itemBuilder: (context, index) {
                      final path = _imagePaths[index];
                      return Container(
                        key: ValueKey(path),
                        width: 110,
                        margin: const EdgeInsetsDirectional.only(
                            end: AppSpacing.s8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.control),
                              child: Image.file(
                                File(path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image_outlined)),
                              ),
                            ),
                            PositionedDirectional(
                              top: 4,
                              end: 4,
                              child: IconButton.filled(
                                tooltip: 'إزالة الصورة',
                                onPressed:
                                    _busy ? null : () => _removeImage(index),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ),
                            if (index == 0 &&
                                (_replaceImages || existingImages == 0))
                              const PositionedDirectional(
                                start: 5,
                                bottom: 5,
                                child: AppStatusBadge(
                                  label: 'الرئيسية',
                                  tone: AppStatusTone.info,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'اسحب الصور لتغيير ترتيبها. أول صورة جديدة تصبح الرئيسية عند الاستبدال أو في الإعلان الجديد.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (isProfessional) ...[
          const SizedBox(height: AppSpacing.s12),
          const AppInlineMessage(
            message:
                'الحساب المهني الموثق لا يُطلب منه إثبات ملكية لا يخصه. الإعلان نفسه يبقى خاضعاً للمراجعة ومنع التكرار.',
            tone: AppStatusTone.info,
          ),
        ],
        if (isOwner) ...[
          const SizedBox(height: AppSpacing.s16),
          const AppSectionHeader(
            title: 'إثبات علاقتك بهذا العقار',
            subtitle:
                'هويتك موثقة في الحساب؛ هنا نراجع علاقتك بهذا العقار فقط.',
          ),
          const SizedBox(height: AppSpacing.s12),
          DropdownButtonFormField<String>(
            value: _ownershipDocumentType,
            decoration: const InputDecoration(labelText: 'نوع مستند العقار'),
            items: _ownershipDocumentTypes.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(growable: false),
            onChanged: _busy
                ? null
                : (value) => setState(() => _ownershipDocumentType = value),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppTextField(
            controller: _documentOwnerName,
            label: 'اسم صاحب الحق كما في المستند',
            enabled: !_busy,
          ),
          const SizedBox(height: AppSpacing.s12),
          DropdownButtonFormField<String>(
            value: _relationshipType,
            decoration: const InputDecoration(labelText: 'صفتك بالنسبة للعقار'),
            items: _relationshipTypes.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(growable: false),
            onChanged: _busy
                ? null
                : (value) => setState(() => _relationshipType = value),
          ),
          if (_relationshipType != null && _relationshipType != 'owner') ...[
            const SizedBox(height: AppSpacing.s12),
            AppTextField(
              controller: _relationshipNote,
              label: _relationshipType == 'other'
                  ? 'وضح صفتك وعلاقتك بالعقار'
                  : 'تفاصيل العلاقة أو التفويض (اختياري)',
              enabled: !_busy,
              maxLines: 3,
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          AppSurface(
            onTap: _busy ? null : _pickOwnershipProof,
            child: AppListRow(
              title: 'مستند ملكية / علاقة العقار',
              subtitle: _ownershipProofPath != null
                  ? 'تم اختيار مستند جديد'
                  : existingOwnershipProof
                      ? 'يوجد مستند مرفوع سابقاً'
                      : 'اضغط لاختيار المستند',
              leading: Icon(
                _ownershipProofPath != null || existingOwnershipProof
                    ? Icons.check_circle_outline
                    : Icons.upload_file_outlined,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s20),
        const AppSectionHeader(
          title: 'السعي',
          subtitle: 'حدد السعي والطرف الذي يتحمله قبل إرسال الإعلان للمراجعة.',
        ),
        const SizedBox(height: AppSpacing.s8),
        _saiConfigurationCard(),
        const SizedBox(height: AppSpacing.s20),
        const AppSectionHeader(title: 'ملخص الإعلان'),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          child: Column(
            children: [
              _SummaryRow(label: 'العنوان', value: _title.text.trim()),
              _SummaryRow(
                  label: 'الغرض',
                  value: _purpose == 'sale' ? 'للبيع' : 'للإيجار'),
              _SummaryRow(label: 'النوع', value: _typeLabels[_type] ?? _type),
              _SummaryRow(label: 'السعر', value: _priceSummaryText),
              _SummaryRow(label: 'الموقع', value: _composedAddress),
              _SummaryRow(
                  label: 'عدد اللبن',
                  value:
                      '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}'),
              _SummaryRow(label: 'السعي', value: _saiDisplayText),
            ],
          ),
        ),
      ],
    );
  }

  Widget _saiConfigurationCard() {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isSaiReady
                    ? Icons.check_circle_rounded
                    : Icons.payments_outlined,
                color: _isSaiReady ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  _saiDisplayText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            _isSaiReady
                ? 'يمكنك تعديل اختيار السعي قبل الإرسال إذا احتجت.'
                : 'لن يتم إرسال الإعلان للمراجعة حتى يتم تحديد السعي المطلوب.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: _isSaiReady ? 'تعديل السعي' : 'تحديد السعي',
            icon: Icons.payments_outlined,
            loading: _saiBusy,
            onPressed: _busy || _saiBusy ? null : _configureSai,
            expand: true,
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    if (_step < 4) {
      return _BottomBar(
        children: [
          if (_step > 0)
            Expanded(
              child: AppButton(
                label: 'السابق',
                style: AppButtonStyle.outlined,
                onPressed: _busy ? null : () => setState(() => _step--),
                expand: true,
              ),
            ),
          if (_step > 0) const SizedBox(width: AppSpacing.s8),
          Expanded(
            flex: 2,
            child: AppButton(
              label: 'التالي',
              onPressed: _busy ? null : _next,
              expand: true,
            ),
          ),
        ],
      );
    }

    return _FinalActionsBar(
      busy: _busy,
      onPrevious: () => setState(() => _step--),
      onPreview: _preview,
      onSaveDraft: () => _persist(submit: false),
      onSubmit: () => _persist(submit: true),
    );
  }

  void _next() {
    final message = _validationMessageForStep(_step);
    if (message != null) {
      _message(message);
      return;
    }
    setState(() => _step++);
  }

  String? _validationMessageForStep(int step) {
    if (step == 0) {
      if (_title.text.trim().length < 4) {
        return 'اكتب عنواناً واضحاً من 4 أحرف على الأقل.';
      }
      if (_requiresSaleTenure && _tenureType == null) {
        return 'حدد نوع الملكية: حر أو وقف.';
      }
    }
    if (step == 1) {
      if (_latitude == null || _longitude == null) {
        return 'حدد موقع العقار على الخريطة أو باستخدام موقعك الحالي.';
      }
      if (_governorate.text.trim().length < 2) return 'أكمل اسم المحافظة.';
      if (_composedAddress.length < 3) return 'أكمل معلومات عنوان العقار.';
    }
    if (step == 2) {
      final areaValue = double.tryParse(_area.text.trim());
      if (areaValue == null || areaValue <= 0) return 'أدخل عدداً صحيحاً للبن.';
      if (_requiresResidential) {
        if ((_optionalInt(_bedrooms) ?? 0) < 1) return 'أدخل عدد غرف النوم.';
        if ((_optionalInt(_bathrooms) ?? 0) < 1) return 'أدخل عدد الحمامات.';
      }
      if (_requiresStructure && _parkingChoice == null) {
        return 'حدد هل يوجد موقف سيارة.';
      }
      if (_requiresStructure && _facade == null) return 'اختر واجهة البناء.';
    }
    if (step == 3) {
      if (_purpose == 'sale') {
        final value = double.tryParse(_price.text.trim());
        if (value == null || value <= 0) {
          return 'أدخل سعراً صحيحاً أكبر من صفر.';
        }
      } else {
        final monthly = double.tryParse(_monthlyRent.text.trim());
        final term = int.tryParse(_rentalTermMonths.text.trim());
        final advance = int.tryParse(_advanceMonths.text.trim());
        if (monthly == null || monthly <= 0) {
          return 'أدخل الإيجار الشهري بشكل صحيح.';
        }
        if (term == null || term < 1 || term > 24) {
          return 'مدة التأجير يجب أن تكون من شهر إلى 24 شهراً.';
        }
        if (advance == null || advance < 1 || advance > term) {
          return 'أشهر المقدم يجب أن تكون من شهر وحتى مدة التأجير.';
        }
      }
    }
    return null;
  }

  String? _validateCore() {
    for (var step = 0; step <= 3; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) return message;
    }
    return null;
  }

  String? _validateForSubmit() {
    final core = _validateCore();
    if (core != null) return core;
    if (!_isSaiReady) {
      return 'حدد السعي والطرف الذي يتحمله قبل إرسال الإعلان للمراجعة.';
    }

    final existingImages = _existing?.images.length ?? 0;
    final effectiveImageCount = _replaceImages
        ? _imagePaths.length
        : existingImages + _imagePaths.length;
    if (effectiveImageCount < 1) {
      return 'أضف صورة واحدة على الأقل قبل إرسال الإعلان للمراجعة.';
    }

    final user = ref.read(authControllerProvider).asData?.value;
    if (user?.isOwner == true) {
      if (_ownershipDocumentType == null) {
        return 'اختر نوع مستند ملكية أو علاقة العقار.';
      }
      if (_documentOwnerName.text.trim().length < 3) {
        return 'اكتب اسم صاحب الحق كما يظهر في مستند العقار.';
      }
      if (_relationshipType == null) return 'حدد صفتك بالنسبة للعقار.';
      if (_ownershipProofPath == null &&
          _existing?.ownershipProofPresent != true) {
        return 'أرفق مستند ملكية أو علاقة هذا العقار.';
      }
      if (_relationshipType == 'owner' &&
          _normalizedName(_documentOwnerName.text) !=
              _normalizedName(user!.name)) {
        return 'الاسم في مستند العقار لا يطابق اسم الحساب. اختر صفتك الصحيحة مثل وكيل أو وارث أو شريك.';
      }
      if (_relationshipType == 'other' &&
          _relationshipNote.text.trim().length < 3) {
        return 'وضح صفتك أو علاقتك بالعقار.';
      }
    }
    return null;
  }

  PropertyListingInput _input() {
    final user = ref.read(authControllerProvider).asData?.value;
    return PropertyListingInput(
      title: _title.text.trim(),
      description: _description.text.trim(),
      purpose: _purpose,
      type: _type,
      tenureType: _requiresSaleTenure ? _tenureType : null,
      price: _effectivePrice!,
      priceDisplayMode: _visitorPaysSai ? _priceDisplayMode : 'excludes_sai',
      monthlyRent:
          _purpose == 'rent' ? double.parse(_monthlyRent.text.trim()) : null,
      rentalTermMonths:
          _purpose == 'rent' ? int.parse(_rentalTermMonths.text.trim()) : null,
      advanceMonths:
          _purpose == 'rent' ? int.parse(_advanceMonths.text.trim()) : null,
      areaValue: double.parse(_area.text.trim()),
      areaUnit: _areaUnit,
      bedrooms: _requiresResidential ? _optionalInt(_bedrooms) : null,
      bathrooms: _requiresResidential ? _optionalInt(_bathrooms) : null,
      hasParking: _requiresStructure ? _parkingValue : null,
      buildingFacade: _requiresStructure ? _facade : null,
      address: _composedAddress,
      latitude: _latitude!,
      longitude: _longitude!,
      contactPhone: _phone.text.trim(),
      contactWhatsapp: _whatsapp.text.trim(),
      ownershipDocumentType:
          user?.isOwner == true ? _ownershipDocumentType : null,
      documentOwnerName:
          user?.isOwner == true ? _documentOwnerName.text.trim() : null,
      ownerRelationshipType: user?.isOwner == true ? _relationshipType : null,
      ownerRelationshipNote:
          user?.isOwner == true ? _relationshipNote.text.trim() : null,
    );
  }

  Future<void> _persist({required bool submit}) async {
    final validation = submit ? _validateForSubmit() : _validateCore();
    if (validation != null) {
      _message(validation);
      return;
    }

    if (submit) {
      final confirmed = await AppDialog.show<bool>(
        context,
        title: 'إرسال الإعلان للمراجعة؟',
        content: const Text(
          'سيتم حفظ آخر تعديلاتك أولاً، ثم إرسال نفس الإعلان إلى فريق الدعم. أثناء المراجعة لن يكون قابلاً للتعديل حتى يعود للتصحيح أو يصدر القرار.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ وإرسال')),
        ],
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    late PropertyDetails draft;
    try {
      final repository = ref.read(propertyRepositoryProvider);
      draft = _isEditing
          ? await repository.updateListing(
              _existing!.id,
              _input(),
              imagePaths: _imagePaths,
              replaceImages: _replaceImages,
              submitForReview: false,
              ownershipProofPath: _ownershipProofPath,
            )
          : await repository.createListing(
              _input(),
              imagePaths: _imagePaths,
              submitForReview: false,
              ownershipProofPath: _ownershipProofPath,
            );

      if (mounted) setState(() => _workingDraft = draft);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      await _clearUploadedTemporaryFiles();

      if (submit) {
        try {
          draft = await repository.submitListing(draft.id);
          ref.read(propertyDataRevisionProvider.notifier).state++;
        } catch (error) {
          if (mounted) {
            final message = friendlyApiError(error);
            _message(
                'تم حفظ الإعلان كمسودة، لكن تعذر إرساله للمراجعة: $message');
            if (message.contains('السعي')) {
              await _refreshSai(draft.id);
            }
          }
          return;
        }
      }

      if (!mounted) return;
      _message(submit
          ? 'تم حفظ الإعلان وإرساله للمراجعة.'
          : 'تم حفظ الإعلان كمسودة. يمكنك إكماله وإرساله لاحقاً.');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) _finish(draft);
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(PropertyDetails property) {
    if (_startedAsEditing) {
      Navigator.of(context).pop(property);
    } else {
      context.go('/my-listings');
    }
  }

  Future<void> _preview() async {
    final validation = _validateCore();
    if (validation != null) {
      _message(validation);
      return;
    }

    await AppBottomSheet.show<void>(
      context,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s16,
            AppLayout.compactPageGutter,
            MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpacing.s24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: 'معاينة قبل الإرسال',
                  subtitle: 'هذه المعاينة لا تحفظ ولا تغيّر حالة الإعلان.',
                ),
                const SizedBox(height: AppSpacing.s16),
                if (_imagePaths.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: Image.file(
                      File(_imagePaths.first),
                      height: 210,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 160,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  )
                else if (_existing?.mainImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: Image.network(
                      _existing!.mainImage!,
                      height: 210,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 160,
                        child: Center(child: Icon(Icons.home_work_outlined)),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.s16),
                Text(_title.text.trim(),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  _priceSummaryText,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: AppSpacing.s12),
                _SummaryRow(
                    label: 'الغرض',
                    value: _purpose == 'sale' ? 'للبيع' : 'للإيجار'),
                _SummaryRow(label: 'النوع', value: _typeLabels[_type] ?? _type),
                _SummaryRow(
                    label: 'عدد اللبن',
                    value:
                        '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}'),
                _SummaryRow(label: 'السعي', value: _saiDisplayText),
                _SummaryRow(label: 'الموقع', value: _composedAddress),
                if (_description.text.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(_description.text.trim()),
                ],
                const SizedBox(height: AppSpacing.s20),
                AppButton(
                  label: 'إغلاق المعاينة',
                  style: AppButtonStyle.outlined,
                  onPressed: () => Navigator.pop(sheetContext),
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onPriceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshSai(int propertyId) async {
    try {
      final envelope =
          await ref.read(propertyRepositoryProvider).sai(propertyId);
      if (mounted) setState(() => _saiEnvelope = envelope);
    } catch (_) {
      // Sai configuration remains explicitly available in the final step.
    }
  }

  Future<PropertyDetails?> _ensureDraftForSai() async {
    final validation = _validateCore();
    if (validation != null) {
      _message(validation);
      return null;
    }
    final repository = ref.read(propertyRepositoryProvider);
    final current = _existing;
    final draft = current == null
        ? await repository.createListing(
            _input(),
            imagePaths: _imagePaths,
            submitForReview: false,
            ownershipProofPath: _ownershipProofPath,
          )
        : await repository.updateListing(
            current.id,
            _input(),
            imagePaths: _imagePaths,
            replaceImages: _replaceImages,
            submitForReview: false,
            ownershipProofPath: _ownershipProofPath,
          );
    if (mounted) setState(() => _workingDraft = draft);
    ref.read(propertyDataRevisionProvider.notifier).state++;
    await _clearUploadedTemporaryFiles();
    return draft;
  }

  Future<void> _configureSai() async {
    setState(() => _saiBusy = true);
    try {
      final draft = await _ensureDraftForSai();
      if (draft == null || !mounted) return;
      final repository = ref.read(propertyRepositoryProvider);
      final ready = await showPropertySaiConfigurationSheet(
        context,
        repository: repository,
        propertyId: draft.id,
        purpose: _purpose,
      );
      if (!mounted) return;
      await _refreshSai(draft.id);
      if (!ready && mounted) {
        _message(
            'لم يتم تأكيد السعي. أكمل بيانات السعي قبل إرسال الإعلان للمراجعة.');
      }
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _saiBusy = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final picked = await _mediaPicker.pickImages();
      if (!mounted || picked.isEmpty) return;

      final existingCount =
          _replaceImages ? 0 : (_existing?.images.length ?? 0);
      final available = (12 - existingCount - _imagePaths.length).clamp(0, 12);
      final accepted = picked.take(available).toList(growable: false);
      final discarded = picked.where((path) => !accepted.contains(path));
      await _mediaPicker.clearTemporaryFiles(discarded);
      if (!mounted) return;
      setState(() => _imagePaths = <String>[..._imagePaths, ...accepted]);
      if (accepted.length < picked.length) {
        _message('الحد الأقصى للإعلان هو 12 صورة.');
      }
    } on PlatformException {
      _message('تعذر فتح معرض الصور على هذا الجهاز.');
    } catch (_) {
      _message('تعذر اختيار الصور.');
    }
  }

  Future<void> _removeImage(int index) async {
    if (index < 0 || index >= _imagePaths.length) return;
    final path = _imagePaths[index];
    setState(() => _imagePaths = List<String>.of(_imagePaths)..removeAt(index));
    try {
      await _mediaPicker.clearTemporaryFiles([path]);
    } catch (_) {}
  }

  Future<void> _pickOwnershipProof() async {
    try {
      final picked = await _mediaPicker.pickImages();
      if (!mounted || picked.isEmpty) return;
      final next = picked.first;
      await _mediaPicker.clearTemporaryFiles(picked.skip(1));
      final old = _ownershipProofPath;
      setState(() => _ownershipProofPath = next);
      if (old != null && old != next) {
        await _mediaPicker.clearTemporaryFiles([old]);
      }
    } on PlatformException {
      _message('تعذر فتح معرض الصور لاختيار المستند.');
    } catch (_) {
      _message('تعذر اختيار المستند.');
    }
  }

  Future<void> _selectOnMap() async {
    final selection =
        await Navigator.of(context).push<PropertyLocationSelection>(
      MaterialPageRoute<PropertyLocationSelection>(
        builder: (_) => PropertyLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          reverseLookup: (latitude, longitude) => ref
              .read(propertyRepositoryProvider)
              .resolveLocationAddress(latitude: latitude, longitude: longitude),
        ),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _latitude = selection.latitude;
      _longitude = selection.longitude;
    });
    await _fillAddress(
        selection.address, selection.latitude, selection.longitude);
  }

  Future<void> _useCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message('فعّل خدمة الموقع أو اختر موقع العقار يدوياً على الخريطة.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message('لم يتم منح إذن الموقع. يمكنك اختيار موقع العقار من الخريطة.');
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
      await _fillAddress(
        const PropertyLocationAddress(),
        position.latitude,
        position.longitude,
      );
    } catch (_) {
      _message('تعذر الحصول على الموقع الحالي. استخدم الخريطة لتحديد العقار.');
    }
  }

  Future<void> _fillAddress(
    PropertyLocationAddress initial,
    double latitude,
    double longitude,
  ) async {
    setState(() => _resolvingLocation = true);
    try {
      var address = initial;
      if (!address.isComplete) {
        final resolved = await ref
            .read(propertyRepositoryProvider)
            .resolveLocationAddress(latitude: latitude, longitude: longitude);
        address = address.mergeFallback(resolved);
      }
      if (!mounted) return;
      setState(() {
        if (address.governorate != null) {
          _governorate.text = address.governorate!;
        }
        if (address.district != null) _district.text = address.district!;
        if (address.street != null) _street.text = address.street!;
      });
    } catch (_) {
      if (mounted) {
        _message(
            'تم تثبيت الموقع، لكن تعذر جلب العنوان تلقائياً. أكمله يدوياً.');
      }
    } finally {
      if (mounted) setState(() => _resolvingLocation = false);
    }
  }

  Future<void> _clearUploadedTemporaryFiles() async {
    final paths = <String>[
      ..._imagePaths,
      if (_ownershipProofPath != null) _ownershipProofPath!,
    ];
    _imagePaths = <String>[];
    _ownershipProofPath = null;
    try {
      await _mediaPicker.clearTemporaryFiles(paths);
    } catch (_) {}
  }

  String get _composedAddress => PropertyLocationAddress(
        governorate: _governorate.text,
        district: _district.text,
        street: _street.text,
      ).combined;

  int? _optionalInt(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : int.tryParse(value);
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

  void _message(String message) {
    if (!mounted) return;
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
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppLayout.compactPageGutter,
        AppSpacing.s12,
        AppLayout.compactPageGutter,
        AppSpacing.s4,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('الخطوة ${step + 1} من 5'),
              const Spacer(),
              Text('${(step + 1) * 20}%'),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          LinearProgressIndicator(value: (step + 1) / 5),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: AppElevation.floating,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s8,
            AppLayout.compactPageGutter,
            AppSpacing.s12,
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}

class _FinalActionsBar extends StatelessWidget {
  const _FinalActionsBar({
    required this.busy,
    required this.onPrevious,
    required this.onPreview,
    required this.onSaveDraft,
    required this.onSubmit,
  });

  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onPreview;
  final VoidCallback onSaveDraft;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: AppElevation.floating,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppLayout.compactPageGutter,
            AppSpacing.s8,
            AppLayout.compactPageGutter,
            AppSpacing.s12,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 390;
              final secondary = <Widget>[
                Expanded(
                  child: AppButton(
                    label: 'معاينة',
                    icon: Icons.visibility_outlined,
                    style: AppButtonStyle.outlined,
                    onPressed: busy ? null : onPreview,
                    expand: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: AppButton(
                    label: 'حفظ مسودة',
                    icon: Icons.save_outlined,
                    style: AppButtonStyle.tonal,
                    loading: busy,
                    onPressed: busy ? null : onSaveDraft,
                    expand: true,
                  ),
                ),
              ];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: 'إرسال للمراجعة',
                    icon: Icons.send_outlined,
                    loading: busy,
                    onPressed: busy ? null : onSubmit,
                    expand: true,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  if (compact) ...[
                    AppButton(
                      label: 'حفظ مسودة',
                      icon: Icons.save_outlined,
                      style: AppButtonStyle.tonal,
                      loading: busy,
                      onPressed: busy ? null : onSaveDraft,
                      expand: true,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    AppButton(
                      label: 'معاينة',
                      icon: Icons.visibility_outlined,
                      style: AppButtonStyle.outlined,
                      onPressed: busy ? null : onPreview,
                      expand: true,
                    ),
                  ] else
                    Row(children: secondary),
                  AppButton(
                    label: 'السابق',
                    style: AppButtonStyle.text,
                    onPressed: busy ? null : onPrevious,
                    expand: true,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}
