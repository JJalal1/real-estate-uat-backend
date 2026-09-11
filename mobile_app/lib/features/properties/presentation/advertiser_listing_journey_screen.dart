import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/arabic_amount_words.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/property_repository.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_location_address.dart';
import '../domain/property_sai.dart';
import 'property_location_picker_screen.dart';
import 'property_sai_configuration_sheet.dart';

class AdvertiserListingJourneyScreen extends ConsumerStatefulWidget {
  const AdvertiserListingJourneyScreen({super.key, this.existingProperty});

  final PropertyDetails? existingProperty;

  @override
  ConsumerState<AdvertiserListingJourneyScreen> createState() =>
      _AdvertiserListingJourneyScreenState();
}

class _AdvertiserListingJourneyScreenState
    extends ConsumerState<AdvertiserListingJourneyScreen> {
  static const _totalSteps = 6;
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
  PropertyDetails? _workingProperty;
  PropertySaiEnvelope? _saiEnvelope;

  PropertyDetails? get _original => widget.existingProperty;
  PropertyDetails? get _persisted => _workingProperty ?? _original;
  bool get _isOriginalEdit => _original != null;
  bool get _requiresSaleTenure =>
      _purpose == 'sale' && _saleTenureTypes.contains(_type);
  bool get _requiresResidential => _residentialTypes.contains(_type);
  bool get _requiresStructure => _structureTypes.contains(_type);
  bool? get _parkingValue =>
      _parkingChoice == null ? null : _parkingChoice == 'yes';
  bool get _saiReady {
    final management = _saiEnvelope?.management;
    return management?.configured == true &&
        management?.platformTermsStatus != 'rejected';
  }

  String get _saiSummary {
    final management = _saiEnvelope?.management;
    final publicText = management?.publicDisplayText?.trim();
    if (publicText != null && publicText.isNotEmpty) return publicText;
    final publicSai = _saiEnvelope?.sai?.displayText.trim();
    if (publicSai != null && publicSai.isNotEmpty) return publicSai;
    return _saiReady ? 'تم تحديد السعي' : 'لم يتم تحديد السعي بعد';
  }

  @override
  void initState() {
    super.initState();
    _workingProperty = _original;
    final property = _original;
    if (property != null) {
      _purpose = property.purpose;
      _type = property.type;
      _tenureType = property.tenureType;
      _title.text = property.title;
      _description.text = property.description ?? '';
      _price.text = property.price.toStringAsFixed(0);
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
      unawaited(_loadSai(property.id));
    }
  }

  @override
  void dispose() {
    unawaited(
      _mediaPicker
          .clearTemporaryFiles(<String>[
            ..._imagePaths,
            if (_ownershipProofPath != null) _ownershipProofPath!,
          ])
          .catchError((_) {}),
    );
    for (final controller in <TextEditingController>[
      _title,
      _description,
      _price,
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
    final correctionReason = _persisted?.reviewStatus == 'returned_for_correction'
        ? _persisted?.lastReviewReason
        : null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: _isOriginalEdit ? 'تعديل الإعلان' : 'إضافة عقار',
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (correctionReason != null && correctionReason.trim().isNotEmpty)
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
              _ProgressHeader(step: _step, totalSteps: _totalSteps),
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
        4 => _saiStep(),
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
              : (values) {
                  final next = values.first;
                  setState(() {
                    if (_purpose != next) _saiEnvelope = null;
                    _purpose = next;
                    if (!_requiresSaleTenure) _tenureType = null;
                  });
                },
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
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 360;
            final buttons = <Widget>[
              AppButton(
                label: 'اختيار من الخريطة',
                icon: Icons.map_outlined,
                onPressed: _busy || _resolvingLocation ? null : _selectOnMap,
                expand: true,
              ),
              AppButton(
                label: 'تحديد موقعي الحالي',
                icon: Icons.my_location,
                onPressed:
                    _busy || _resolvingLocation ? null : _useCurrentLocation,
                expand: true,
              ),
            ];
            if (narrow) {
              return Column(
                children: [
                  buttons[0],
                  const SizedBox(height: AppSpacing.s8),
                  buttons[1],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: buttons[0]),
                const SizedBox(width: AppSpacing.s8),
                Expanded(child: buttons[1]),
              ],
            );
          },
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
                decoration: const InputDecoration(labelText: 'وحدة القياس'),
                items: propertyAreaUnitLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(growable: false),
            onChanged:
                _busy ? null : (value) => setState(() => _facade = value),
          ),
        ],
      ],
    );
  }

  Widget _priceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'السعر والتواصل',
          subtitle: 'حدد السعر ووسائل التواصل التي تريد إظهارها للمهتمين.',
        ),
        const SizedBox(height: AppSpacing.s16),
        AppTextField(
          controller: _price,
          label: 'السعر بالريال اليمني *',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !_busy,
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _price,
          builder: (context, value, _) {
            final words = arabicYemeniRialAmountWords(value.text);
            if (words.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpacing.s8),
              child: AppInlineMessage(
                title: 'السعر بالحروف',
                message: words,
                tone: AppStatusTone.info,
              ),
            );
          },
        ),
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

  Widget _saiStep() {
    final user = ref.watch(authControllerProvider).asData?.value;
    final professional = user?.isBroker == true || user?.isOffice == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'السعي',
          subtitle: professional
              ? 'حدد نسبة السعي والطرف الذي يتحملها قبل إرسال الإعلان للمراجعة.'
              : 'نسبة السعي للمالك ثابتة حسب نوع الإعلان؛ حدد فقط الطرف الذي يتحملها.',
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _saiReady
                        ? Icons.check_circle_rounded
                        : Icons.payments_outlined,
                    color: _saiReady
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _saiReady ? 'تم تحديد السعي' : 'السعي مطلوب قبل الإرسال',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(_saiSummary),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              AppButton(
                label: _saiReady ? 'تعديل السعي' : 'تحديد السعي',
                icon: Icons.tune_rounded,
                loading: _busy,
                onPressed: _busy ? null : _configureSaiInJourney,
                expand: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppInlineMessage(
          message: professional
              ? 'إذا اخترت 0% يطبق النظام السعي الاحتياطي المحدد في السياسة. وإذا كانت النسبة أكبر من 0% يلزم قبول شرط التطبيق داخل شاشة السعي.'
              : _purpose == 'sale'
                  ? 'في البيع نسبة السعي للمالك ثابتة 1%، وتختار فقط من يتحملها.'
                  : 'في الإيجار نسبة السعي للمالك ثابتة 20% من إيجار الشهر الأول، وتختار فقط من يتحملها.',
          tone: AppStatusTone.info,
        ),
      ],
    );
  }

  Widget _mediaEvidenceReviewStep() {
    final user = ref.watch(authControllerProvider).asData?.value;
    final isOwner = user?.isOwner == true;
    final isProfessional = user?.isBroker == true || user?.isOffice == true;
    final existingImages = _persisted?.images.length ?? 0;
    final effectiveImages =
        _replaceImages ? _imagePaths.length : existingImages + _imagePaths.length;
    final existingOwnershipProof = _persisted?.ownershipProofPresent == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'الصور والإثبات والمراجعة',
          subtitle:
              'راجع كل البيانات بما فيها السعي، ثم أرسل الإعلان للمراجعة عندما يصبح جاهزاً.',
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
              if (_persisted != null && existingImages > 0) ...[
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
                          end: AppSpacing.s8,
                        ),
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
                                  child: Icon(Icons.broken_image_outlined),
                                ),
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
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isProfessional) ...[
          const SizedBox(height: AppSpacing.s12),
          const AppInlineMessage(
            message:
                'الحساب المهني الموثق لا يُطلب منه إثبات ملكية لا يخصه. الإعلان يبقى خاضعاً للمراجعة ومنع التكرار.',
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
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
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
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
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
        const AppSectionHeader(title: 'ملخص الإعلان'),
        const SizedBox(height: AppSpacing.s8),
        AppSurface(
          child: Column(
            children: [
              _SummaryRow(label: 'العنوان', value: _title.text.trim()),
              _SummaryRow(
                label: 'الغرض',
                value: _purpose == 'sale' ? 'للبيع' : 'للإيجار',
              ),
              _SummaryRow(label: 'النوع', value: _typeLabels[_type] ?? _type),
              _SummaryRow(label: 'السعر', value: '${_price.text.trim()} YER'),
              _SummaryRow(label: 'السعي', value: _saiSummary),
              _SummaryRow(label: 'الموقع', value: _composedAddress),
              _SummaryRow(
                label: 'عدد اللبن',
                value:
                    '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    if (_step < _totalSteps - 1) {
      return _BottomBar(
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: AppButton(
                  label: 'السابق',
                  style: AppButtonStyle.outlined,
                  onPressed: _busy ? null : () => setState(() => _step--),
                  expand: true,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
            ],
            Expanded(
              flex: 2,
              child: AppButton(
                label: 'التالي',
                onPressed: _busy ? null : _next,
                expand: true,
              ),
            ),
          ],
        ),
      );
    }

    return _BottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'إرسال للمراجعة',
            icon: Icons.send_outlined,
            loading: _busy,
            onPressed: _busy ? null : () => _persist(submit: true),
            expand: true,
          ),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'معاينة',
                  icon: Icons.visibility_outlined,
                  style: AppButtonStyle.outlined,
                  onPressed: _busy ? null : _preview,
                  expand: true,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppButton(
                  label: 'حفظ مسودة',
                  icon: Icons.save_outlined,
                  style: AppButtonStyle.tonal,
                  loading: _busy,
                  onPressed: _busy ? null : () => _persist(submit: false),
                  expand: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          AppButton(
            label: 'السابق',
            style: AppButtonStyle.text,
            onPressed: _busy ? null : () => setState(() => _step--),
            expand: true,
          ),
        ],
      ),
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
      if (areaValue == null || areaValue <= 0) {
        return 'أدخل عدد اللبن بشكل صحيح.';
      }
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
      final value = double.tryParse(_price.text.trim().replaceAll(',', ''));
      if (value == null || value <= 0) {
        return 'أدخل سعراً صحيحاً أكبر من صفر.';
      }
    }
    if (step == 4 && !_saiReady) {
      return 'حدد السعي والطرف الذي يتحمله قبل المتابعة.';
    }
    return null;
  }

  String? _validateCore() {
    for (var step = 0; step <= 4; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) return message;
    }
    return null;
  }

  String? _validateForSubmit() {
    final core = _validateCore();
    if (core != null) return core;
    final existingImages = _persisted?.images.length ?? 0;
    final effectiveImageCount =
        _replaceImages ? _imagePaths.length : existingImages + _imagePaths.length;
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
          _persisted?.ownershipProofPresent != true) {
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
      price: double.parse(_price.text.trim().replaceAll(',', '')),
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
      ownerRelationshipType:
          user?.isOwner == true ? _relationshipType : null,
      ownerRelationshipNote:
          user?.isOwner == true ? _relationshipNote.text.trim() : null,
    );
  }

  Future<void> _configureSaiInJourney() async {
    for (var step = 0; step <= 3; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) {
        setState(() => _step = step);
        _message(message);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final draft = await _saveCoreDraft();
      if (!mounted) return;
      setState(() {
        _workingProperty = draft;
        _busy = false;
      });
      final ready = await showPropertySaiConfigurationSheet(
        context,
        repository: ref.read(propertyRepositoryProvider),
        propertyId: draft.id,
        purpose: _purpose,
      );
      if (!mounted) return;
      await _loadSai(draft.id);
      if (!ready) {
        _message('لم يكتمل تحديد السعي. أكمل بيانات السعي قبل المتابعة.');
      }
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<PropertyDetails> _saveCoreDraft() async {
    final repository = ref.read(propertyRepositoryProvider);
    final property = _persisted;
    final draft = property == null
        ? await repository.createListing(_input(), submitForReview: false)
        : await repository.updateListing(
            property.id,
            _input(),
            submitForReview: false,
          );
    ref.read(propertyDataRevisionProvider.notifier).state++;
    return draft;
  }

  Future<void> _loadSai(int propertyId) async {
    try {
      final value = await ref.read(propertyRepositoryProvider).sai(propertyId);
      if (!mounted) return;
      setState(() => _saiEnvelope = value);
    } catch (_) {
      // Sai remains explicitly incomplete; the user can retry from its step.
    }
  }

  Future<void> _persist({required bool submit}) async {
    final validation = submit ? _validateForSubmit() : _validateCore();
    if (validation != null) {
      if (validation.contains('السعي')) setState(() => _step = 4);
      _message(validation);
      return;
    }

    if (submit) {
      final confirmed = await AppDialog.show<bool>(
        context,
        title: 'إرسال الإعلان للمراجعة؟',
        content: const Text(
          'سيتم حفظ آخر تعديلاتك ثم إرسال نفس الإعلان إلى فريق الدعم. راجع السعي والبيانات قبل المتابعة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ وإرسال'),
          ),
        ],
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final repository = ref.read(propertyRepositoryProvider);
      final current = _persisted;
      var draft = current == null
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

      _workingProperty = draft;
      ref.read(propertyDataRevisionProvider.notifier).state++;
      await _clearUploadedTemporaryFiles();

      if (submit) {
        try {
          draft = await repository.submitListing(draft.id);
          _workingProperty = draft;
          ref.read(propertyDataRevisionProvider.notifier).state++;
        } catch (error) {
          if (!mounted) return;
          final message = friendlyApiError(error);
          if (message.contains('السعي')) setState(() => _step = 4);
          _message('تعذر إرسال الإعلان للمراجعة: $message');
          return;
        }
      }

      if (!mounted) return;
      _message(
        submit
            ? 'تم حفظ الإعلان وإرساله للمراجعة.'
            : 'تم حفظ الإعلان كمسودة. يمكنك إكماله وإرساله لاحقاً.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) _finish(draft);
    } catch (error) {
      if (mounted) _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(PropertyDetails property) {
    if (_isOriginalEdit) {
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
    final priceWords = arabicYemeniRialAmountWords(_price.text);
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
                  subtitle: 'هذه المعاينة لا تغير حالة الإعلان.',
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
                    ),
                  )
                else if (_persisted?.mainImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: Image.network(
                      _persisted!.mainImage!,
                      height: 210,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: AppSpacing.s16),
                Text(
                  _title.text.trim(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  '${_price.text.trim()} YER',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                if (priceWords.isNotEmpty) Text(priceWords),
                const SizedBox(height: AppSpacing.s12),
                _SummaryRow(
                  label: 'الغرض',
                  value: _purpose == 'sale' ? 'للبيع' : 'للإيجار',
                ),
                _SummaryRow(label: 'النوع', value: _typeLabels[_type] ?? _type),
                _SummaryRow(label: 'السعي', value: _saiSummary),
                _SummaryRow(
                  label: 'عدد اللبن',
                  value:
                      '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}',
                ),
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

  Future<void> _pickImages() async {
    try {
      final picked = await _mediaPicker.pickImages();
      if (!mounted || picked.isEmpty) return;
      final existingCount =
          _replaceImages ? 0 : (_persisted?.images.length ?? 0);
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
    final selection = await Navigator.of(context).push<PropertyLocationSelection>(
      MaterialPageRoute<PropertyLocationSelection>(
        builder: (_) => PropertyLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          reverseLookup: (latitude, longitude) => ref
              .read(propertyRepositoryProvider)
              .resolveLocationAddress(
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
    await _fillAddress(
      selection.address,
      selection.latitude,
      selection.longitude,
    );
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
            .resolveLocationAddress(
              latitude: latitude,
              longitude: longitude,
            );
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
          'تم تثبيت الموقع، لكن تعذر جلب العنوان تلقائياً. أكمله يدوياً.',
        );
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
  const _ProgressHeader({required this.step, required this.totalSteps});

  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / totalSteps;
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
              Text('الخطوة ${step + 1} من $totalSteps'),
              const Spacer(),
              Text('${(progress * 100).round()}%'),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

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
          child: child,
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
