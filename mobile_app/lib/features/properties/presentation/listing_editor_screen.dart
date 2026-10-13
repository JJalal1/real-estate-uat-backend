import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/listing_recovery_store.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ebroker_design.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_step_button.dart';
import '../../account/data/auth_controller.dart';
import '../data/property_repository.dart';
import '../domain/arabic_price_words.dart';
import '../domain/property_details.dart';
import '../domain/property_field_options.dart';
import '../domain/property_location_address.dart';
import '../domain/property_sai.dart';
import 'property_land_boundary_picker_screen.dart';
import 'property_location_picker_screen.dart';
import 'listing_sai_section.dart';

class ListingEditorScreen extends ConsumerStatefulWidget {
  const ListingEditorScreen({super.key, this.existingProperty});

  final PropertyDetails? existingProperty;

  @override
  ConsumerState<ListingEditorScreen> createState() =>
      _ListingEditorScreenState();
}

class _ListingEditorScreenState extends ConsumerState<ListingEditorScreen> with WidgetsBindingObserver {
  static const _typeLabels = <String, String>{
    'apartment': 'شقة',
    'floor': 'دور كامل',
    'building': 'عمارة كاملة',
    'house': 'منزل',
    'villa': 'فيلا',
    'land': 'أرض',
    'shop': 'محل',
    'office': 'مكتب',
    'farm': 'مزرعة',
  };
  static const _saleTenureTypes = <String>{
    'apartment',
    'floor',
    'building',
    'house',
    'villa',
    'land',
    'farm',
  };
  static const _residentialTypes = <String>{'apartment', 'floor', 'house', 'villa'};
  static const _structureTypes = <String>{
    'apartment',
    'floor',
    'building',
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
  final _buildingReference = TextEditingController();
  final _unitNumber = TextEditingController();
  final _floorNumber = TextEditingController();
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
  Map<String, dynamic>? _landBoundaryGeoJson;
  bool _busy = false;
  bool _resolvingLocation = false;
  bool _replaceImages = false;
  List<String> _imagePaths = <String>[];
  String? _ownershipProofPath;
  PropertyDetails? _workingDraft;
  final _saiRate = TextEditingController(text: '0');
  PropertySaiManagement? _saiPolicy;
  String? _saiPolicyError;
  bool _saiAccepted = false, _saiTouched = false, _hasRecoveredSai = false;
  bool _shopInBuilding = false, _existingSaiLoaded = false;
  int _saiPolicyRequest = 0;
  String _priceDisplayMode = 'excludes_sai';

  Timer? _recoveryTimer;
  late ListingRecoveryStore _recoveryStore;
  int? _recoveryUserId, _recoveredServerId;
  bool _recoveryReady = false, _recoveryFinished = false, _recoverySaved = false, _recoveryFailed = false;
  String? _lastRecoverySignature;

  Map<String, TextEditingController> get _recoveryFields => {
    'broker_sai_rate_percent': _saiRate,
    'title': _title, 'description': _description, 'price': _price, 'monthly_rent': _monthlyRent,
    'rental_term_months': _rentalTermMonths, 'advance_months': _advanceMonths, 'area': _area,
    'bedrooms': _bedrooms, 'bathrooms': _bathrooms, 'governorate': _governorate, 'district': _district,
    'street': _street, 'building_reference': _buildingReference, 'unit_number': _unitNumber,
    'floor_number': _floorNumber, 'phone': _phone, 'whatsapp': _whatsapp,
    'document_owner_name': _documentOwnerName, 'relationship_note': _relationshipNote,
  };

  Map<String, dynamic> _recoverySnapshot() => {
    'editor_version': 4, 'sai_terms_accepted': _saiAccepted, 'shop_in_building': _shopInBuilding,
    'step': _step, 'purpose': _purpose, 'type': _type, 'area_unit': _areaUnit,
    'tenure_type': _tenureType, 'parking': _parkingChoice, 'facade': _facade,
    'ownership_document_type': _ownershipDocumentType, 'relationship_type': _relationshipType,
    'latitude': _latitude, 'longitude': _longitude, 'land_boundary': _landBoundaryGeoJson,
    'replace_images': _replaceImages, 'price_display_mode': _priceDisplayMode,
    'server_property_id': _existing?.id ?? _recoveredServerId,
    'proof_needs_reselection': _ownershipProofPath != null,
    'fields': {for (final entry in _recoveryFields.entries) entry.key: entry.value.text},
  };

  @override
  void setState(VoidCallback fn) { super.setState(fn); _scheduleRecovery(); }

  void _scheduleRecovery() {
    if (!_recoveryReady || _recoveryFinished || _recoveryUserId == null) return;
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(milliseconds: 650), () => unawaited(_saveRecovery()));
  }

