import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../data/listing_account_draft_repository.dart';
import '../domain/listing_account_draft.dart';
import '../domain/property_schema.dart';
import 'listing_draft_photo.dart';

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
import 'listing_ai_sheet.dart';
import 'rental_conditions_editor.dart';
import '../../discovery/data/ai_repository.dart';

class ListingEditorScreen extends ConsumerStatefulWidget {
  const ListingEditorScreen({super.key, this.existingProperty, this.accountDraft, this.startFresh = false});

  final ListingAccountDraft? accountDraft;
  final bool startFresh;

  final PropertyDetails? existingProperty;

  @override
  ConsumerState<ListingEditorScreen> createState() =>
      _ListingEditorScreenState();
}

class _ListingEditorScreenState extends ConsumerState<ListingEditorScreen> with WidgetsBindingObserver {
  static const _typeLabels = <String, String>{
    'apartment': 'شقة',
    'building': 'عمارة',
    'house': 'منزل',
    'villa': 'فيلا',
    'land': 'أرض',
    'shop': 'محل',
    'office': 'مكتب',
    'farm': 'مزرعة',
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
  final _assistantBrief = TextEditingController();
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
  String? _elevatorChoice;
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
  final _saiRate = TextEditingController();
  final _saiAmount = TextEditingController();
  String _saiAmountType = 'percentage';
  PropertySaiManagement? _saiPolicy;
  String? _saiPolicyError;
  bool _saiAccepted = false, _saiTouched = false, _hasRecoveredSai = false;
  bool _wholeFloor = false; // Read-only identity for existing legacy whole-floor listings.
  List<Map<String, dynamic>> _rentalConditions = [];
  bool _existingSaiLoaded = false;
  int _saiPolicyRequest = 0;
  String _priceDisplayMode = 'excludes_sai';

  Timer? _recoveryTimer;
  late ListingRecoveryStore _recoveryStore;
  int? _recoveryUserId, _recoveredServerId;
  bool _recoveryReady = false, _recoveryFinished = false, _recoverySaved = false, _recoveryFailed = false;
  String? _lastRecoverySignature;
  late ListingAccountDraftRepository _accountRepository;
  late String _draftKey;
  int _draftRevision = 0;
  bool _accountSaved = false, _accountSyncing = false, _accountConflict = false;
  String? _accountError, _descriptionError;
  bool _descriptionBusy = false, _typeConfirmed = false, _purposeConfirmed = false, _completionOnly = false;
  Set<String> _completionFields = {};
  final _remotePhotos = <String, String>{}, _localPhotoKeys = <String, String>{};
  final _removedPhotoKeys = <String>{};
  List<String> _photoOrder = [];
  (Map<String, dynamic>, Map<String, String>)? _pendingAccount;
  Future<void> _accountTail = Future<void>.value();

  List<String> get _photoKeys {
    final active = <String>{..._remotePhotos.keys.where((k) => !_removedPhotoKeys.contains(k)),
      for (final path in _imagePaths) _localPhotoKeys.putIfAbsent(path, newListingDraftKey)};
    return [..._photoOrder.where(active.remove), ...active];
  }
  int get _effectiveImageCount => (_replaceImages ? 0 : (_existing?.images.length ?? 0)) + _photoKeys.length;

  void _adoptAccountDraft(ListingAccountDraft draft) {
    _draftRevision = draft.revision;
    _remotePhotos..clear()..addAll(draft.images);
    _recoveredServerId = draft.propertyId ?? _recoveredServerId;
  }

  Map<String, dynamic> _serverSnapshot(Map<String, dynamic> snapshot) {
    final data = Map<String, dynamic>.from(jsonDecode(jsonEncode(snapshot)) as Map);
    data.remove('draft_key'); data.remove('server_revision'); data.remove('image_tokens');
    final fields = Map<String, dynamic>.from(data['fields'] as Map);
    const aliases = {'area':'area_value','parking':'has_parking','elevator':'has_elevator','facade':'building_facade','land_boundary':'land_boundary_geojson'};
    for (final key in fields.keys.toList()) { if (!DynamicPropertySchema.applies(aliases[key] ?? key, data)) fields.remove(key); }
    for (final key in data.keys.toList()) { if (!DynamicPropertySchema.applies(aliases[key] ?? key, data)) data.remove(key); }
    if (!DynamicPropertySchema.applies('area_value', data)) data.remove('area_unit');
    if (data['purpose'] == 'rent') fields.remove('price');
    data['fields'] = fields;
    return data;
  }

  Future<void> _saveAccount(Map<String, dynamic> snapshot, Map<String, String> photos) {
    if (_accountConflict) return _accountTail;
    _pendingAccount = (_serverSnapshot(snapshot), Map.of(photos));
    _accountSaved = false;
    if (_accountSyncing) return _accountTail;
    _accountSyncing = true;
    _accountTail = () async {
      try {
        while (_pendingAccount != null) {
          final pending = _pendingAccount!; _pendingAccount = null;
          var draft = await _accountRepository.save(_draftKey, pending.$1, _draftRevision,
            propertyId: _existing?.id ?? _recoveredServerId);
          _adoptAccountDraft(draft);
          final order = (pending.$1['image_order'] as List? ?? const []).whereType<String>().toSet();
          for (final key in _remotePhotos.keys.toList()) {
            if (order.contains(key)) continue;
            draft = await _accountRepository.removeImage(_draftKey, key, _draftRevision); _adoptAccountDraft(draft);
          }
          for (final photo in pending.$2.entries) {
            if (_remotePhotos.containsKey(photo.key) || !order.contains(photo.key)) continue;
            draft = await _accountRepository.upload(_draftKey, photo.key, photo.value, _draftRevision); _adoptAccountDraft(draft);
          }
        }
        _accountSaved = true; _accountError = null;
      } catch (e) {
        _accountSaved = false; _accountError = friendlyApiError(e);
        _accountConflict = e is DioException && e.response?.statusCode == 409;
      } finally {
        _accountSyncing = false;
        if (mounted) super.setState(() {});
      }
    }();
    return _accountTail;
  }

  void _clearHiddenFields() {
    if (!_applies('tenure_type')) _tenureType = null;
    if (!_applies('bedrooms')) _bedrooms.clear();
    if (!_applies('bathrooms')) _bathrooms.clear();
    if (!_applies('has_parking')) _parkingChoice = null;
    if (!_applies('has_elevator')) _elevatorChoice = null;
    if (!_applies('building_facade')) _facade = null;
    if (!_applies('floor_number')) _floorNumber.clear();
    if (!_applies('unit_number')) _unitNumber.clear();
    if (!_applies('building_reference')) _buildingReference.clear();
    if (!_applies('area_value')) { _area.clear(); _areaUnit = 'sqm'; }
    if (_type == 'shop' && _areaUnit != 'sqm') {
      final area = double.tryParse(_area.text);
      if (area != null) _area.text = formatPropertyAreaValue(area * (propertyAreaUnitSquareMetres[_areaUnit] ?? 1));
      _areaUnit = 'sqm';
    }
    if (!_applies('rental_conditions')) { _rentalConditions = []; _advanceMonths.clear(); _rentalTermMonths.clear(); }
    if (!_applies('land_boundary_geojson')) _landBoundaryGeoJson = null;
    if (!_applies('broker_sai_rate_percent')) _saiRate.clear();
    if (!_applies('fixed_sai_amount')) _saiAmount.clear();
  }

  Widget _floorSelector() {
    final value = _floorNumber.text.trim(), options = DynamicPropertySchema.floorOptions;
    return DropdownButtonFormField<String>(key: const ValueKey('listing-floor-select'), value: value.isEmpty ? null : value,
      isExpanded: true, decoration: InputDecoration(labelText: _type == 'apartment' ? 'الشقة في الدور *' : 'الدور *'),
      items: [for (final entry in options.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        if (value.isNotEmpty && !options.containsKey(value)) DropdownMenuItem(value: value, child: Text(value))],
      onChanged: _busy ? null : (value) => setState(() => _floorNumber.text = value ?? ''));
  }

  Future<void> _generateDescription() async {
    if (_descriptionBusy || _busy) return;
    final facts = _aiFacts(), before = _description.text, signature = jsonEncode(_aiFacts());
    setState(() { _descriptionBusy = true; _descriptionError = null; });
    try {
      final result = await ref.read(aiRepositoryProvider).description(facts,
        propertyId: _existing?.id ?? _recoveredServerId, draftKey: _draftRevision > 0 ? _draftKey : null);
      if (!mounted) return;
      if (_description.text != before || jsonEncode(_aiFacts()) != signature) {
        setState(() => _descriptionError = 'تغيرت بيانات الإعلان أو الوصف أثناء التجهيز. أعد الطلب عند الحاجة.'); return;
      }
      final text = result['description'];
      if (text is! String || text.trim().isEmpty || text.length > 5000) throw StateError('تعذر تجهيز الوصف.');
      setState(() => _description.text = text);
    } catch (e) { if (mounted) setState(() => _descriptionError = friendlyApiError(e)); }
    finally { if (mounted) setState(() => _descriptionBusy = false); }
  }

  Set<String> _missingFields() {
    final facts = {..._aiFacts(), 'type':_type, 'purpose':_purpose, 'latitude':_latitude, 'longitude':_longitude};
    final required = {...DynamicPropertySchema.required(_schemaContext), 'title','governorate','latitude','longitude','price'};
    final result = <String>{};
    for (final key in required) {
      final value = key == 'price' ? _effectivePrice : facts[key];
      if (value == null || value == '' || (const ['area_value','price','bedrooms','bathrooms'].contains(key) && (value is! num || value <= 0))) result.add(key);
    }
    if (!_typeConfirmed) result.add('type'); if (!_purposeConfirmed) result.add('purpose');
    if (_effectiveImageCount == 0) result.add('photos');
    if (!_isSaiReady) result.add('sai');
    if (_ownershipValidation() != null) result.add('ownership');
    if (_type == 'land' && _landBoundaryGeoJson == null) result.add('boundary');
    return result;
  }

  Widget _completionStep() {
    final keys = _completionFields;
    Widget text(String key, TextEditingController controller, String label, {bool numeric = false}) =>
      !keys.contains(key) ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: AppTextField(
        controller: controller, label: label, enabled: !_busy, keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text));
    Widget choice(String key, String label, String? value, Map<String,String> options, ValueChanged<String?> change) => !keys.contains(key)
      ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: DropdownButtonFormField<String>(
        value: value, isExpanded: true, decoration: InputDecoration(labelText: label),
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: _busy ? null : change));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('أكمل الناقص فقط', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
      const Text('نقلنا المعلومات التي راجعتها إلى المسودة. أكمل البيانات المطلوبة ثم راجع الإعلان وأرسله.'),
      choice('type','أكد نوع العقار',_typeConfirmed ? _type : null,_typeLabels,(v) => setState(() { _type = v!; _typeConfirmed = true; _clearHiddenFields(); _completionFields = _missingFields(); })),
      choice('purpose','أكد الغرض',_purposeConfirmed ? _purpose : null,const {'sale':'للبيع','rent':'للإيجار'},(v) => setState(() {
        _purpose = v!; _purposeConfirmed = true; _clearHiddenFields(); _completionFields = _missingFields(); unawaited(_loadSaiPolicy()); })),
      if (_typeConfirmed && _purposeConfirmed) ...[
        text('title',_title,'عنوان الإعلان *'),
        if (_requiresSaleTenure) choice('tenure_type','نوع الملكية *',_tenureType,const {'freehold':'حر','waqf':'وقف'},(v) => setState(() => _tenureType = v)),
        text('governorate',_governorate,'المحافظة *'),
        if (keys.contains('latitude') || keys.contains('longitude')) ...[
          const SizedBox(height: 12), Text(_latitude == null ? 'أكد نقطة العقار على الخريطة؛ لن نخمن موقعه.' : 'تم تحديد نقطة العقار.'),
          TextButton.icon(onPressed: _busy ? null : _selectOnMap, icon: const Icon(Icons.location_on_outlined), label: const Text('تأكيد الموقع على الخريطة')),
        ],
        if (keys.contains('boundary')) TextButton(onPressed: _busy ? null : _pickLandBoundary, child: const Text('تحديد حدود الأرض')),
        if (keys.contains('floor_number') && _unitNeedsFloor) Padding(padding: const EdgeInsets.only(top: 12), child: _floorSelector()),
        if (_applies('unit_number')) text('unit_number',_unitNumber,'رقم الوحدة أو موضعها *'),
        if (_applies('area_value')) text('area_value',_area,_type == 'shop' ? 'المساحة بالمتر المربع *' : 'المساحة *',numeric:true),
        if (_requiresResidential) ...[text('bedrooms',_bedrooms,'غرف النوم *',numeric:true),text('bathrooms',_bathrooms,'الحمامات *',numeric:true)],
        if (_requiresStructure) choice('has_parking','موقف السيارة *',_parkingChoice,const {'yes':'يوجد','no':'لا يوجد'},(v) => setState(() => _parkingChoice = v)),
        if (_supportsFacade) choice('building_facade','واجهة البناء *',_facade,propertyFacadeLabels,(v) => setState(() => _facade = v)),
        text('price',_purpose == 'rent' ? _monthlyRent : _price,_purpose == 'rent' ? 'الإيجار الشهري بالريال اليمني *' : 'سعر البيع بالريال اليمني *',numeric:true),
        if (keys.contains('photos')) ...[const SizedBox(height: 16), _listingPhotos(), const Text('ارفع صورًا حقيقية للعقار.')],
        if (keys.contains('sai')) ListingSaiSection(purpose:_purpose,policy:_saiPolicy,rateController:_saiRate,amountController:_saiAmount,
          basis:_effectivePrice,amountType:_saiAmountType,accepted:_saiAccepted,error:_saiPolicyError,enabled:!_busy,
          onChanged:() => setState(() => _saiTouched = true),onAcceptanceChanged:(v) => setState(() => _saiAccepted = v),
          onAmountTypeChanged:(v) => setState(() { _saiAmountType=v;_saiTouched=true; }),onRetry:_loadSaiPolicy),
        if (keys.contains('ownership')) _ownershipEvidence(),
      ],
      const SizedBox(height: 20),
      TextButton(onPressed: _busy ? null : () => setState(() => _completionOnly = false), child: const Text('مراجعة وتعديل كل الحقول')),
    ]);
  }

  Widget _completionActions() => _FinalActionsBar(busy:_busy,
    onPrevious:() => setState(() => _completionOnly = false),onPreview:_preview,
    onSaveDraft:() => _persist(submit:false),onSubmit:() => _persist(submit:true));

  Map<String, TextEditingController> get _recoveryFields => {
    'broker_sai_rate_percent': _saiRate,
    'fixed_sai_amount': _saiAmount,
    'title': _title, 'description': _description, 'ai_listing_brief': _assistantBrief, 'price': _price, 'monthly_rent': _monthlyRent,
    'rental_term_months': _rentalTermMonths, 'advance_months': _advanceMonths, 'area': _area,
    'bedrooms': _bedrooms, 'bathrooms': _bathrooms, 'governorate': _governorate, 'district': _district,
    'street': _street, 'building_reference': _buildingReference, 'unit_number': _unitNumber,
    'floor_number': _floorNumber, 'phone': _phone, 'whatsapp': _whatsapp,
    'document_owner_name': _documentOwnerName, 'relationship_note': _relationshipNote,
  };

  Map<String, dynamic> _recoverySnapshot() => {
    'editor_version': 8, 'sai_amount_type': _saiAmountType, 'rental_conditions': _rentalConditions, 'unit_occupies_entire_floor': _wholeFloor, 'sai_touched': _saiTouched, 'sai_terms_accepted': _saiAccepted,
    'type_confirmed': _typeConfirmed, 'purpose_confirmed': _purposeConfirmed, 'completion_only': _completionOnly,
    'draft_key': _draftKey, 'server_revision': _draftRevision, 'image_tokens': _localPhotoKeys, 'image_order': _photoKeys,
    'step': _step, 'purpose': _purpose, 'type': _type, 'area_unit': _areaUnit,
    'tenure_type': _tenureType, 'parking': _parkingChoice, 'elevator': _elevatorChoice, 'facade': _facade,
    'ownership_document_type': _ownershipDocumentType, 'relationship_type': _relationshipType,
    'latitude': _latitude, 'longitude': _longitude, 'land_boundary': _landBoundaryGeoJson,
    'replace_images': _replaceImages, 'price_display_mode': _priceDisplayMode,
    'server_property_id': _existing?.id ?? _recoveredServerId,
    'proof_needs_reselection': _ownershipProofPath != null,
    'fields': {for (final entry in _recoveryFields.entries) entry.key: entry.value.text},
  };

  @override
  void setState(VoidCallback fn) { super.setState(() { fn(); _clearHiddenFields(); }); _scheduleRecovery(); }

  void _scheduleRecovery() {
    if (!_recoveryReady || _recoveryFinished || _recoveryUserId == null || _busy) return;
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(milliseconds: 650), () => unawaited(_saveRecovery()));
  }

  Future<void> _saveRecovery() async {
    final userId = _recoveryUserId;
    if (userId == null || !_recoveryReady || _recoveryFinished) return;
    final data = _recoverySnapshot(), images = List<String>.of(_imagePaths);
    final signature = jsonEncode([data, images]);
    if (signature == _lastRecoverySignature && _accountSaved) return;
    try {
      await _recoveryStore.write(userId, widget.existingProperty?.id, data, images);
      _lastRecoverySignature = signature;
      if (mounted && !_recoveryFinished) super.setState(() { _recoverySaved = true; _recoveryFailed = false; });
    } catch (_) { if (mounted) super.setState(() => _recoveryFailed = true); }
    await _saveAccount(data, {for (final path in images) _localPhotoKeys[path]!: path});
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
    final data = widget.accountDraft?.payload ?? (widget.startFresh ? null : await _recoveryStore.read(userId, widget.existingProperty?.id));
    if (!mounted) return;
    if (data != null) {
      if (widget.accountDraft == null && data['draft_key'] is String) _draftKey = data['draft_key'] as String;
      if (widget.accountDraft == null && data['server_revision'] is int) _draftRevision = data['server_revision'] as int;
      _typeConfirmed = data['type_confirmed'] == true || ((data['editor_version'] as num? ?? 0) < 8); _purposeConfirmed = data['purpose_confirmed'] == true || ((data['editor_version'] as num? ?? 0) < 8);
      _completionOnly = data['completion_only'] == true;
      if (data['image_tokens'] is Map) _localPhotoKeys.addAll(Map<String,String>.from(data['image_tokens'] as Map));
      _photoOrder = (data['image_order'] as List? ?? const []).whereType<String>().toList();
      final fields = data['fields'];
      if (data['rental_conditions'] is List) _rentalConditions = (data['rental_conditions'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _step = (data['step'] is int ? data['step'] as int : 0).clamp(0, 3).toInt();
      if (const ['sale', 'rent'].contains(data['purpose'])) _purpose = data['purpose'] as String;
      if (_typeLabels.containsKey(data['type'])) _type = data['type'] as String;
      if (data['type'] == 'floor') _type = 'apartment';
      _wholeFloor = _type == 'apartment' && (widget.existingProperty != null || data['server_property_id'] is int) && (data['type'] == 'floor' || data['unit_occupies_entire_floor'] == true);
      if (propertyAreaUnitLabels.containsKey(data['area_unit'])) _areaUnit = data['area_unit'] as String;
      _tenureType = const ['freehold', 'waqf'].contains(data['tenure_type']) ? data['tenure_type'] as String : null;
      _parkingChoice = const ['yes', 'no'].contains(data['parking']) ? data['parking'] as String : null;
      _elevatorChoice = const ['yes', 'no'].contains(data['elevator']) ? data['elevator'] as String : null;
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
      if (const ['percentage', 'fixed'].contains(data['sai_amount_type'])) _saiAmountType = data['sai_amount_type'] as String;
      final saiField = _saiAmountType == 'fixed' ? 'fixed_sai_amount' : 'broker_sai_rate_percent';
      _hasRecoveredSai = data['sai_touched'] == true && fields is Map && (fields[saiField]?.toString().trim().isNotEmpty ?? false);
      _saiTouched = _hasRecoveredSai;
      if (_hasRecoveredSai) _saiAccepted = data['sai_terms_accepted'] == true;

      if (fields is Map) {
        for (final entry in _recoveryFields.entries) {
          if (const ['broker_sai_rate_percent', 'fixed_sai_amount'].contains(entry.key) && data['sai_touched'] != true) continue;
          final text = fields[entry.key]; if (text is String) entry.value.text = text;
        }
      }
      if (_purpose == 'rent' && data['rental_conditions'] is! List) {
        _rentalConditions = [
          if (int.tryParse(_advanceMonths.text) case final int months when months > 0) {'kind': 'advance', 'months': months},
          if (int.tryParse(_rentalTermMonths.text) case final int months when months > 0) {'kind': 'duration', 'months': months},
        ];
      }

      _recoverySaved = true;
      if (data['proof_needs_reselection'] == true) _message('استعدنا بيانات الإعلان. أعد اختيار ملف إثبات الملكية عند إكمال المسودة.');
    }
    _clearHiddenFields();
    if (_completionOnly) _completionFields = _missingFields();
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
  double get _enteredSaiRate => parseSaiNumber(_saiRate.text) ?? double.nan;
  double get _enteredSaiAmount => parseSaiNumber(_saiAmount.text) ?? double.nan;
  bool get _fixedSai => _saiAmountType == 'fixed' && _saiPolicy?.isOwner != true;
  double get _activeSaiValue => _fixedSai ? _enteredSaiAmount : _enteredSaiRate;
  String? get _inlineSaiValidation {
    final policy = _saiPolicy;
    if (policy == null) return 'تعذر تحميل سياسة السعي. أعد تحميلها قبل الإرسال.';
    if (policy.isOwner) return null;
    if (_isEditing && !_existingSaiLoaded && !_saiTouched && !_hasRecoveredSai) return 'انتظر تحميل السعي الحالي أو حدد النسبة بنفسك.';
    if (_fixedSai) {
      final amount = _enteredSaiAmount, basis = _effectivePrice;
      final maximum = basis == null ? null : (basis * (policy.brokerMaxRatePercent ?? -1)).round() / 100;
      if (!amount.isFinite || amount < 0 || maximum == null || amount > maximum ||
          (amount * 100 - (amount * 100).round()).abs() > .000001) {
        return 'أدخل مبلغ سعي صحيحًا ضمن الحد المسموح وبدقتين عشريتين على الأكثر.';
      }
      return null;
    }
    final rate = _enteredSaiRate, maximum = policy.brokerMaxRatePercent;
    if (!rate.isFinite || rate < 0 || maximum == null || rate > maximum || (rate * 100 - (rate * 100).round()).abs() > .000001) {
      return 'أدخل نسبة سعي صحيحة ضمن الحد المسموح وبدقتين عشريتين على الأكثر.';
    }
    return null;
  }
  String get _saiDisplayText {
    final policy = _saiPolicy;
    if (policy == null) return 'سياسة السعي غير محملة';
    if (_fixedSai && _enteredSaiAmount.isFinite && _enteredSaiAmount > 0) {
      return 'السعي ${_enteredSaiAmount.toStringAsFixed(2)} ريال · يتحمله ${_purpose == 'rent' ? 'المستأجر' : 'المشتري'}';
    }
    final rate = policy.isOwner || _enteredSaiRate == 0 ? policy.fixedRatePercent : _enteredSaiRate;
    return 'السعي ${rate ?? '—'}% · يتحمله ${_purpose == 'rent' ? 'المستأجر' : 'المشتري'}';
  }
  Map<String, dynamic> get _schemaContext => {'type': _type, 'purpose': _purpose, 'unit_occupies_entire_floor': _wholeFloor, 'sai_amount_type': _saiAmountType};
  bool _applies(String key) => DynamicPropertySchema.applies(key, _schemaContext);
  bool get _requiresSaleTenure => _applies('tenure_type');
  bool get _requiresResidential => _applies('bedrooms');
  bool get _supportsFacade => _applies('building_facade');
  bool get _requiresStructure => _applies('has_parking');
  bool get _supportsElevator => _applies('has_elevator');
  bool get _isUnitType => _applies('unit_number') || _applies('floor_number');
  bool get _unitNeedsFloor => _applies('floor_number');
  bool? get _parkingValue =>
      _parkingChoice == null ? null : _parkingChoice == 'yes';
  bool get _isRentalApartment => _type == 'apartment' && _purpose == 'rent';

  double? get _effectivePrice {
    if (_purpose == 'rent') {
      final monthly = double.tryParse(_monthlyRent.text.trim());
      return monthly != null && monthly > 0 ? monthly : null;
    }
    return double.tryParse(_price.text.trim());
  }

  String get _priceSummaryText {
    if (_purpose == 'rent') {
      final monthly = _monthlyRent.text.trim();
      return monthly.isEmpty
          ? '—'
          : '$monthly YER شهرياً';
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
    _accountRepository = ref.read(listingAccountDraftRepositoryProvider);
    _draftKey = widget.accountDraft?.key ?? newListingDraftKey();
    if (widget.accountDraft != null) _adoptAccountDraft(widget.accountDraft!);
    _typeConfirmed = widget.existingProperty != null; _purposeConfirmed = widget.existingProperty != null;
    _recoveryUserId = ref.read(authControllerProvider).asData?.value?.id;
    Future.microtask(() async { await _restoreRecovery(); if (mounted) await _loadSaiPolicy(); });
    for (final controller in _recoveryFields.values) { controller.addListener(_scheduleRecovery); }
    final property = _existing;
    if (property == null) return;

    _purpose = property.purpose;
    _type = property.type == 'floor' ? 'apartment' : property.type;
    _wholeFloor = _type == 'apartment' && property.unitOccupiesEntireFloor;
    _tenureType = property.tenureType;
    _title.text = property.title;
    _description.text = property.description ?? '';
    _price.text = property.editablePrice.toStringAsFixed(0);
    _monthlyRent.text = property.monthlyRent?.toStringAsFixed(0) ?? '';
    _rentalConditions = property.rentalConditions.map((e) => Map<String, dynamic>.from(e)).toList();
    if (_purpose == 'rent' && _rentalConditions.isEmpty) {
      if (property.advanceMonths != null) _rentalConditions.add({'kind': 'advance', 'months': property.advanceMonths});
      if (property.rentalTermMonths != null) _rentalConditions.add({'kind': 'duration', 'months': property.rentalTermMonths});
    }
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
    _elevatorChoice = property.hasElevator == null ? null : property.hasElevator! ? 'yes' : 'no';
    final address = PropertyLocationAddress.fromStoredAddress(property.address);
    _governorate.text = address.governorate ?? '';
    _district.text = address.district ?? '';
    _street.text = address.street ?? '';
    _latitude = property.latitude;
    _longitude = property.longitude;
    _buildingReference.text = property.buildingReference ?? '';
    _unitNumber.text = property.unitNumber ?? '';
    _floorNumber.text = property.floorNumber ?? '';

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
      _saiAmount,
      _title,
      _description,
      _assistantBrief,
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
          actions: [IconButton(key: const ValueKey('listing-completion'), tooltip: 'نواقص الإعلان',
            onPressed: _busy ? null : _reviewCompletion, icon: const EbrokerIcon(Icons.fact_check_outlined)),
            Center(child: Padding(padding: const EdgeInsetsDirectional.only(end: 16),
            child: EbrokerText('${_step + 1}/4', size: 16, weight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary)))],
        ),
        body: SafeArea(
          child: !_recoveryReady ? const AppLoadingState() : Column(
            children: [
              if (_recoveryUserId != null) Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 0), child: Text(
                _recoveryFailed && _accountError != null ? 'تعذر الحفظ على الجهاز والحساب. أعد المحاولة قبل الخروج.' : _accountConflict ? 'تغيرت المسودة على جهاز آخر. افتح أحدث نسخة قبل المتابعة.' : _accountError != null ? 'تعذر الحفظ على الحساب. ${_recoverySaved ? 'تقدمك محفوظ على الجهاز.' : ''} أعد المحاولة.' : _accountSyncing ? 'جارٍ حفظ تقدمك على حسابك…' : _accountSaved ? 'حُفظ تقدمك وصورك على حسابك' : 'يُحفظ تقدمك تلقائيًا على حسابك',
                style: Theme.of(context).textTheme.bodySmall)),
              if (_accountError != null && !_accountConflict) TextButton(onPressed: _busy ? null : _saveRecovery, child: const Text('إعادة محاولة الحفظ')),
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
              _completionOnly ? _completionActions() : _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => _completionOnly ? _completionStep() : switch (_step) {
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
        AppSurface(key: const ValueKey('listing-draft-assistant-entry'), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('جهّز إعلانك أسرع', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('صف العقار بالنص أو الصوت، وراجع مسودة مرتبة قبل إكمالها.'),
            TextButton.icon(key: const ValueKey('listing-draft-assistant'),
              onPressed: _busy ? null : () => _assist(prepareDraft: true),
              icon: const EbrokerIcon(Icons.auto_awesome_outlined, size: 20), label: const Text('جهّز الإعلان بالصوت أو المساعد')),
          ])),
        const SizedBox(height: AppSpacing.s16),
        const AppSectionHeader(
          title: 'نوع الإعلان والعقار',
          subtitle: 'اختر الغرض والنوع واكتب عنوانًا واضحًا.',
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
                    _purpose = values.first; _purposeConfirmed = true;
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
                            if (_type != entry.key) _wholeFloor = false;
                            _type = entry.key; _typeConfirmed = true;
                            if (!_supportsElevator) _elevatorChoice = null;

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
          Text(_type == 'shop' ? 'حدد المحل بوضوح' : 'أين الوحدة داخل المبنى؟',
            style: Theme.of(context).textTheme.titleSmall),
          if (_unitNeedsFloor) ...[
            const SizedBox(height: 12),
            _floorSelector(),
          ],
          if (!_wholeFloor) ...[
            const SizedBox(height: 12),
            AppTextField(controller: _unitNumber,
              label: _type == 'shop' ? 'اسم أو رقم المحل أو موضعه *' : _isRentalApartment ? 'موضع الشقة داخل الدور (اختياري)' : _type == 'apartment' ? 'رقم الشقة أو موضعها داخل الدور *' : 'رقم المكتب أو موضعه *',
              hint: _type == 'shop' ? 'مثال: المحل الأمامي بجوار المدخل' : 'مثال: 7 أو شمالية أو أمامية', enabled: !_busy),
          ],
        ],
        const SizedBox(height: AppSpacing.s16),
        if (!_isRentalApartment)
          _type == 'shop' ? AppTextField(controller: _area, label: 'المساحة بالمتر المربع *',
            keyboardType: const TextInputType.numberWithOptions(decimal: true), enabled: !_busy)
          : LayoutBuilder(builder: (context, constraints) {
            final area = AppTextField(controller: _area,
              label: _areaUnit == 'sqm' ? 'المساحة *' : 'عدد الوحدات *',
              keyboardType: const TextInputType.numberWithOptions(decimal: true), enabled: !_busy);
            final unit = DropdownButtonFormField<String>(value: _areaUnit, isExpanded: true,
              decoration: const InputDecoration(labelText: 'وحدة المساحة'),
              items: propertyAreaUnitLabels.entries.map((entry) => DropdownMenuItem(value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis))).toList(growable: false),
              onChanged: _busy ? null : (value) => setState(() => _areaUnit = value ?? 'sqm'));
            return MediaQuery.textScalerOf(context).scale(14) > 21
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [area, const SizedBox(height: 12), unit])
              : Row(children: [Expanded(flex: 2, child: area), const SizedBox(width: 8), Expanded(flex: 3, child: unit)]);
          }),
        if (_requiresResidential) ...[
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _bedrooms,
                  label: 'غرف النوم *',
                  hint: 'مثال: 3',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: AppTextField(
                  controller: _bathrooms,
                  label: 'الحمامات *',
                  hint: 'مثال: 2',
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                ),
              ),
            ],
          ),
        ],
        if (_supportsElevator) ...[
          const SizedBox(height: AppSpacing.s16),
          DropdownButtonFormField<String>(value: _elevatorChoice ?? 'unknown', isExpanded: true,
            decoration: const InputDecoration(labelText: 'المصعد'), items: const [
              DropdownMenuItem(value: 'unknown', child: Text('غير مذكور')),
              DropdownMenuItem(value: 'yes', child: Text('يوجد مصعد')),
              DropdownMenuItem(value: 'no', child: Text('بدون مصعد')),
            ], onChanged: _busy ? null : (value) => setState(() => _elevatorChoice = value == 'unknown' ? null : value)),
        ],
        if (_requiresStructure) ...[
          const SizedBox(height: AppSpacing.s16),
          DropdownButtonFormField<String>(
            value: _parkingChoice, isExpanded: true,
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
            value: _facade, isExpanded: true,
            decoration: const InputDecoration(labelText: 'واجهة البناء *'),
            items: propertyFacadeLabels.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(growable: false),
            onChanged:
                _busy ? null : (value) => setState(() => _facade = value),
          ),
        ],
        if (_type == 'land') ...[const SizedBox(height: 12), DropdownButtonFormField<String>(value: _facade, isExpanded: true,
          decoration: const InputDecoration(labelText: 'واجهة الأرض (اختياري)'), items: propertyFacadeLabels.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
          onChanged: _busy ? null : (value) => setState(() => _facade = value))],
        const SizedBox(height: 24),
        _listingPhotos(),
        const SizedBox(height: 8),
        const Text('يجب أن تكون الصور حقيقية للعقار المعلن عنه.'),
        const SizedBox(height: 20),
        AppTextField(controller: _description, label: 'وصف العقار',
          hint: 'اكتب ما يميز العقار أو استخدم وصفًا مقترحًا من مواصفاتك.', enabled: !_busy, maxLines: 5),
        if (_descriptionBusy) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Expanded(child: Text('جارٍ تجهيز الوصف…'))])),
        if (_descriptionError != null) Text(_descriptionError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton.icon(onPressed: _busy || _descriptionBusy ? null : _generateDescription,
          icon: const EbrokerIcon(Icons.edit_note_outlined, size: 18), label: const Text('إنشاء وصف بالذكاء الاصطناعي')),
        if (_purpose == 'rent') RentalConditionsEditor(value: _rentalConditions, enabled: !_busy, onPolish: _polishRentalConditions,
          onChanged: (value) => setState(() => _rentalConditions = value)),
      ],
    );
  }

  Widget _priceStep() {
    final wordsSource = _purpose == 'rent' ? _monthlyRent.text : _price.text;
    final amountWords = arabicRiyalAmountInWords(wordsSource) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: _purpose == 'rent' ? 'الإيجار والتواصل' : 'السعر والتواصل',
          subtitle: _purpose == 'rent'
              ? 'حدد الإيجار الشهري ووسائل التواصل.'
              : 'حدد السعر ووسائل التواصل التي تريد إظهارها للمهتمين.',
        ),
        const SizedBox(height: AppSpacing.s16),
        if (_purpose == 'sale')
          AppTextField(
            controller: _price,
            label: 'سعر البيع بالريال اليمني *',
            hint: '0',
            helperText: amountWords.isEmpty ? null : amountWords,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_busy,
          )
        else ...[
          AppTextField(
            controller: _monthlyRent,
            label: 'الإيجار الشهري بالريال اليمني *',
            hint: '0',
            helperText: amountWords.isEmpty ? null : amountWords,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_busy,
          ),
        ],
        ListingSaiSection(purpose: _purpose, policy: _saiPolicy, rateController: _saiRate,
          amountController: _saiAmount, amountType: _saiAmountType,
          onAmountTypeChanged: (value) => setState(() { _saiAmountType = value; _saiTouched = true; }),
          basis: _purpose == 'rent' ? double.tryParse(_monthlyRent.text.trim()) : _effectivePrice,
          accepted: _saiAccepted, error: _saiPolicyError, enabled: !_busy,
          onRetry: () => unawaited(_loadSaiPolicy()),
          onChanged: () => setState(() => _saiTouched = true),
          onAcceptanceChanged: (value) => setState(() { _saiAccepted = value; _saiTouched = true; })),
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
    final existingImages = _existing?.images.length ?? 0, keys = _photoKeys;
    return AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('صور الإعلان ($_effectiveImageCount/12)',style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      AppButton(label:'إضافة صور',icon:Icons.add_photo_alternate_outlined,expand:true,style:AppButtonStyle.tonal,onPressed:_busy?null:_pickImages),
      if (_isEditing && existingImages > 0) SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,
        title:const Text('استبدال الصور الحالية بالكامل'), value:_replaceImages,
        onChanged:_busy ? null : (v) => setState(() => _replaceImages=v)),
      if (!_replaceImages && existingImages > 0) SizedBox(height:110, child:ListView.separated(scrollDirection:Axis.horizontal,
        itemCount:existingImages,separatorBuilder:(_,__) => const SizedBox(width:8),itemBuilder:(_,index) => SizedBox(width:140,
          child:AppPropertyMedia(imageUrl:_existing!.images[index].url,height:110)))),
      if (keys.isNotEmpty) ...[
        const SizedBox(height:12),SizedBox(height:118,child:ReorderableListView.builder(scrollDirection:Axis.horizontal,
          itemCount:keys.length,onReorder:_busy ? (_,__) {} : (from,to) => setState(() {
            if(to>from)to--;final order=List<String>.of(keys);final key=order.removeAt(from);order.insert(to,key);_photoOrder=order;
          }),itemBuilder:(_,index) {
            final key=keys[index];String? path;
            for(final entry in _localPhotoKeys.entries) { if(entry.value==key && _imagePaths.contains(entry.key)) path=entry.key; }
            return Container(key:ValueKey(key),width:120,margin:const EdgeInsetsDirectional.only(end:8),child:Stack(fit:StackFit.expand,children:[
              ClipRRect(borderRadius:BorderRadius.circular(8),child:path!=null ? Image.file(File(path),fit:BoxFit.cover,
                errorBuilder:(_,__,___)=>_remotePhotos[key]!=null ? ListingDraftPhoto(url:_remotePhotos[key]!) : const Icon(Icons.broken_image_outlined))
                : ListingDraftPhoto(url:_remotePhotos[key]!)),
              PositionedDirectional(top:2,end:2,child:IconButton.filled(tooltip:'إزالة الصورة',onPressed:_busy?null:()=>_removeDraftPhoto(key),icon:const Icon(Icons.close,size:18))),
              if(index==0 && (_replaceImages || existingImages==0)) const PositionedDirectional(start:4,bottom:4,child:AppStatusBadge(label:'الرئيسية',tone:AppStatusTone.info)),
            ]));
          })),const SizedBox(height:6),const Text('اسحب الصور لتغيير ترتيبها. تُحفظ الصور المرفوعة على حسابك.'),
      ],
    ]));
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
            Expanded(
              child: EbrokerStepButton(
                label: 'السابق',
                style: AppButtonStyle.outlined,
                onPressed: _busy ? null : () {
                  if (_step > 0) { setState(() => _step--); } else { Navigator.of(context).maybePop(); }
                },
                expand: true,
              ),
            ),
          const SizedBox(width: AppSpacing.s8),
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
    if (_step == 0 && !_completionOnly) { _typeConfirmed = true; _purposeConfirmed = true; }
    final message = _validationMessageForStep(_step);
    if (message != null) {
      _message(message);
      return;
    }
    setState(() => _step++);
  }

  String? _validationMessageForStep(int step, {bool requireImages = true}) {
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
      if (!_isRentalApartment && (areaValue == null || areaValue <= 0)) return 'أدخل مساحة صحيحة أكبر من صفر.';
      final images = _effectiveImageCount;
      if (requireImages && images == 0) return 'أضف صورًا حقيقية للعقار قبل المتابعة.';
      if (_purpose == 'rent') {
        int? advance, duration;
        for (final condition in _rentalConditions) {
          if (const ['advance', 'duration'].contains(condition['kind']) && (condition['months'] is! int || (condition['months'] as int) < 1 || (condition['months'] as int) > 24)) return 'أكمل عدد الأشهر للشرط المحدد (من 1 إلى 24).';
          if (condition['kind'] == 'special' && (condition['text']?.toString().trim().isEmpty ?? true)) return 'اكتب الشرط الخاص أو احذفه.';
          if (condition['kind'] == 'advance') advance = condition['months'] as int;
          if (condition['kind'] == 'duration') duration = condition['months'] as int;
        }
        if (advance != null && duration != null && advance > duration) return 'أشهر المقدم لا يمكن أن تتجاوز مدة العقد المحددة.';
      }
      if (_isUnitType) {
        if (!_wholeFloor && !_isRentalApartment && _unitNumber.text.trim().isEmpty) {
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
        if (monthly == null || monthly <= 0) {
          return 'أدخل الإيجار الشهري بشكل صحيح.';
        }
      }
    }
    return null;
  }

  String? _validateCore() {
    if (!_typeConfirmed || !_purposeConfirmed) return 'أكد نوع العقار والغرض قبل المتابعة.';
    for (var step = 0; step <= 3; step++) {
      final message = _validationMessageForStep(step, requireImages: false);
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

    final effectiveImageCount = _effectiveImageCount;
    if (effectiveImageCount < 1) {
      return 'أضف صورة واحدة على الأقل قبل إرسال الإعلان للمراجعة.';
    }
    return _ownershipValidation();
  }

  String? _ownershipValidation() {
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

  List<(int, String)> _completionGaps() {
    final gaps = <(int, String)>[];
    for (var step = 0; step < 4; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) gaps.add((step, message));
    }
    final images = _effectiveImageCount;
    if (images == 0 && !gaps.any((gap) => gap.$2.contains('صور'))) {
      gaps.add((2, 'أضف صورًا حقيقية للعقار قبل المتابعة.'));
    }
    if (_validationMessageForStep(3) == null && !_isSaiReady && _inlineSaiValidation != null) {
      gaps.add((3, _inlineSaiValidation!));
    }
    final ownership = _ownershipValidation();
    if (ownership != null) gaps.add((1, ownership));
    gaps.sort((a, b) => a.$1.compareTo(b.$1));
    return gaps;
  }

  void _goToCompletionStep(int target) {
    for (var step = 0; step < target; step++) {
      final message = _validationMessageForStep(step);
      if (message != null) {
        setState(() => _step = step);
        _message(message);
        return;
      }
    }
    setState(() => _step = target);
  }

  Future<void> _reviewCompletion() async {
    FocusScope.of(context).unfocus();
    final gaps = _completionGaps();
    final target = await AppBottomSheet.show<int>(context, builder: (sheet) => Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(height: MediaQuery.sizeOf(sheet).height * .68,
        child: ListView(padding: const EdgeInsets.all(18), children: [
          Text('أكمل إعلانك بسرعة', style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('انتقل لما يحتاج إكمالًا. يبقى اعتماد الإعلان بعد إرساله لمراجعة المنصة.'),
          const SizedBox(height: 16),
          if (gaps.isEmpty) const AppInlineMessage(message: 'متطلبات النموذج مكتملة. راجع النص والصور قبل الإرسال.', tone: AppStatusTone.info),
          for (var i = 0; i < gaps.length; i++) ListTile(
            key: ValueKey('listing-gap-$i'),
            contentPadding: EdgeInsets.zero,
            leading: const EbrokerIcon(Icons.radio_button_unchecked, size: 20),
            title: Text(gaps[i].$2),
            subtitle: Text(const ['نوع الإعلان والعنوان', 'الموقع والمستندات', 'المواصفات والصور', 'السعر والسعي'][gaps[i].$1]),
            trailing: const EbrokerIcon(Icons.chevron_left, size: 20),
            onTap: () => Navigator.of(sheet).pop(gaps[i].$1)),
          const Divider(),
          ListTile(contentPadding: EdgeInsets.zero, leading: const EbrokerIcon(Icons.edit_note_outlined),
            title: const Text('مراجعة الوصف والصور'),
            onTap: () => Navigator.of(sheet).pop(2)),
        ]))));
    if (mounted && target != null) _goToCompletionStep(target);
  }

  Future<void> _copyListingText() async {
    final text = [
      _title.text.trim(),
      '${_typeLabels[_type] ?? _type} ${_purpose == 'rent' ? 'للإيجار' : 'للبيع'}',
      _priceSummaryText,
      if (_isSaiReady) _saiDisplayText,
      _composedAddress,
      if (_description.text.trim().isNotEmpty) _description.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'للتواصل: ${_phone.text.trim()}',
      if (_whatsapp.text.trim().isNotEmpty) 'واتساب: ${_whatsapp.text.trim()}',
    ].where((line) => line.isNotEmpty).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _message('نُسخ نص الإعلان. يمكنك لصقه ومراجعته قبل مشاركته.');
  }

  Map<String, dynamic> _aiFacts() => {
    if (_typeConfirmed) 'type': _type, if (_purposeConfirmed) 'purpose': _purpose, 'currency': 'YER',
    if (_requiresSaleTenure && _tenureType != null) 'tenure_type': _tenureType,
    if (_applies('unit_number') && _unitNumber.text.trim().isNotEmpty) 'unit_number': _unitNumber.text.trim(),
    if (_saiTouched) ...{'sai_amount_type': _saiAmountType, if (_fixedSai && _enteredSaiAmount.isFinite) 'fixed_sai_amount': _enteredSaiAmount, if (!_fixedSai && _enteredSaiRate.isFinite) 'broker_sai_rate_percent': _enteredSaiRate},
    if (_purpose == 'rent' && _rentalConditions.isNotEmpty) 'rental_conditions': _rentalConditions,
    if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
    if (_composedAddress.trim().isNotEmpty) 'address': _composedAddress,
    if (_governorate.text.trim().isNotEmpty) 'governorate': _governorate.text.trim(),
    if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
    if (_street.text.trim().isNotEmpty) 'street': _street.text.trim(),
    if (_purpose == 'sale' && (double.tryParse(_price.text) ?? 0) > 0) 'price': double.parse(_price.text),
    if (_purpose == 'rent' && (double.tryParse(_monthlyRent.text) ?? 0) > 0) 'monthly_rent': double.parse(_monthlyRent.text),
    if (!_isRentalApartment && (double.tryParse(_area.text) ?? 0) > 0) 'area_value': double.parse(_area.text),
    if (!_isRentalApartment) 'area_unit': _areaUnit,
    if (_requiresResidential && (_optionalInt(_bedrooms) ?? 0) > 0) 'bedrooms': _optionalInt(_bedrooms),
    if (_requiresResidential && (_optionalInt(_bathrooms) ?? 0) > 0) 'bathrooms': _optionalInt(_bathrooms),
    if (_requiresStructure && _parkingChoice != null) 'has_parking': _parkingValue,
    if (_supportsElevator && _elevatorChoice != null) 'has_elevator': _elevatorChoice == 'yes',
    if (_supportsFacade && _facade != null) 'building_facade': _facade,
    if (_unitNeedsFloor && _floorNumber.text.trim().isNotEmpty) 'floor_number': _floorNumber.text.trim(),
    if (_type == 'apartment') 'unit_occupies_entire_floor': _wholeFloor,
  };

  Future<void> _assist({bool prepareDraft = false}) async {
    final result = await AppBottomSheet.show<Map<String, dynamic>>(context, builder: (_) => ListingAiSheet(
      facts: _aiFacts(), propertyId: _existing?.id ?? _recoveredServerId, draftKey: _draftRevision > 0 ? _draftKey : null,
      prepareDraft: prepareDraft, initialMessage: _assistantBrief.text,
      hasExistingDescription: _description.text.trim().isNotEmpty,
      onMessageChanged: (text) => _assistantBrief.text = text));
    if (!mounted || result == null) return;
    final oldPurpose = _purpose;
    final addressChanged = const ['governorate','district','street'].any((k) => result[k] != null && result[k] != _aiFacts()[k]);
    setState(() {
      if (result['description'] is String) _description.text = result['description'] as String;
      if (_typeLabels.containsKey(result['type'])) { _type = result['type'] as String; _typeConfirmed = true; }
      if (const ['sale', 'rent'].contains(result['purpose'])) { _purpose = result['purpose'] as String; _purposeConfirmed = true; }
      for (final entry in <String, TextEditingController>{
        'title': _title, if (!_isRentalApartment) 'area_value': _area, 'governorate': _governorate, 'district': _district, 'street': _street,
        if (_purpose == 'sale') 'price': _price,
        if (_purpose == 'rent') 'monthly_rent': _monthlyRent,
        if (_requiresResidential) 'bedrooms': _bedrooms,
        if (_requiresResidential) 'bathrooms': _bathrooms,
        if (_isUnitType) 'floor_number': _floorNumber,
        if (_isUnitType) 'unit_number': _unitNumber,
      }.entries) { if (result[entry.key] != null) entry.value.text = result[entry.key].toString(); }
      if (propertyAreaUnitLabels.containsKey(result['area_unit'])) _areaUnit = result['area_unit'] as String;
      if (_requiresSaleTenure && const ['freehold', 'waqf'].contains(result['tenure_type'])) _tenureType = result['tenure_type'] as String;
      if (_requiresStructure && result['has_parking'] is bool) _parkingChoice = result['has_parking'] == true ? 'yes' : 'no';
      if (_supportsFacade && propertyFacadeLabels.containsKey(result['building_facade'])) _facade = result['building_facade'] as String;
      if (_supportsElevator && result['has_elevator'] is bool) _elevatorChoice = result['has_elevator'] == true ? 'yes' : 'no';
      if (_type != 'apartment') _wholeFloor = false;
      if (_wholeFloor) _unitNumber.clear();
      if (!_requiresResidential) { _bedrooms.clear(); _bathrooms.clear(); }
      if (!_requiresStructure) { _parkingChoice = null; if (!_supportsFacade) _facade = null; }
      if (!_supportsElevator) _elevatorChoice = null;
      if (!_requiresSaleTenure) _tenureType = null;
      if (!_isUnitType) { _floorNumber.clear(); _unitNumber.clear(); _buildingReference.clear(); }
      if (addressChanged) { _latitude = null; _longitude = null; _landBoundaryGeoJson = null; }
      if (_type != 'land') _landBoundaryGeoJson = null;
      if (oldPurpose != _purpose) { _saiAccepted = false; _saiTouched = true; }
      if (const ['percentage','fixed'].contains(result['sai_amount_type'])) _saiAmountType = result['sai_amount_type'] as String;
      if (result['broker_sai_rate_percent'] is num) { _saiRate.text = result['broker_sai_rate_percent'].toString(); _saiTouched = true; }
      if (result['fixed_sai_amount'] is num) { _saiAmount.text = result['fixed_sai_amount'].toString(); _saiTouched = true; }
      if (_purpose == 'rent' && result['rental_conditions'] is List) _rentalConditions = (result['rental_conditions'] as List).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
      _clearHiddenFields();
    });
    if (oldPurpose != _purpose) await _loadSaiPolicy();
    if (!mounted) return;
    if (prepareDraft) {
      _completionOnly = true; _completionFields = _missingFields();
      final gaps = _completionGaps();
      if (gaps.isNotEmpty) setState(() => _step = gaps.first.$1);
    }
    unawaited(_saveRecovery());
    _message('طُبّق الاقتراح في الحقول. راجع بقية الإعلان قبل إرساله.');
  }

  Future<void> _polishRentalConditions() async {
    if (_busy || _rentalConditions.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(aiRepositoryProvider).rentalConditions(_rentalConditions, propertyId: _existing?.id ?? _recoveredServerId);
      if (!mounted) return;
      final rows = result['rental_conditions'];
      if (rows is! List || result['text'] is! String) throw StateError('Invalid requirements proposal');
      final use = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('راجع صياغة الشروط'), content: SingleChildScrollView(child: Text(result['text'] as String)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('استخدام الترتيب المقترح'))]));
      if (mounted && use == true) setState(() => _rentalConditions = rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (error) { if (mounted) _message(friendlyApiError(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  PropertyListingInput _input() {
    final user = ref.read(authControllerProvider).asData?.value;
    return PropertyListingInput(
      inputVersion: 8,
      rentalConditions: _purpose == 'rent' ? _rentalConditions : const [],
      title: _title.text.trim(),
      description: _description.text.trim(),
      purpose: _purpose,
      type: _type,
      tenureType: _requiresSaleTenure ? _tenureType : null,
      price: _effectivePrice!,
      priceDisplayMode: 'excludes_sai',
      monthlyRent:
          _purpose == 'rent' ? double.parse(_monthlyRent.text.trim()) : null,
      rentalTermMonths:
          null,
      advanceMonths:
          null,
      areaValue: _isRentalApartment ? null : double.tryParse(_area.text.trim()),
      areaUnit: _isRentalApartment ? null : _area.text.trim().isEmpty ? null : _areaUnit,
      bedrooms: _requiresResidential ? _optionalInt(_bedrooms) : null,
      bathrooms: _requiresResidential ? _optionalInt(_bathrooms) : null,
      hasParking: _requiresStructure ? _parkingValue : null,
      hasElevator: _isRentalApartment ? null : _supportsElevator && _elevatorChoice != null ? _elevatorChoice == 'yes' : null,
      buildingFacade: _supportsFacade ? _facade : null,
      address: _composedAddress,
      buildingReference: _isUnitType ? _buildingReference.text.trim() : null,
      unitNumber: _isUnitType && !_wholeFloor ? _unitNumber.text.trim() : null,
      unitOccupiesEntireFloor: _type == 'apartment' && _wholeFloor,
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
      if (!submit) { await _saveRecovery(); if (mounted) _message(_accountSaved ? 'حُفظت المسودة على حسابك. يمكنك إكمالها لاحقًا.' : 'لم يكتمل الحفظ على الحساب. أعد المحاولة قبل الخروج.'); } else { _message(validation); }
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
    _recoveryTimer?.cancel();
    late PropertyDetails draft;
    try {
      await _saveRecovery();
      if (!_accountSaved || _accountConflict) throw StateError('تعذر حفظ المسودة على الحساب.');
      if (!await _resolveRecoveredDraft()) return;
      final repository = ref.read(propertyRepositoryProvider);
      draft = _isEditing
          ? await repository.updateListing(
              _existing!.id,
              _input(),
              imagePaths: const [],
              editorDraftKey: _draftKey, editorDraftRevision: _draftRevision,
              replaceImages: _replaceImages,
              submitForReview: false,
              ownershipProofPath: _ownershipProofPath,
            )
          : await repository.createListing(
              _input(),
              imagePaths: const [],
              editorDraftKey: _draftKey, editorDraftRevision: _draftRevision,
              submitForReview: false,
              ownershipProofPath: _ownershipProofPath,
            );

      if (mounted) setState(() => _workingDraft = draft);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      _adoptAccountDraft(await _accountRepository.get(_draftKey));
      await _clearUploadedTemporaryFiles();
      _photoOrder.clear(); _removedPhotoKeys.clear(); _remotePhotos.clear(); _localPhotoKeys.clear();
      _accountSaved = false;
      await _saveRecovery();

      // These writes follow the explicit Save/Submit action. Neither editing
      // the percentage nor displaying a preview mutates a server listing.
      final policy = _saiPolicy;
      if (policy != null && (policy.isOwner || ((_existingSaiLoaded || _saiTouched || _hasRecoveredSai || !_startedAsEditing) && _isSaiReady))) {
        try {
          await repository.configureSai(draft.id,
            payer: _purpose == 'rent' ? 'tenant' : 'buyer',
            brokerRatePercent: policy.isOwner || _fixedSai ? null : _enteredSaiRate,
            amountType: _fixedSai ? 'fixed' : 'percentage',
            fixedAmount: _fixedSai ? _enteredSaiAmount : null,
            deferPlatformTerms: !policy.isOwner && _activeSaiValue > 0);
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
                if (!_isRentalApartment && _area.text.trim().isNotEmpty) _SummaryRow(
                    label: 'المساحة',
                    value: '${_area.text.trim()} ${propertyAreaUnitLabel(_areaUnit)}'),
                _SummaryRow(label: 'السعي', value: _saiDisplayText),
                _SummaryRow(label: 'الموقع', value: _composedAddress),
                if (_description.text.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(_description.text.trim()),
                ],
                if (_purpose == 'rent' && _rentalConditions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text('شروط الإيجار', style: Theme.of(context).textTheme.titleMedium),
                  for (final condition in _rentalConditions) Text(switch (condition['kind']) {
                    'advance' => 'مقدم إيجار: ${condition['months']} أشهر',
                    'duration' => 'مدة العقد: ${condition['months']} أشهر',
                    'guarantor' => 'ضمانة تجارية مطلوبة',
                    'deposit' => 'تأمين مطلوب',
                    _ => '${condition['text'] ?? ''}',
                  }),
                ],
                const SizedBox(height: AppSpacing.s20),
                AppButton(
                  label: 'إغلاق المعاينة',
                  style: AppButtonStyle.outlined,
                  onPressed: () => Navigator.pop(sheetContext),
                  expand: true,
                ),
                const SizedBox(height: AppSpacing.s8),
                TextButton.icon(key: const ValueKey('listing-copy-text'), onPressed: _copyListingText,
                  icon: const EbrokerIcon(Icons.copy_outlined, size: 18), label: const Text('نسخ نص الإعلان')),
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
      if (mounted) { setState(() {
        _existingSaiLoaded = true;
        final management = envelope.management;
        if (management != null && management.purpose == _purpose && !_saiTouched && !_hasRecoveredSai) {
          _saiAmountType = management.amountType;
          _saiAmount.text = management.fixedAmount?.toString() ?? '';
          _saiRate.text = management.requestedBrokerRatePercent?.toString() ?? '';
          _saiAccepted = management.platformTermsStatus == 'accepted';
        }
      }); }
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
    if ((_isRentalApartment || _type == 'shop') && !_wholeFloor && _unitNumber.text.trim().isEmpty && result.signals.contains('unit_identity_incomplete')) {
      return true; // The server routes an unspecified unit to support identity review.
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
      final available = (12 - existingCount - _photoKeys.length).clamp(0, 12);
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

  Future<void> _removeDraftPhoto(String key) async {
    final paths = _localPhotoKeys.entries.where((e)=>e.value==key).map((e)=>e.key).toList();
    setState(() { _removedPhotoKeys.add(key); _photoOrder.remove(key); _imagePaths.removeWhere(paths.contains); });
    await _saveRecovery();
    try { await _mediaPicker.clearTemporaryFiles(paths); } catch (_) {}
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
        Expanded(child: EbrokerStepButton(label: 'السابق', style: AppButtonStyle.outlined,
          onPressed: busy ? null : onPrevious, expand: true)),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: EbrokerStepButton(label: 'إرسال للمراجعة', icon: Icons.send_outlined,
          loading: busy, onPressed: busy ? null : onSubmit, expand: true)),
        const SizedBox(width: 8),
        PopupMenuButton<String>(tooltip: 'خيارات المسودة', enabled: !busy,
          icon: const EbrokerIcon(Icons.more_horiz, size: 22),
          onSelected: (value) { switch (value) {
            case 'save': onSaveDraft(); break;
            case 'preview': onPreview(); break;
          } },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'save', child: Semantics(label: 'حفظ مسودة', excludeSemantics: true, child: Text('حفظ مسودة'))),
            PopupMenuItem(value: 'preview', child: Semantics(label: 'معاينة', excludeSemantics: true, child: Text('معاينة'))),
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