  Future<void> _saveRecovery() async {
    final userId = _recoveryUserId;
    if (userId == null || !_recoveryReady || _recoveryFinished) return;
    final data = _recoverySnapshot();
    final images = List<String>.of(_imagePaths);
    final signature = jsonEncode([data, images]);
    if (signature == _lastRecoverySignature) return;
    try {
      await _recoveryStore.write(userId, widget.existingProperty?.id, data, images);
      _lastRecoverySignature = signature;
      if (mounted && !_recoveryFinished) super.setState(() { _recoverySaved = true; _recoveryFailed = false; });
    } catch (_) { if (mounted) super.setState(() => _recoveryFailed = true); }
  }

  Future<void> _restoreRecovery() async {
    if (_recoveryUserId == null) {
      try {
        final actor = await ref.read(authControllerProvider.future);
        if (!mounted) return;
        _recoveryUserId = actor?.id;
      } catch (_) {}
    }
    if (!mounted) return;
    final userId = _recoveryUserId;
    if (userId == null) { _recoveryReady = true; super.setState(() {}); return; }
    final data = await _recoveryStore.read(userId, widget.existingProperty?.id);
    if (!mounted) return;
    if (data != null) {
      final fields = data['fields'];
      if (fields is Map) {
        for (final entry in _recoveryFields.entries) {
          final text = fields[entry.key]; if (text is String) entry.value.text = text;
        }
      }
      _step = (data['step'] is int ? data['step'] as int : 0).clamp(0, 3).toInt();
      if (const ['sale', 'rent'].contains(data['purpose'])) _purpose = data['purpose'] as String;
      if (_typeLabels.containsKey(data['type'])) _type = data['type'] as String;
      if (propertyAreaUnitLabels.containsKey(data['area_unit'])) _areaUnit = data['area_unit'] as String;
      _tenureType = const ['freehold', 'waqf'].contains(data['tenure_type']) ? data['tenure_type'] as String : null;
      _parkingChoice = const ['yes', 'no'].contains(data['parking']) ? data['parking'] as String : null;
      _facade = propertyFacadeLabels.containsKey(data['facade']) ? data['facade'] as String : null;
      _ownershipDocumentType = _ownershipDocumentTypes.containsKey(data['ownership_document_type']) ? data['ownership_document_type'] as String : null;
      _relationshipType = _relationshipTypes.containsKey(data['relationship_type']) ? data['relationship_type'] as String : null;
      _latitude = (data['latitude'] as num?)?.toDouble(); _longitude = (data['longitude'] as num?)?.toDouble();
      if (data['land_boundary'] is Map) _landBoundaryGeoJson = Map<String, dynamic>.from(data['land_boundary'] as Map);
      _replaceImages = data['replace_images'] == true;
      if (const ['excludes_sai', 'includes_sai'].contains(data['price_display_mode'])) _priceDisplayMode = data['price_display_mode'] as String;
      _imagePaths = (data['image_paths'] as List? ?? const []).whereType<String>().toList();
      final serverId = data['server_property_id'];
      if (widget.existingProperty == null && serverId is int && serverId > 0) _recoveredServerId = serverId;
      _hasRecoveredSai = fields is Map && fields.containsKey('broker_sai_rate_percent');
      _saiAccepted = data['sai_terms_accepted'] == true;
      _shopInBuilding = data['shop_in_building'] == true || _floorNumber.text.isNotEmpty;
      _recoverySaved = true;
      if (data['proof_needs_reselection'] == true) _message('استعدنا بيانات الإعلان. أعد اختيار ملف إثبات الملكية عند إكمال المسودة.');
    }
    _recoveryReady = true;
    _lastRecoverySignature = jsonEncode([_recoverySnapshot(), _imagePaths]);
    super.setState(() {});
  }

  Future<bool> _resolveRecoveredDraft() async {
    if (_recoveredServerId == null || _workingDraft != null) return true;
    try {
      final existing = await ref.read(propertyRepositoryProvider).details(_recoveredServerId!);
      if (!mounted) return false;
      setState(() => _workingDraft = existing);
      await _refreshSai(existing.id);
      return true;
    } catch (error) { if (mounted) _message(friendlyApiError(error)); return false; }
  }

  PropertyDetails? get _existing => _workingDraft ?? widget.existingProperty;
  bool get _startedAsEditing => widget.existingProperty != null;
  bool get _isEditing => _existing != null;
  bool get _isSaiReady => _inlineSaiValidation == null;
  double get _enteredSaiRate => double.tryParse(_saiRate.text.trim()) ?? double.nan;
  String? get _inlineSaiValidation {
    final policy = _saiPolicy;
    if (policy == null) return 'تعذر تحميل سياسة السعي. أعد تحميلها قبل الإرسال.';
    if (policy.isOwner) return null;
    if (_isEditing && !_existingSaiLoaded && !_saiTouched && !_hasRecoveredSai) return 'انتظر تحميل السعي الحالي أو حدد النسبة بنفسك.';
    final rate = _enteredSaiRate, maximum = policy.brokerMaxRatePercent;
    if (!rate.isFinite || rate < 0 || maximum == null || rate > maximum || (rate * 100 - (rate * 100).round()).abs() > .000001) {
      return 'أدخل نسبة سعي صحيحة ضمن الحد المسموح وبدقتين عشريتين على الأكثر.';
    }
    if (rate > 0 && !_saiAccepted) return 'وافق على مستحق المنصة الموضح قبل إرسال الإعلان.';
    return null;
  }
  String get _saiDisplayText {
    final policy = _saiPolicy;
    if (policy == null) return 'سياسة السعي غير محملة';
    final rate = policy.isOwner || _enteredSaiRate == 0 ? policy.fixedRatePercent : _enteredSaiRate;
    return 'السعي ${rate ?? '—'}% · يتحمله ${_purpose == 'rent' ? 'المستأجر' : 'المشتري'}';
  }
  bool get _requiresSaleTenure => _purpose == 'sale' && _saleTenureTypes.contains(_type);
  bool get _requiresResidential => _residentialTypes.contains(_type);
  bool get _requiresStructure => _structureTypes.contains(_type);
  bool get _isUnitType => const {'apartment', 'floor', 'office', 'shop'}.contains(_type);
  bool get _unitNeedsFloor => const {'apartment', 'floor', 'office'}.contains(_type) || (_type == 'shop' && _shopInBuilding);
  bool? get _parkingValue =>
      _parkingChoice == null ? null : _parkingChoice == 'yes';
  bool get _visitorPaysSai => true;
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _recoveryTimer?.cancel();
      unawaited(_saveRecovery());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _price.addListener(_onPriceChanged);
    _monthlyRent.addListener(_onPriceChanged);
    _advanceMonths.addListener(_onPriceChanged);
    _recoveryStore = ref.read(listingRecoveryStoreProvider);
    _recoveryUserId = ref.read(authControllerProvider).asData?.value?.id;
    Future.microtask(() async { await _restoreRecovery(); if (mounted) await _loadSaiPolicy(); });
    for (final controller in _recoveryFields.values) { controller.addListener(_scheduleRecovery); }
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
    _buildingReference.text = property.buildingReference ?? '';
    _unitNumber.text = property.unitNumber ?? '';
    _floorNumber.text = property.floorNumber ?? '';
    _shopInBuilding = _type == 'shop' && _floorNumber.text.isNotEmpty;
    _landBoundaryGeoJson = property.landBoundaryGeoJson;
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
    WidgetsBinding.instance.removeObserver(this);
    _price.removeListener(_onPriceChanged);
    _monthlyRent.removeListener(_onPriceChanged);
    _advanceMonths.removeListener(_onPriceChanged);
    _recoveryTimer?.cancel();
    final pendingRecovery = _saveRecovery();
    unawaited(
      pendingRecovery.whenComplete(() => _mediaPicker.clearTemporaryFiles(<String>[
        ..._imagePaths,
        if (_ownershipProofPath != null) _ownershipProofPath!,
      ].where((path) => !ListingRecoveryStore.isSavedMedia(path)))).catchError((_) {}),
    );
    for (final controller in <TextEditingController>[
      _saiRate,
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
      _buildingReference,
      _unitNumber,
      _floorNumber,
      _phone,
      _whatsapp,
      _documentOwnerName,
      _relationshipNote,
    ]) {
      controller.removeListener(_scheduleRecovery);
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
          actions: [Center(child: Padding(padding: const EdgeInsetsDirectional.only(end: 16),
            child: EbrokerText('${_step + 1}/4', size: 16, weight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary)))],
        ),
        body: SafeArea(
          child: !_recoveryReady ? const AppLoadingState() : Column(
            children: [
              if (_recoveryUserId != null) Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 0), child: Text(
                _recoveryFailed ? 'تعذر الحفظ التلقائي. يمكنك حفظ مسودة.' : _recoverySaved ? 'حُفظ تقدمك تلقائيًا على هذا الجهاز' : 'يُحفظ تقدمك تلقائيًا على هذا الجهاز',
                style: Theme.of(context).textTheme.bodySmall)),
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
        _ => _priceStep(),
      };

  Widget _basicsStep() {
    final extraCategoryHeight = (MediaQuery.textScalerOf(context).scale(12.rf(context)) - 12.rf(context))
        .clamp(0.0, double.infinity).toDouble() * 1.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'نوع الإعلان والعقار',
          subtitle: 'اختر الغرض والنوع واكتب عنواناً ووصفاً واضحين.',
        ),
        const SizedBox(height: AppSpacing.s16),
        EbrokerSegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'sale', label: Text('للبيع')),
            ButtonSegment(value: 'rent', label: Text('للإيجار')),
          ],
          selected: {_purpose},
          onSelectionChanged: _busy
              ? null
              : (values) => setState(() {
                    _purpose = values.first;
                    _saiAccepted = false; _saiTouched = true;
                    unawaited(_loadSaiPolicy());
                    if (!_requiresSaleTenure) _tenureType = null;
                  }),
        ),
        const SizedBox(height: AppSpacing.s16),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12,
            mainAxisExtent: 85.rh(context) + extraCategoryHeight),
          children: _typeLabels.entries
              .map(
                (entry) => EbrokerWizardCategoryCard(
                  label: entry.value,
                  icon: switch (entry.key) {
                    'house' || 'villa' => 'home',
                    'land' || 'farm' => 'propertymap',
                    'shop' => 'bank',
                    _ => 'properties',
                  },
                  selected: _type == entry.key,
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _type = entry.key;
                            if (_type == 'floor') _unitNumber.clear();
                            if (_type != 'shop') _shopInBuilding = false;
                            if (!_requiresSaleTenure) _tenureType = null;
                            if (!_requiresResidential) {
                              _bedrooms.clear();
                              _bathrooms.clear();
                            }
                            if (!_requiresStructure) {
                              _parkingChoice = null;
                              _facade = null;
                            }
                            if (!_isUnitType) {
                              _buildingReference.clear();
                              _unitNumber.clear();
                              _floorNumber.clear();
                            }
                            if (_type != 'land') {
                              _landBoundaryGeoJson = null;
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
        const SizedBox(height: 24),
        _listingPhotos(),
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
              EbrokerIcon(
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
                      ? 'تم تحديد موقع العقار على الخريطة'
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
        if (_type == 'land' && hasLocation) ...[
          const SizedBox(height: AppSpacing.s16),
          AppInlineMessage(
            title: _landBoundaryGeoJson == null
                ? 'حدود الأرض غير محددة'
                : 'تم تحديد حدود الأرض',
            message: _landBoundaryGeoJson == null
                ? 'ارسم زوايا الأرض حتى لا يعتمد منع التكرار على الدبوس فقط.'
                : 'سيستخدم النظام حدود القطعة والمساحة معاً لمنع تكرارها.',
            tone: _landBoundaryGeoJson == null
                ? AppStatusTone.warning
                : AppStatusTone.success,
          ),
          const SizedBox(height: AppSpacing.s8),
          AppButton(
            label: _landBoundaryGeoJson == null
                ? 'رسم حدود الأرض'
                : 'تعديل حدود الأرض',
            icon: Icons.polyline_outlined,
            style: AppButtonStyle.tonal,
            onPressed: _busy ? null : _pickLandBoundary,
            expand: true,
          ),
        ],
        const SizedBox(height: 24),
        _ownershipEvidence(),
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
        if (_isUnitType) ...[
          const SizedBox(height: 16),
          Text(_type == 'floor' ? 'أي دور تعرض بالكامل؟' : _type == 'shop' ? 'حدد المحل بوضوح' : 'أين الوحدة داخل المبنى؟',
            style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_type != 'floor') AppTextField(controller: _unitNumber,
            label: _type == 'shop' ? 'اسم أو رقم المحل أو موضعه *' : 'رقم الوحدة أو موضعها *',
            hint: _type == 'shop' ? 'مثال: المحل الأمامي بجوار المدخل' : 'مثال: 7 أو شمالية أو أمامية', enabled: !_busy),
          if (_type == 'shop') CheckboxListTile(contentPadding: EdgeInsets.zero,
            title: const Text('المحل داخل مبنى متعدد الأدوار'), value: _shopInBuilding,
            onChanged: _busy ? null : (value) => setState(() { _shopInBuilding = value == true; if (!_shopInBuilding) _floorNumber.clear(); })),
          if (_unitNeedsFloor) ...[
            const SizedBox(height: 12),
            AppTextField(controller: _floorNumber, label: 'أي دور؟ *', hint: 'مثال: الأرضي أو 3', enabled: !_busy),
          ],
        ],
        const SizedBox(height: AppSpacing.s16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: AppTextField(
                controller: _area,
                label: _areaUnit == 'sqm' ? 'المساحة *' : 'عدد الوحدات *',
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
            helperText: amountWords.isEmpty ? null : amountWords,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_busy,
          )
        else ...[
          AppTextField(
            controller: _monthlyRent,
            label: 'الإيجار الشهري بالريال اليمني *',
            helperText: amountWords.isEmpty ? null : amountWords,
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
        ListingSaiSection(purpose: _purpose, policy: _saiPolicy, rateController: _saiRate,
          basis: _purpose == 'rent' ? double.tryParse(_monthlyRent.text.trim()) : _effectivePrice,
          accepted: _saiAccepted, error: _saiPolicyError, enabled: !_busy,
          onRetry: () => unawaited(_loadSaiPolicy()),
          onChanged: () => setState(() => _saiTouched = true),
          onAcceptanceChanged: (value) => setState(() { _saiAccepted = value; _saiTouched = true; })),
        if (_saiPolicy != null && _visitorPaysSai) ...[
          const SizedBox(height: AppSpacing.s16),
          Text('طريقة عرض السعر للباحث',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.s8),
          EbrokerSegmentedButton<String>(
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

  Widget _listingPhotos() {
    final existingImages = _existing?.images.length ?? 0;
    final effectiveImages = _replaceImages ? _imagePaths.length : existingImages + _imagePaths.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              if (!_replaceImages && existingImages > 0) ...[
                const SizedBox(height: 10),
                SizedBox(height: 110, child: ListView.separated(scrollDirection: Axis.horizontal,
                  itemCount: existingImages, separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: Image.network(_existing!.images[index].url, width: 140, height: 110, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 140, child: Center(child: EbrokerIcon(Icons.image_outlined, size: 24))))))),
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
                                    child: EbrokerIcon(Icons.broken_image_outlined)),
                              ),
                            ),
                            PositionedDirectional(
                              top: 4,
                              end: 4,
                              child: IconButton.filled(
                                tooltip: 'إزالة الصورة',
                                onPressed:
                                    _busy ? null : () => _removeImage(index),
                                icon: const EbrokerIcon(Icons.close, size: 18),
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
    ]);
  }

  Widget _ownershipEvidence() {
    final user = ref.watch(authControllerProvider).asData?.value;
    final isOwner = user?.isOwner == true;
    final existingOwnershipProof = _existing?.ownershipProofPresent == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              leading: EbrokerIcon(
                _ownershipProofPath != null || existingOwnershipProof
                    ? Icons.check_circle_outline
                    : Icons.upload_file_outlined,
              ),
            ),
          ),
        ],
    ]);
  }

  Widget _actions() {
    if (_step < 3) {
      return _BottomBar(
        children: [
          if (_step > 0)
            Expanded(
              child: EbrokerStepButton(
                label: 'السابق',
                style: AppButtonStyle.outlined,
                onPressed: _busy ? null : () => setState(() => _step--),
                expand: true,
              ),
            ),
          if (_step > 0) const SizedBox(width: AppSpacing.s8),
          Expanded(
            flex: 2,
            child: EbrokerStepButton(
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
      if (_type == 'land' && _landBoundaryGeoJson == null) {
        return 'ارسم حدود الأرض حتى نتحقق من هوية القطعة ولا نعتمد على الدبوس وحده.';
      }
    }
    if (step == 2) {
      final areaValue = double.tryParse(_area.text.trim());
      if (areaValue == null || areaValue <= 0) return 'أدخل عدداً صحيحاً للبن.';
      if (_isUnitType) {
        if (_type != 'floor' && _unitNumber.text.trim().isEmpty) {
          return 'أدخل رقم الوحدة أو موضعها لتمييزها عن غيرها.';
        }
        if (_unitNeedsFloor && _floorNumber.text.trim().isEmpty) {
          return 'أدخل رقم الدور.';
        }
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
      return _inlineSaiValidation;
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
      buildingReference: _isUnitType ? _buildingReference.text.trim() : null,
      unitNumber: _isUnitType && _type != 'floor' ? _unitNumber.text.trim() : null,
      floorNumber: _unitNeedsFloor && _floorNumber.text.trim().isNotEmpty
          ? _floorNumber.text.trim()
          : null,
      landBoundaryGeoJson: _type == 'land' ? _landBoundaryGeoJson : null,
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
    if (!_recoveryReady || !await _resolveRecoveredDraft()) return;
    if (!mounted) return;
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
          EbrokerFilledButton(
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
      await _saveRecovery();

      // These writes follow the explicit Save/Submit action. Neither editing
      // the percentage nor displaying a preview mutates a server listing.
      final policy = _saiPolicy;
      if (policy != null && (policy.isOwner || ((_existingSaiLoaded || _saiTouched || _hasRecoveredSai || !_startedAsEditing) && _enteredSaiRate.isFinite && _enteredSaiRate >= 0 && _enteredSaiRate <= (policy.brokerMaxRatePercent ?? -1)))) {
        try {
          await repository.configureSai(draft.id,
            payer: _purpose == 'rent' ? 'tenant' : 'buyer',
            brokerRatePercent: policy.isOwner ? null : _enteredSaiRate,
            platformTermsDecision: !policy.isOwner && _enteredSaiRate > 0 ? (_saiAccepted ? 'accept' : 'reject') : null);
          ref.read(propertyDataRevisionProvider.notifier).state++;
        } catch (error) {
          if (mounted) _message('حُفظت المسودة، لكن تعذر حفظ السعي: ${friendlyApiError(error)}');
          return;
        }
      }

      if (submit) {
        try {
          final identityReady = await _checkIdentityBeforeSubmit(draft.id);
          if (!identityReady) return;
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
      _recoveryFinished = true;
      _recoveryTimer?.cancel();
      if (_recoveryUserId != null) await _recoveryStore.clear(_recoveryUserId!, widget.existingProperty?.id);
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
                        child: Center(child: EbrokerIcon(Icons.broken_image_outlined)),
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
                        child: Center(child: EbrokerIcon(Icons.home_work_outlined)),
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

  Future<void> _loadSaiPolicy() async {
    final request = ++_saiPolicyRequest;
    final purpose = _purpose;
    if (mounted) setState(() { _saiPolicy = null; _saiPolicyError = null; });
    try {
      final policy = await ref.read(propertyRepositoryProvider).saiPolicy(purpose);
      if (mounted && request == _saiPolicyRequest && purpose == _purpose) setState(() => _saiPolicy = policy);
    } catch (error) {
      if (mounted && request == _saiPolicyRequest) setState(() => _saiPolicyError = friendlyApiError(error));
    }
  }

  Future<void> _refreshSai(int propertyId) async {
    try {
      final envelope =
          await ref.read(propertyRepositoryProvider).saiForEditor(propertyId);
      if (mounted) setState(() {
        _existingSaiLoaded = true;
        final management = envelope.management;
        if (management != null && !_saiTouched && !_hasRecoveredSai) {
          _saiRate.text = (management.requestedBrokerRatePercent ?? 0).toString();
          _saiAccepted = management.platformTermsStatus == 'accepted';
        }
      });
    } catch (_) {
      // Keep local edits and the separate policy retry available.
    }
  }

  Future<bool> _checkIdentityBeforeSubmit(int propertyId) async {
    final repository = ref.read(propertyRepositoryProvider);
    final result = await repository.checkPropertyIdentity(propertyId);
    if (result.isDistinct) {
      return true;
    }
    if (result.isConfirmedDuplicate) {
      _message(
          'هذا العقار أو هذه الوحدة مسجلة بالفعل على المنصة ولا يمكن إنشاء إعلان آخر لها.');
      return false;
    }
    final answer = await _duplicateSelfVerificationDialog();
    if (answer == null || !mounted) return false;
    final verified = await repository.selfVerifyPropertyIdentity(
      propertyId,
      differenceType: answer.$1,
      differenceNote: answer.$2,
    );
    if (verified.isConfirmedDuplicate) {
      _message(
          'بعد التحقق ما زال هذا العقار مطابقاً لعقار مسجل، لذلك لا يمكن إرساله.');
      return false;
    }
    if (verified.needsSupport) {
      _message(
          'تم تسجيل توضيحك. بقي تشابه غير محسوم وسيشاهده موظف الدعم كمقارنة جاهزة فقط.');
    }
    return true;
  }

  Future<(String, String)?> _duplicateSelfVerificationDialog() async {
    final note = TextEditingController();
    var type = 'different_address';
    String? error;
    final result = await showDialog<(String, String)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('وجدنا عقاراً مشابهاً'),
            content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'إذا كان هذا عقاراً مختلفاً، اختر الفرق واكتب معلومة تساعد النظام على التمييز. الحالات غير المحسومة فقط تذهب للدعم.'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
                decoration:
                    const InputDecoration(labelText: 'ما الفرق الأساسي؟'),
                items: const [
                  DropdownMenuItem(
                      value: 'different_building', child: Text('مبنى مختلف')),
                  DropdownMenuItem(
                      value: 'different_unit', child: Text('وحدة مختلفة')),
                  DropdownMenuItem(
                      value: 'different_area', child: Text('مساحة مختلفة')),
                  DropdownMenuItem(
                      value: 'different_boundary',
                      child: Text('حدود أرض مختلفة')),
                  DropdownMenuItem(
                      value: 'different_address',
                      child: Text('عنوان/رقم عقار مختلف')),
                  DropdownMenuItem(value: 'other', child: Text('فرق آخر')),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: InputDecoration(
                      labelText: 'وضح الفرق *', errorText: error)),
            ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('رجوع')),
              EbrokerFilledButton(
                  onPressed: () {
                    final text = note.text.trim();
                    if (text.length < 10) {
                      setDialogState(
                          () => error = 'اكتب توضيحاً من 10 أحرف على الأقل.');
                      return;
                    }
                    Navigator.pop(dialogContext, (type, text));
                  },
                  child: const Text('أؤكد أنه عقار مختلف')),
            ],
          ),
        ),
      ),
    );
    note.dispose();
    return result;
  }

  Future<void> _pickLandBoundary() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) {
      _message('حدد موقع الأرض أولاً.');
      return;
    }
    final selection =
        await Navigator.of(context).push<PropertyLandBoundarySelection>(
      MaterialPageRoute(
          builder: (_) => PropertyLandBoundaryPickerScreen(
                initialLatitude: latitude,
                initialLongitude: longitude,
                initialBoundary: _landBoundaryGeoJson,
              )),
    );
    if (selection != null && mounted) {
      setState(() => _landBoundaryGeoJson = selection.geoJson);
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
    _replaceImages = false;
    _ownershipProofPath = null;
    try {
      await _mediaPicker.clearTemporaryFiles(paths.where((path) => !ListingRecoveryStore.isSavedMedia(path)));
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
            20,
            10,
            20,
            16,
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}

class _FinalActionsBar extends StatelessWidget {
  const _FinalActionsBar({required this.busy, required this.onPrevious,
    required this.onPreview, required this.onSaveDraft, required this.onSubmit});
  final bool busy;
  final VoidCallback onPrevious, onPreview, onSaveDraft, onSubmit;
  @override
  Widget build(BuildContext context) => Material(color: Theme.of(context).colorScheme.surface,
    elevation: AppElevation.floating, child: SafeArea(top: false, child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 10, 18, 12),
      child: Row(children: [
        Expanded(child: EbrokerStepButton(label: 'إرسال للمراجعة', icon: Icons.send_outlined,
          loading: busy, onPressed: busy ? null : onSubmit, expand: true)),
        const SizedBox(width: 8),
        PopupMenuButton<String>(tooltip: 'خيارات المسودة', enabled: !busy,
          icon: const EbrokerIcon(Icons.more_horiz, size: 22),
          onSelected: (value) { switch (value) {
            case 'save': onSaveDraft(); break;
            case 'preview': onPreview(); break;
            case 'previous': onPrevious(); break;
          } },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'save', child: Semantics(label: 'حفظ مسودة', excludeSemantics: true, child: Text('حفظ مسودة'))),
            PopupMenuItem(value: 'preview', child: Semantics(label: 'معاينة', excludeSemantics: true, child: Text('معاينة'))),
            PopupMenuItem(value: 'previous', child: Text('السابق')),
          ]),
      ]))));
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
