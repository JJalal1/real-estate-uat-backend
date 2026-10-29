import '../domain/listing_contact_policy.dart';
import '../domain/rental_condition_summary.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../data/listing_account_draft_repository.dart';
import '../domain/listing_account_draft.dart';
import '../domain/property_schema.dart';
import 'listing_draft_photo.dart';
import 'adaptive_property_photo.dart';

import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/local/listing_recovery_store.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/platform/voice_capture_controller.dart';
import '../../../core/platform/voice_input.dart';
import '../../../core/platform/app_permission_settings.dart';
import '../../../core/widgets/inline_voice_capture.dart';
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
import 'property_location_preview.dart';
import '../domain/property_coordinates.dart';
import '../../../core/local/stage6_secure_session_store.dart';
import 'listing_sai_section.dart';
import 'listing_ai_sheet.dart';
import 'rental_conditions_editor.dart';
import '../../discovery/data/ai_repository.dart';

class ListingEditorScreen extends ConsumerStatefulWidget {
  const ListingEditorScreen({super.key, this.existingProperty, this.accountDraft, this.localRecovery, this.startFresh = false, this.startWithAssistant = false});

  final ListingAccountDraft? accountDraft;
  final Map<String, dynamic>? localRecovery;
  final bool startFresh;
  final bool startWithAssistant;

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
  final _floorsCount = TextEditingController();
  final _shopOpenings = TextEditingController();
  List<String> _unitsPerFloor = [];
  bool _sameFloorUnits = false;
  int _unitsGeneration = 0;
  final _bedrooms = TextEditingController();
  final _bathrooms = TextEditingController();
  final _governorate = TextEditingController();
  final _district = TextEditingController();
  final _street = TextEditingController();
  final _buildingReference = TextEditingController();
  final _unitNumber = TextEditingController();
  final _floorNumber = TextEditingController();
  ListingContactPolicy _contactPolicy = const ListingContactPolicy();
  bool _validateContacts = false;
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _documentOwnerName = TextEditingController();
  final _relationshipNote = TextEditingController();
  final _editorScroll = ScrollController();

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
  bool get _hasLocation => hasValidPropertyCoordinates(_latitude, _longitude);
  Map<String, dynamic>? _landBoundaryGeoJson;
  bool _busy = false;
  bool _resolvingLocation = false;
  bool _replaceImages = false;
  List<String> _imagePaths = <String>[];
  String? _ownershipProofPath;
  PropertyDetails? _workingDraft;
  final _saiRate = TextEditingController();
  final _saiAmount = TextEditingController();
  String _saiAmountType = 'fixed';
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
  bool _draftSavedExplicitly = false;
  bool _accountSaved = false, _accountSyncing = false, _accountConflict = false;
  String? _accountError, _descriptionError;
  String? _stepError, _locationError;
  bool _selectingLocation = false, _showLocationPreview = false;
  bool _locationNeedsSettings = false, _locationServiceDisabled = false;
  late final VoiceCaptureController _descriptionCapture;
  String _descriptionVoiceBase = '';
  String? _lastDescriptionVoiceBase, _lastDescriptionVoiceText;
  int _descriptionVoiceTurn = 0;
  bool _descriptionBusy = false, _typeConfirmed = false, _purposeConfirmed = false, _completionOnly = false, _reviewingCompleted = false;
  Timer? _descriptionRetryTimer;
  bool get _descriptionCoolingDown => ref.read(aiRepositoryProvider).descriptionRetryAt?.isAfter(DateTime.now()) == true;
  Set<String> _completionFields = {};
  final _remotePhotos = <String, String>{}, _localPhotoKeys = <String, String>{};
  final _removedPhotoKeys = <String>{};
  List<String> _photoOrder = [];
  (Map<String, dynamic>, Map<String, String>)? _pendingAccount;
  Future<void> _accountTail = Future<void>.value();
  final _photoStates = <String,String>{}, _photoErrors = <String,String>{};
  final _photoProgress = <String,double>{};
  final _photoCancels = <String,CancelToken>{};
  final _retryPhotoKeys = <String>{};
  bool _needsReconcile = false;
  String? _checkpointKey, _checkpointSignature, _confirmedEditSignature, _initialEditSignature;
  bool _allowExit = false, _exitDialogOpen = false, _disposed = false, _sessionValid = true, _persistStarting = false;

  String get _editSignature {
    final data = _serverSnapshot(_recoverySnapshot())..remove('step')..remove('server_property_id');
    if (!_saiTouched) {
      final fields=Map<String,dynamic>.from(data['fields'] as Map);
      fields.remove('broker_sai_rate_percent');fields.remove('fixed_sai_amount');data['fields']=fields;
    }
    return jsonEncode([data,_ownershipProofPath]);
  }
  bool get _hasUnsavedChanges => _recoveryReady && _sessionValid &&
    (_recoveryFailed || _editSignature != (_confirmedEditSignature ?? _initialEditSignature));

  List<String> get _photoKeys {
    final active = <String>{if (!_replaceImages) ...?_existing?.images.map((i)=>'property-${i.id}').where((k)=>!_removedPhotoKeys.contains(k)),
      ..._remotePhotos.keys.where((k) => !_removedPhotoKeys.contains(k)),
      for (final path in _imagePaths) _localPhotoKeys.putIfAbsent(path, newListingDraftKey),
      ..._photoOrder.where((key)=>!_removedPhotoKeys.contains(key) && !(_replaceImages && key.startsWith('property-')))};
    return [..._photoOrder.where(active.remove), ...active];
  }
  int get _effectiveImageCount => _photoKeys.length;

  void _adoptAccountDraft(ListingAccountDraft draft) {
    _draftRevision = draft.revision;
    if (!draft.isRecovery) _draftSavedExplicitly = true;
    _remotePhotos..clear()..addAll(draft.images);
    for (final key in draft.images.keys) { if (!_removedPhotoKeys.contains(key)) { _photoStates[key]='complete';_photoErrors.remove(key); } }
    _recoveredServerId = draft.propertyId ?? _recoveredServerId;
    final promoted=draft.payload['promoted_image_keys'];
    if (draft.propertyId!=null && promoted is Map && promoted.isNotEmpty) {
      final aliases=Map<String,String>.from(promoted);
      _photoOrder=_photoKeys.map((key)=>aliases[key] ?? key).toList();
      final removed=_removedPhotoKeys.map((key)=>aliases[key] ?? key).toSet();
      _removedPhotoKeys..clear()..addAll(removed);
      _imagePaths.removeWhere((path)=>aliases.containsKey(_localPhotoKeys[path]));
      _localPhotoKeys.removeWhere((path,key)=>aliases.containsKey(key));
      for (final key in aliases.keys) { _photoStates.remove(key);_photoErrors.remove(key); }
    }
  }

  Map<String, dynamic> _serverSnapshot(Map<String, dynamic> snapshot) {
    final data = Map<String, dynamic>.from(jsonDecode(jsonEncode(snapshot)) as Map);
    data.remove('draft_key'); data.remove('server_revision'); data.remove('image_tokens');
    for (final key in ['remote_images','removed_image_keys','photo_states','ownership_proof_path','account_checkpoint_key','account_checkpoint_signature','promoted_image_keys']) { data.remove(key); }
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
    if (_accountConflict || !_sessionValid || _disposed) return _accountTail;
    _pendingAccount = (_serverSnapshot(snapshot), Map.of(photos));
    _accountSaved = false;
    if (_accountSyncing) return _accountTail;
    _accountSyncing = true;
    _accountTail = () async {
      try {
        while (_pendingAccount != null) {
          var pending = _pendingAccount!; _pendingAccount = null;
          if (_needsReconcile) {
            try {
              final latest=await _accountRepository.get(_draftKey).timeout(const Duration(seconds:30));
              if (_disposed || !_sessionValid || _recoveryFinished) return;
              if (latest.payload['checkpoint_key'] != _checkpointKey) {
                throw DioException(requestOptions:RequestOptions(),response:Response(requestOptions:RequestOptions(),statusCode:409),type:DioExceptionType.badResponse);
              }
              _adoptAccountDraft(latest);
              if (latest.payload['promoted_image_keys'] is Map && (latest.payload['promoted_image_keys'] as Map).isNotEmpty) {
                if (!await _resolveRecoveredDraft()) throw StateError('تعذر استعادة الإعلان المحفوظ. أعد المحاولة.');
                if (_disposed || !_sessionValid || _recoveryFinished) return;
                pending=(_serverSnapshot(_recoverySnapshot()),{for (final path in List<String>.of(_imagePaths)) _localPhotoKeys[path]!:path});
              }
            } on DioException catch (error) { if (error.response?.statusCode != 404 || _draftRevision != 0) rethrow; }
            _needsReconcile=false;
          }
          final signature=jsonEncode(pending.$1);
          if (_checkpointSignature != signature) { _checkpointSignature=signature;_checkpointKey=newListingDraftKey(); }
          final payload={...pending.$1,'checkpoint_key':_checkpointKey};
          var draft = await _accountRepository.save(_draftKey, payload, _draftRevision,
            propertyId: _existing?.id ?? _recoveredServerId).timeout(const Duration(seconds:90));
          if (_disposed || !_sessionValid || _recoveryFinished) return;
          _adoptAccountDraft(draft);
          final order = (pending.$1['image_order'] as List? ?? const []).whereType<String>().toSet();
          for (final key in _remotePhotos.keys.toList()) {
            if (order.contains(key)) continue;
            draft = await _draftOperation(() => _accountRepository.removeImage(_draftKey, key, _draftRevision));
            if (_disposed || !_sessionValid || _recoveryFinished) return;
            _adoptAccountDraft(draft);
          }
          for (final photo in pending.$2.entries) {
            if (_remotePhotos.containsKey(photo.key) || !order.contains(photo.key) || _removedPhotoKeys.contains(photo.key)) continue;
            if (_photoStates[photo.key]=='failed' && !_retryPhotoKeys.remove(photo.key)) continue;
            var connectionLost=false;
            final token=CancelToken();_photoCancels[photo.key]=token;_photoStates[photo.key]='uploading';_photoErrors.remove(photo.key);
            if (mounted) super.setState(() {});
            try {
              draft = await _draftOperation(() => _accountRepository.upload(_draftKey, photo.key, photo.value, _draftRevision,
                cancelToken:token,onSendProgress:(sent,total) {
                  if (_disposed || !_sessionValid || _removedPhotoKeys.contains(photo.key)) return;
                  _photoProgress[photo.key]=total>0 ? sent/total : 0;
                  _photoStates[photo.key]=total>0 && sent>=total ? 'processing' : 'uploading';
                  if (mounted) super.setState(() {});
                }));
              if (_disposed || !_sessionValid || _recoveryFinished) return;
              _adoptAccountDraft(draft);
            } catch (error) {
              if (_disposed || !_sessionValid || _recoveryFinished) return;
              if (!_removedPhotoKeys.contains(photo.key)) {
                _photoStates[photo.key]='failed';_photoErrors[photo.key]=friendlyApiError(error);
              }
              _needsReconcile=true;
              connectionLost=error is TimeoutException || error is DioException && const [DioExceptionType.connectionError,DioExceptionType.connectionTimeout,DioExceptionType.sendTimeout,DioExceptionType.receiveTimeout].contains(error.type);
              if (error is DioException && error.response?.data is Map && error.response?.data['code']=='draft_revision_conflict') rethrow;
            } finally { _photoCancels.remove(photo.key); }
            await _writeLocalRecovery();
            if (mounted) super.setState(() {});
            // A lost connection pauses untouched files; a file-specific failure still allows the rest.
            if (connectionLost) break;
          }
          // Persist the acknowledged revision and remote image keys even when one later file fails.
          await _writeLocalRecovery();
        }
        final ready=_photoKeys.every((key)=>key.startsWith('property-') || _remotePhotos.containsKey(key));
        _accountSaved = ready && _checkpointSignature==jsonEncode(_serverSnapshot(_recoverySnapshot()));
        _accountError = ready ? null : 'لم يكتمل رفع بعض الصور. أعد محاولة الملف المتعثر.';
        if (_accountSaved) _confirmedEditSignature=_editSignature;
      } catch (e) {
        _needsReconcile=true;
        _accountSaved = false; _accountError = friendlyApiError(e);
        _accountConflict = e is DioException && e.response?.statusCode == 409;
      } finally {
        _accountSyncing = false;
        if (mounted && !_disposed) super.setState(() {});
      }
    }();
    return _accountTail;
  }

  Future<ListingAccountDraft> _draftOperation(Future<ListingAccountDraft> Function() operation) async {
    try { return await operation().timeout(const Duration(minutes:2)); }
    on DioException catch (error) {
      if (error.response?.statusCode != 409 || error.response?.data is! Map || error.response?.data['code'] != 'draft_revision_conflict') rethrow;
      final latest=await _accountRepository.get(_draftKey).timeout(const Duration(seconds:30));
      if (_disposed || !_sessionValid || latest.payload['checkpoint_key'] != _checkpointKey) rethrow;
      _adoptAccountDraft(latest);
      return operation().timeout(const Duration(minutes:2));
    }
  }

  void _clearHiddenFields() {
    if (!_applies('floors_count')) { _floorsCount.clear(); _unitsPerFloor = []; _sameFloorUnits = false; }
    if (!_applies('shop_openings')) _shopOpenings.clear();
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
    final value = _floorNumber.text.trim(), options = DynamicPropertySchema.floorOptionsFor(_type);
    final selected = value.isNotEmpty && (options.containsKey(value) || _type != 'apartment') ? value : null;
    return AppSelectField<String>(key: const ValueKey('listing-floor-select'), value: selected,
      isExpanded: true, decoration: InputDecoration(labelText: _type == 'apartment' ? 'الشقة في الدور *' : 'الدور *',
        errorText: _type == 'apartment' && value.isNotEmpty && !options.containsKey(value) ? 'اختر دورًا من الأرضي إلى السابع.' : null),
      items: [for (final entry in options.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        if (_type != 'apartment' && value.isNotEmpty && !options.containsKey(value)) DropdownMenuItem(value: value, child: Text(value))],
      onChanged: _busy ? null : (value) => setState(() => _floorNumber.text = value ?? ''));
  }

  Future<void> _generateDescription() async {
    if (_descriptionBusy || _busy || _descriptionCapture.active || _descriptionCoolingDown) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final facts = _aiFacts(), before = _description.text, signature = jsonEncode(_aiFacts());
    setState(() { _descriptionBusy = true; _descriptionError = null; });
    try {
      final result = await ref.read(aiRepositoryProvider).description(facts,
        sourceDescription: before,
        propertyId: _existing?.id ?? _recoveredServerId, draftKey: _draftRevision > 0 ? _draftKey : null);
      if (!mounted || ref.read(authControllerProvider).asData?.value?.id != actor) return;
      if (_description.text != before || jsonEncode(_aiFacts()) != signature) {
        setState(() => _descriptionError = 'تغيرت بيانات الإعلان أو الوصف أثناء التجهيز. أعد الطلب عند الحاجة.'); return;
      }
      final text = result['description'];
      if (text is! String || text.trim().isEmpty || text.length > 5000) throw StateError('تعذر تجهيز الوصف.');
      setState(() => _description.text = text);
    } catch (e) {
      if (!mounted) return;
      if (e is DescriptionRateLimit) {
        _descriptionRetryTimer?.cancel();
        _descriptionRetryTimer = Timer(e.retryAt.difference(DateTime.now()), () { if (mounted) setState(() {}); });
      }
      setState(() => _descriptionError = e is DioException && const [401,403,422].contains(e.response?.statusCode)
        ? friendlyApiError(e) : 'تعذر إنشاء الوصف الآن، جرّب بعد لحظات');
    }
    finally { if (mounted) setState(() => _descriptionBusy = false); }
  }

  void _descriptionVoiceChanged() {
    if (!mounted) return;
    if (_descriptionCapture.active && _descriptionCapture.preview.isNotEmpty) {
      final text = appendDictation(_descriptionVoiceBase, _descriptionCapture.preview);
      _description.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    super.setState(() {});
  }
  void _cancelDescriptionVoice() {
    if (!_descriptionCapture.active && !_descriptionCapture.canRetry) return;
    ++_descriptionVoiceTurn; _descriptionCapture.cancel(); _description.text = _descriptionVoiceBase;
  }
  void _restartDescriptionVoice() {
    if (_descriptionCapture.active) { _cancelDescriptionVoice(); }
    else if (_lastDescriptionVoiceBase != null && _description.text == _lastDescriptionVoiceText) { _description.text = _lastDescriptionVoiceBase!; }
    unawaited(_dictateDescription());
  }
  Future<void> _dictateDescription({bool retry = false, bool wholeRecording = false}) async {
    if (_busy || _descriptionBusy || _descriptionCapture.active) return;
    FocusScope.of(context).unfocus();
    _descriptionVoiceBase = _description.text;
    final actor = ref.read(authControllerProvider).asData?.value?.id, turn = ++_descriptionVoiceTurn;
    final text = retry ? await _descriptionCapture.retryTranscription() : await _descriptionCapture.start(wholeRecording: wholeRecording);
    if (!mounted || turn != _descriptionVoiceTurn || actor != ref.read(authControllerProvider).asData?.value?.id) return;
    final complete = text ?? (_descriptionCapture.error != null ? _descriptionCapture.stablePreview : '');
    _description.text = appendDictation(_descriptionVoiceBase, complete);
    if (complete.isNotEmpty) { _lastDescriptionVoiceBase = _descriptionVoiceBase; _lastDescriptionVoiceText = _description.text; }
    if (_description.text.length > 5000) setState(() => _descriptionError = 'الوصف محفوظ هنا. اختصره إلى 5000 حرف قبل الحفظ.');
    _scheduleRecovery();
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
    if (_title.text.trim().length < 4) result.add('title');
    if (_governorate.text.trim().length < 2) result.add('governorate');
    if (_composedAddress.length < 3) result.add('address');
    if (_applies('floors_count')) {
      final count = _optionalInt(_floorsCount) ?? 0;
      if (count < 1 || count > 50) result.add('floors_count');
      if (_unitsPerFloor.length != count || _unitsPerFloor.any((v) => (int.tryParse(v) ?? 0) < 1 || (int.tryParse(v) ?? 0) > 100)) result.add('units_per_floor');
    }
    if (_type == 'shop' && ((_optionalInt(_shopOpenings) ?? 0) < 1 || (_optionalInt(_shopOpenings) ?? 0) > 100)) result.add('shop_openings');
    if (_type == 'apartment' && !DynamicPropertySchema.floorOptionsFor(_type).containsKey(_floorNumber.text.trim())) result.add('floor_number');
    if (_purpose == 'rent' && _rentalConditionsError() != null) result.add('rental_conditions');
    if (_effectiveImageCount == 0 || _photoKeys.any((key) => !key.startsWith('property-') && !_remotePhotos.containsKey(key))) result.add('photos');
    if (!_isSaiReady) result.add('sai');
    if (_ownershipValidation() != null) result.add('ownership');
    if (_type == 'land' && _landBoundaryGeoJson == null) result.add('boundary');
    if (_contactPolicy.error(_phone.text, required: true) != null || _contactPolicy.error(_whatsapp.text) != null) result.add('contact_phone');
    return result;
  }

  Widget _completionStep() {
    final keys = _completionFields;
    final locationMissing = keys.any(const {'latitude','longitude','governorate','address'}.contains);
    Widget text(String key, TextEditingController controller, String label, {bool numeric = false}) =>
      !keys.contains(key) ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: AppTextField(
        controller: controller, label: label, enabled: !_busy && (!const ['governorate','district','street'].contains(key) || _hasLocation),
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text));
    Widget choice(String key, String label, String? value, Map<String,String> options, ValueChanged<String?> change) => !keys.contains(key)
      ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: AppSelectField<String>(
        value: value, isExpanded: true, decoration: InputDecoration(labelText: label),
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: _busy ? null : change));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('أكمل الناقص فقط', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
      const Text('نقلنا المعلومات التي راجعتها إلى المسودة. أكمل البيانات المطلوبة ثم راجع الإعلان وأرسله.'),
      const SizedBox(height: 12),
      _completedSummary(),
      choice('type','أكد نوع العقار',_typeConfirmed ? _type : null,_typeLabels,(v) => setState(() { _type = v!; _typeConfirmed = true; _clearHiddenFields(); _completionFields = _missingFields(); })),
      choice('purpose','أكد الغرض',_purposeConfirmed ? _purpose : null,const {'sale':'للبيع','rent':'للإيجار'},(v) => setState(() {
        _purpose = v!; _purposeConfirmed = true; _clearHiddenFields(); _completionFields = _missingFields(); unawaited(_loadSaiPolicy()); })),
      if (_typeConfirmed && _purposeConfirmed) ...[
        text('title',_title,'عنوان الإعلان *'),
        if (_requiresSaleTenure) choice('tenure_type','نوع الملكية *',_tenureType,const {'freehold':'حر','waqf':'وقف'},(v) => setState(() => _tenureType = v)),
        if (locationMissing) ...[const SizedBox(height: 12), _locationCard()],
        text('governorate',_governorate,'المحافظة *'),
        if (keys.contains('boundary')) TextButton(onPressed: _busy ? null : _pickLandBoundary, child: const Text('تحديد حدود الأرض')),
        if (keys.contains('floor_number') && _unitNeedsFloor) Padding(padding: const EdgeInsets.only(top: 12), child: _floorSelector()),
        if (_applies('unit_number')) text('unit_number',_unitNumber,'رقم الوحدة أو موضعها *'),
        if (_applies('area_value')) text('area_value',_area,_type == 'shop' ? 'المساحة بالمتر المربع *' : 'المساحة *',numeric:true),
        if (_applies('floors_count') && (keys.contains('floors_count') || keys.contains('units_per_floor'))) ..._structureFields(),
        if (_type == 'shop' && keys.contains('shop_openings')) ...[const SizedBox(height: 12), AppTextField(key: const ValueKey('listing-shop-openings'), controller: _shopOpenings, label: 'عدد الفتحات *', keyboardType: TextInputType.number, enabled: !_busy)],
        if (_requiresResidential) ...[text('bedrooms',_bedrooms,'غرف النوم *',numeric:true),text('bathrooms',_bathrooms,'الحمامات *',numeric:true)],
        if (_requiresStructure) choice('has_parking','موقف السيارة *',_parkingChoice,const {'yes':'يوجد','no':'لا يوجد'},(v) => setState(() => _parkingChoice = v)),
        if (_supportsFacade) choice('building_facade','واجهة البناء *',_facade,propertyFacadeLabels,(v) => setState(() => _facade = v)),
        text('price',_purpose == 'rent' ? _monthlyRent : _price,_purpose == 'rent' ? 'الإيجار الشهري بالريال اليمني *' : 'سعر البيع بالريال اليمني *',numeric:true),
        if (keys.contains('photos')) ...[const SizedBox(height: 16), _listingPhotos(), const Text('ارفع صورًا حقيقية للعقار.')],
        if (keys.contains('sai')) ListingSaiSection(purpose:_purpose,policy:_saiPolicy,rateController:_saiRate,amountController:_saiAmount,
          basis:_effectivePrice,amountType:_saiAmountType,accepted:_saiAccepted,error:_saiPolicyError,enabled:!_busy,
          onChanged:() => setState(() => _saiTouched = true),onAcceptanceChanged:(v) => setState(() => _saiAccepted = v),
          onAmountTypeChanged:(v) => setState(() { _saiAmountType=v;_saiTouched=true; }),onRetry:_loadSaiPolicy),
        if (keys.contains('contact_phone')) ...[const SizedBox(height: 12),
          AppTextField(controller: _phone, label: 'رقم الاتصال *', keyboardType: TextInputType.phone, enabled: !_busy, helperText: 'رقم جوال يمني من 9 أرقام'),
          if (_contactPolicy.error(_whatsapp.text) != null) AppTextField(controller: _whatsapp, label: 'رقم اتصال آخر', keyboardType: TextInputType.phone, enabled: !_busy)],
        if (keys.contains('rental_conditions')) RentalConditionsEditor(value: _rentalConditions, enabled: !_busy,
          onChanged: (value) => setState(() => _rentalConditions = value)),
        if (keys.contains('ownership')) _ownershipEvidence(),
      ],
      const SizedBox(height: 20),
      TextButton(key: const ValueKey('listing-review-completed'), onPressed: _busy ? null : () => _showFullStep(0), child: const Text('مراجعة وتعديل البيانات المكتملة والاختيارية')),
    ]);
  }

  Widget _completionActions() => _FinalActionsBar(busy:_busy || _descriptionCapture.active,
    onPrevious:() => _showFullStep(_step),onPreview:_preview,
    primaryLabel: 'معاينة الإعلان',
    onSaveDraft:() => _persist(submit:false),onSubmit:_reviewCompletedDraft);

  void _reviewCompletedDraft() {
    FocusScope.of(context).unfocus();
    final validation = _validateForSubmit();
    if (validation != null) {
      setState(() => _completionFields = _missingFields());
      setState(() => _stepError = validation);
      if (_editorScroll.hasClients) {
        _editorScroll.animateTo(0, duration: AppMotion.fast, curve: Curves.easeOut);
      }
      return;
    }
    unawaited(_preview());
  }

  Widget _completedSummary() {
    final missing = _missingFields();
    final lines = <String>[
      if (!missing.contains('title')) _title.text.trim(),
      if (_typeConfirmed && _purposeConfirmed) '${_typeLabels[_type]} ${_purpose == 'rent' ? 'للإيجار' : 'للبيع'}',
      if (!missing.contains('governorate')) _composedAddress,
      if (!missing.contains('price')) _priceSummaryText,
      if (_requiresResidential && !missing.contains('bedrooms') && !missing.contains('bathrooms')) '${_bedrooms.text} غرف نوم · ${_bathrooms.text} حمامات',
      if (_unitNeedsFloor && !missing.contains('floor_number')) 'الدور: ${DynamicPropertySchema.floorOptionsFor(_type)[_floorNumber.text] ?? _floorNumber.text}',
      if (_hasLocation) 'نقطة العقار مؤكدة',
      if (_effectiveImageCount > 0) '$_effectiveImageCount صور في المسودة',
    ];
    return AppSurface(key: const ValueKey('listing-completed-summary'), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('بياناتك المكتملة', style: Theme.of(context).textTheme.titleSmall),
        for (final line in lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text(line)),
        if (missing.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('المتطلبات مكتملة. راجع المعاينة قبل الإرسال.')),
      ]));
  }

  void _returnToCompletion() {
    FocusScope.of(context).unfocus();
    setState(() { _reviewingCompleted = false; _completionOnly = true; _completionFields = _missingFields(); _stepError = null; });
    if (_editorScroll.hasClients) _editorScroll.jumpTo(0);
  }

  String? _rentalConditionsError() {
    int? advance, duration;
    for (final condition in _rentalConditions) {
      if (const ['advance', 'duration'].contains(condition['kind']) && (condition['months'] is! int || (condition['months'] as int) < 1 || (condition['months'] as int) > 24)) return 'أكمل عدد الأشهر للشرط المحدد (من 1 إلى 24).';
      if (condition['kind'] == 'special' && (condition['text']?.toString().trim().isEmpty ?? true)) return 'اكتب الشرط الخاص أو احذفه.';
      if (condition['kind'] == 'advance') advance = condition['months'] as int;
      if (condition['kind'] == 'duration') duration = condition['months'] as int;
    }
    if (advance != null && duration != null && advance > duration) return 'أشهر المقدم لا يمكن أن تتجاوز مدة العقد المحددة.';
    return null;
  }

  List<Widget> _structureFields() {
    final count = (_optionalInt(_floorsCount) ?? 0).clamp(0, 50).toInt();
    return [
      const SizedBox(height: 12),
      TextField(key: const ValueKey('listing-floors-count'), controller: _floorsCount,
        decoration: const InputDecoration(labelText: 'عدد الأدوار *'), keyboardType: TextInputType.number, enabled: !_busy,
        onChanged: (_) => setState(() { final next = (_optionalInt(_floorsCount) ?? 0).clamp(0, 50).toInt(); _unitsPerFloor = List.generate(next, (i) => i < _unitsPerFloor.length ? _unitsPerFloor[i] : (_sameFloorUnits && _unitsPerFloor.isNotEmpty ? _unitsPerFloor.first : '')); })),
      if (count > 0) CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('نفس العدد في كل دور'),
        value: _sameFloorUnits, onChanged: _busy ? null : (value) => setState(() { _sameFloorUnits = value ?? false; if (_sameFloorUnits) _unitsPerFloor = List.filled(count, _unitsPerFloor.isEmpty ? '' : _unitsPerFloor.first); })),
      for (var i = 0; i < (_sameFloorUnits && count > 0 ? 1 : count); i++) Padding(padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(key: ValueKey('listing-units-${_sameFloorUnits ? 'same' : i}-$_unitsGeneration'),
          initialValue: i < _unitsPerFloor.length ? _unitsPerFloor[i] : '', enabled: !_busy, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _sameFloorUnits ? 'عدد الوحدات في كل دور *' : 'الوحدات في الدور ${i + 1} *'),
          onChanged: (value) => setState(() { if (_sameFloorUnits) { _unitsPerFloor = List.filled(count, value); } else { _unitsPerFloor = List.generate(count, (j) => j == i ? value : (j < _unitsPerFloor.length ? _unitsPerFloor[j] : '')); } }))),
    ];
  }

  Map<String, TextEditingController> get _recoveryFields => {
    'broker_sai_rate_percent': _saiRate,
    'fixed_sai_amount': _saiAmount,
    'title': _title, 'description': _description, 'ai_listing_brief': _assistantBrief, 'price': _price, 'monthly_rent': _monthlyRent,
    'rental_term_months': _rentalTermMonths, 'advance_months': _advanceMonths, 'area': _area,
    'floors_count': _floorsCount, 'shop_openings': _shopOpenings, 'bedrooms': _bedrooms, 'bathrooms': _bathrooms, 'governorate': _governorate, 'district': _district,
    'street': _street, 'building_reference': _buildingReference, 'unit_number': _unitNumber,
    'floor_number': _floorNumber, 'phone': _phone, 'whatsapp': _whatsapp,
    'document_owner_name': _documentOwnerName, 'relationship_note': _relationshipNote,
  };

  Map<String, dynamic> _recoverySnapshot() => {
    'editor_version': 10, 'draft_kind': _draftSavedExplicitly ? 'saved' : 'recovery',
    'entry_method': widget.startWithAssistant ? 'assistant' : 'manual',
    'media_version':1, 'units_per_floor': _unitsPerFloor, 'same_floor_units': _sameFloorUnits, 'sai_amount_type': _saiAmountType, 'rental_conditions': _rentalConditions, 'unit_occupies_entire_floor': _wholeFloor, 'sai_touched': _saiTouched, 'sai_terms_accepted': _saiAccepted,
    'type_confirmed': _typeConfirmed, 'purpose_confirmed': _purposeConfirmed, 'completion_only': _completionOnly, 'completion_reviewing': _reviewingCompleted,
    'draft_key': _draftKey, 'server_revision': _draftRevision, 'image_tokens': _localPhotoKeys, 'image_order': _photoKeys,
    'remote_images':_remotePhotos, 'removed_image_keys':_removedPhotoKeys.toList(), 'photo_states':_photoStates,
    'account_checkpoint_key':_checkpointKey, 'account_checkpoint_signature':_checkpointSignature,
    if (_ownershipProofPath != null) 'ownership_proof_path':_ownershipProofPath,
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
    if (!_recoveryReady || _recoveryFinished || _recoveryUserId == null || _busy || _descriptionCapture.active || !_sessionValid || _disposed) return;
    if (_initialEditSignature!=null && _editSignature==_initialEditSignature && _confirmedEditSignature==null && !_recoverySaved && widget.accountDraft==null) return;
    if (_hasUnsavedChanges && _accountSaved) super.setState(() => _accountSaved=false);
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(milliseconds: 650), () => unawaited(_saveRecovery()));
  }

  Future<bool> _writeLocalRecovery() async {
    final userId = _recoveryUserId;
    if (userId == null || !_recoveryReady || _recoveryFinished || _disposed) return false;
    final data = _recoverySnapshot(), images = List<String>.of(_imagePaths);
    final signature = jsonEncode([data, images]);
    try {
      await _recoveryStore.write(userId, widget.existingProperty?.id, data, images);
      if (_draftSavedExplicitly && widget.existingProperty == null) await _recoveryStore.pinExplicitSave(userId);
      _lastRecoverySignature = signature;
      if (mounted && !_recoveryFinished && !_disposed) super.setState(() { _recoverySaved = true; _recoveryFailed = false; });
      return true;
    } catch (_) { if (mounted && !_disposed) super.setState(() { _recoverySaved=false;_recoveryFailed=true; });return false; }
  }

  Future<void> _saveRecovery({bool retryFailed = false}) async {
    if (!_recoveryReady || _recoveryFinished || !_sessionValid || _disposed || _recoveryUserId==null) return;
    final signature=jsonEncode([_recoverySnapshot(),_imagePaths]);
    if (signature==_lastRecoverySignature && _accountSaved) return;
    if (retryFailed) _retryPhotoKeys.addAll(_photoKeys.where((key)=>_photoStates[key]=='failed'));
    await _writeLocalRecovery();
    if (!_sessionValid || _disposed || _recoveryFinished) return;
    final data=_recoverySnapshot();
    await _saveAccount(data,{for (final path in List<String>.of(_imagePaths)) _localPhotoKeys[path]!:path});
  }

  Future<void> _requestExit() async {
    if (_exitDialogOpen || _disposed) return;
    if (_reviewingCompleted && !_busy) { _returnToCompletion(); return; }
    if (!_hasUnsavedChanges && !_busy) { _leaveEditor();return; }
    _exitDialogOpen=true;
    final choice=await AppDialog.show<String>(context,title:'لديك تعديلات غير محفوظة',
      content:const Text('يمكنك متابعة التعديل أو حفظ المسودة قبل الخروج. التجاهل يترك آخر حفظ مؤكد على الحساب.'),
      actions:[
        TextButton(key:const ValueKey('listing-exit-continue'),onPressed:()=>Navigator.pop(context,'continue'),child:const Text('متابعة التعديل')),
        TextButton(key:const ValueKey('listing-exit-discard'),onPressed:_busy?null:()=>Navigator.pop(context,'discard'),child:const Text('تجاهل التغييرات')),
        TextButton(key:const ValueKey('listing-exit-save'),onPressed:_busy?null:()=>Navigator.pop(context,'save'),child:const Text('حفظ المسودة')),
      ]);
    if (!mounted) return;
    try {
      if (choice=='discard') {
        _recoveryTimer?.cancel();_pendingAccount=null;_recoveryFinished=true;
        for (final cancel in _photoCancels.values) { cancel.cancel('Discarded unsaved changes'); }
        if (_recoveryUserId!=null) await _recoveryStore.clear(_recoveryUserId!,widget.existingProperty?.id);
        if (mounted) _leaveEditor();
      } else if (choice=='save') {
        _draftSavedExplicitly = true;
        await _saveRecovery(retryFailed:true);
        if (!mounted) return;
        if (_accountSaved && !_recoveryFailed) { _leaveEditor(); }
        else { setState(()=>_stepError='لم يكتمل حفظ المسودة. بياناتك باقية هنا؛ أعد المحاولة أو تابع التعديل.'); }
      }
    } catch (_) { _recoveryFinished=false;if (mounted) setState(()=>_stepError='تعذر إتمام الخروج. بياناتك باقية هنا.'); }
    finally { _exitDialogOpen=false; }
  }

  void _leaveEditor() {
    setState(()=>_allowExit=true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) { Navigator.of(context).pop(); }
      else { context.go('/my-listings'); }
    });
  }

  Future<void> _restoreRecovery() async {
    if (_recoveryUserId == null) {
      try {
        final actor = await ref.read(authControllerProvider.future).timeout(const Duration(seconds:15));
        if (!mounted) return;
        _recoveryUserId = actor?.id;
      } catch (_) {}
    }
    if (!mounted) return;
    final userId = _recoveryUserId;
    if (userId == null) { _recoveryReady = true; super.setState(() {}); return; }
    Map<String,dynamic>? local = widget.localRecovery;
    if (local == null && !widget.startFresh) {
      try { local=await _recoveryStore.read(userId, widget.existingProperty?.id).timeout(const Duration(seconds:8)); }
      catch (_) { _recoveryFailed=true; }
    }
    final useLocal=local!=null && (widget.accountDraft==null || local['draft_key']==widget.accountDraft!.key);
    final data = useLocal ? local : widget.accountDraft?.payload;
    if (!mounted) return;
    if (data != null) {
      _draftSavedExplicitly = _draftSavedExplicitly || !isAutomaticListingRecovery(data) || widget.accountDraft?.propertyId != null;
      if (widget.accountDraft == null && data['draft_key'] is String) _draftKey = data['draft_key'] as String;
      if (widget.accountDraft == null && data['server_revision'] is int) _draftRevision = data['server_revision'] as int;
      _checkpointKey=data['account_checkpoint_key'] as String?;
      _checkpointSignature=data['account_checkpoint_signature'] as String?;
      _needsReconcile=useLocal && _draftRevision>0;
      _typeConfirmed = data['type_confirmed'] == true || ((data['editor_version'] as num? ?? 0) < 8); _purposeConfirmed = data['purpose_confirmed'] == true || ((data['editor_version'] as num? ?? 0) < 8);
      _completionOnly = data['completion_only'] == true;
      _reviewingCompleted = data['completion_reviewing'] == true && !_completionOnly;
      if (data['image_tokens'] is Map) _localPhotoKeys.addAll(Map<String,String>.from(data['image_tokens'] as Map));
      if (data['remote_images'] is Map) _remotePhotos.addAll(Map<String,String>.from(data['remote_images'] as Map));
      _removedPhotoKeys.addAll((data['removed_image_keys'] as List? ?? const []).whereType<String>());
      if (data['photo_states'] is Map) _photoStates.addAll(Map<String,String>.from(data['photo_states'] as Map));
      _photoOrder = (data['image_order'] as List? ?? const []).whereType<String>().toList();
      _unitsPerFloor = (data['units_per_floor'] as List? ?? const []).map((e) => e?.toString() ?? '').toList();
      _sameFloorUnits = data['same_floor_units'] == true && _unitsPerFloor.toSet().length <= 1;
      _unitsGeneration++;
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
      _ownershipProofPath=data['ownership_proof_path'] as String?;
      for (final key in _photoKeys) {
        if (_remotePhotos.containsKey(key)) { _photoStates[key]='complete'; }
        else if (_photoStates[key]=='uploading' || _photoStates[key]=='processing') { _photoStates[key]='queued'; }
      }
      final serverId = data['server_property_id'];
      if (widget.existingProperty == null && serverId is int && serverId > 0) _recoveredServerId = serverId;
      if (const ['percentage', 'fixed'].contains(data['sai_amount_type'])) {
        _saiAmountType = data['sai_amount_type'] as String;
      } else if (data['sai_touched'] == true && fields is Map && (fields['broker_sai_rate_percent']?.toString().trim().isNotEmpty ?? false)) {
        _saiAmountType = 'percentage';
      }
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
      if (data['proof_needs_reselection'] == true && _ownershipProofPath==null) _message('استعدنا بيانات الإعلان. أعد اختيار ملف إثبات الملكية عند إكمال المسودة.');
    }
    if (_recoveredServerId!=null) await _resolveRecoveredDraft();
    if (!mounted || !_sessionValid) return;
    _clearHiddenFields();
    if (_completionOnly) _completionFields = _missingFields();
    _recoveryReady = true;
    _lastRecoverySignature = jsonEncode([_recoverySnapshot(), _imagePaths]);
    _initialEditSignature=useLocal ? '' : _editSignature;
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
    if (rate.isFinite && rate > 100) return 'أقصى نسبة للسعي 100%';
    if (!rate.isFinite || rate < 0 || maximum == null || rate > maximum || (rate * 100 - (rate * 100).round()).abs() > .000001) {
      return 'أدخل نسبة سعي صحيحة ضمن الحد المسموح وبدقتين عشريتين على الأكثر.';
    }
    return null;
  }
  String get _saiDisplayText {
    final policy = _saiPolicy;
    if (policy == null) return 'سياسة السعي غير محملة';
    if (_fixedSai && _enteredSaiAmount.isFinite && _enteredSaiAmount > 0) {
      return 'السعي ${_enteredSaiAmount.toStringAsFixed(2)} ريال';
    }
    final rate = policy.isOwner || _enteredSaiRate == 0 ? policy.fixedRatePercent : _enteredSaiRate;
    return 'السعي ${rate ?? '—'}%';
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
    _descriptionCapture = VoiceCaptureController(ref.read(voiceInputProvider))..addListener(_descriptionVoiceChanged);
    final retryAt = ref.read(aiRepositoryProvider).descriptionRetryAt;
    if (retryAt?.isAfter(DateTime.now()) == true) {
      _descriptionRetryTimer = Timer(retryAt!.difference(DateTime.now()), () { if (mounted) setState(() {}); });
    }
    _price.addListener(_onPriceChanged);
    _monthlyRent.addListener(_onPriceChanged);
    _advanceMonths.addListener(_onPriceChanged);
    _recoveryStore = ref.read(listingRecoveryStoreProvider);
    _accountRepository = ref.read(listingAccountDraftRepositoryProvider);
    _draftKey = widget.accountDraft?.key ?? newListingDraftKey();
    if (widget.accountDraft != null) _adoptAccountDraft(widget.accountDraft!);
    _typeConfirmed = widget.existingProperty != null; _purposeConfirmed = widget.existingProperty != null;
    final initialActor = ref.read(authControllerProvider).asData?.value;
    _recoveryUserId = initialActor?.id;
    if (_existing == null) _phone.text = ListingContactPolicy.normalize(initialActor?.phone ?? '');
    Future.microtask(() async {
      try {
        if (_phone.text.isEmpty && _existing == null) {
          final actor=await ref.read(authControllerProvider.future).timeout(const Duration(seconds:15));
          if(mounted && _sessionValid)_phone.text=ListingContactPolicy.normalize(actor?.phone ?? '');
        }
      } catch (_) {}
      await _restoreRecovery(); if (mounted) await _loadSaiPolicy();
      try { final policy = await ref.read(propertyRepositoryProvider).listingContactPolicy(); if (mounted && ref.read(authControllerProvider).asData?.value?.id == _recoveryUserId) setState(() => _contactPolicy = policy); } catch (_) {}
      if (mounted && widget.startWithAssistant) { WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _assist(prepareDraft: true);
      }); }
    });
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
    _floorsCount.text = property.floorsCount?.toString() ?? '';
    _unitsPerFloor = property.unitsPerFloor.map((e) => e.toString()).toList();
    _sameFloorUnits = _unitsPerFloor.isNotEmpty && _unitsPerFloor.toSet().length == 1;
    _shopOpenings.text = property.shopOpenings?.toString() ?? '';
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
    _latitude = property.hasValidLocation ? property.latitude : null;
    _longitude = property.hasValidLocation ? property.longitude : null;
    _buildingReference.text = property.buildingReference ?? '';
    _unitNumber.text = property.unitNumber ?? '';
    _floorNumber.text = property.floorNumber ?? '';

    _landBoundaryGeoJson = property.landBoundaryGeoJson;
    _phone.text = ListingContactPolicy.normalize(property.contactPhone ?? '');
    _whatsapp.text = ListingContactPolicy.normalize(property.contactWhatsapp ?? '');
    _ownershipDocumentType = property.ownershipDocumentType;
    _documentOwnerName.text = property.documentOwnerName ?? '';
    _relationshipType = property.ownerRelationshipType;
    _relationshipNote.text = property.ownerRelationshipNote ?? '';
    unawaited(_refreshSai(property.id));
  }

  @override
  void dispose() {
    _cancelDescriptionVoice();
    _descriptionCapture.removeListener(_descriptionVoiceChanged); _descriptionCapture.dispose();
    _editorScroll.dispose();
    _descriptionRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _price.removeListener(_onPriceChanged);
    _monthlyRent.removeListener(_onPriceChanged);
    _advanceMonths.removeListener(_onPriceChanged);
    _recoveryTimer?.cancel();
    final snapshot=_recoverySnapshot(), paths=List<String>.of(_imagePaths), userId=_recoveryUserId;
    final temporary=[...paths,if(_ownershipProofPath!=null)_ownershipProofPath!].where((path)=>!ListingRecoveryStore.isSavedMedia(path));
    _disposed=true;_pendingAccount=null;
    for (final cancel in _photoCancels.values) { cancel.cancel('Editor closed'); }
    // Never delete the only remaining copy if the durable device write failed.
    final backup=!_recoveryFinished && _recoveryReady && userId!=null && (_hasUnsavedChanges || _recoverySaved)
      ? _recoveryStore.write(userId,widget.existingProperty?.id,snapshot,paths) : Future<void>.value();
    unawaited(backup.then((_)=>_mediaPicker.clearTemporaryFiles(temporary)).catchError((_) {}));
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
      _floorsCount,
      _shopOpenings,
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
    ref.listen(authControllerProvider,(previous,next) {
      final actor=next.asData;
      if (actor==null || _recoveryUserId==null || actor.value?.id==_recoveryUserId || !_sessionValid) return;
      _cancelDescriptionVoice();
      unawaited(_writeLocalRecovery());_pendingAccount=null;
      for (final cancel in _photoCancels.values) { cancel.cancel('Account changed'); }
      super.setState(()=>_sessionValid=false);
    });
    final correctionReason =
        _existing?.reviewStatus == 'returned_for_correction'
            ? _existing?.lastReviewReason
            : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope<Object?>(canPop:_allowExit || !_sessionValid || (!_reviewingCompleted && !_hasUnsavedChanges && !_busy),
        onPopInvokedWithResult:(didPop,result) { if (!didPop) unawaited(_requestExit()); },
      child: Scaffold(
        appBar: AppAppBar(
          title: _isEditing ? 'تعديل الإعلان' : 'إضافة عقار',
          actions: [IconButton(key: const ValueKey('listing-completion'), tooltip: 'نواقص الإعلان',
            onPressed: _busy || !_sessionValid || _descriptionCapture.active ? null : _reviewCompletion, icon: const EbrokerIcon(Icons.fact_check_outlined)),
            if (!_completionOnly) Center(child: Padding(padding: const EdgeInsetsDirectional.only(end: 16),
            child: EbrokerText('${_step + 1}/4', size: 16, weight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary)))],
        ),
        bottomNavigationBar: !_recoveryReady || !_sessionValid ? null : _completionOnly ? _completionActions() : _actions(),
        body: SafeArea(
          bottom: false,
          child: !_sessionValid ? const Center(child:Text('تغيّر الحساب. عُد وافتح مسودات الحساب الحالي.')) : !_recoveryReady ? const AppLoadingState() : Column(
            children: [
              if (_recoveryUserId != null) Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 0), child: Text(
                _recoveryFailed ? 'تعذر حفظ نسخة الجهاز. مدخلاتك باقية هنا؛ أعد المحاولة قبل الخروج.' : _accountConflict ? 'تغيرت المسودة على جهاز آخر. افتح أحدث نسخة قبل المتابعة.' : _accountError != null ? 'تعذر الحفظ على الحساب. ${_recoverySaved ? 'تقدمك محفوظ على الجهاز.' : ''} أعد المحاولة.' : _accountSyncing ? 'جارٍ حفظ تقدمك على حسابك…' : _accountSaved ? 'حُفظ تقدمك وصورك على حسابك' : 'يُحفظ تقدمك تلقائيًا على حسابك',
                style: Theme.of(context).textTheme.bodySmall)),
              if (_accountError != null && !_accountConflict) TextButton(onPressed: _busy || _accountSyncing ? null : ()=>_saveRecovery(retryFailed:true), child: const Text('إعادة محاولة الحفظ')),
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
                  controller: _editorScroll,
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
              if (_stepError != null) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Semantics(liveRegion: true, child: Text(_stepError!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
            ],
          ),
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
          AppSelectField<String>(
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

  Widget _locationCard() => AppSurface(
    key: const ValueKey('listing-location-status'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        EbrokerIcon(_hasLocation ? Icons.check_circle_outline : Icons.location_on_outlined,
          color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(_hasLocation ? 'تم تحديد موقع العقار على الخريطة' : 'حدد نقطة العقار أولًا',
          style: Theme.of(context).textTheme.titleSmall)),
      ]),
      const SizedBox(height: 8),
      Text(_hasLocation ? 'النقطة محفوظة عند الرجوع والمعاينة. عدّلها فقط إذا تغيّر موقع العقار.'
        : 'استخدم موقعك الحالي أو حدد النقطة يدويًا على الخريطة ثم أكدها. بعدها يمكنك تصحيح العنوان.'),
      const SizedBox(height: 12),
      AppButton(key: const ValueKey('listing-select-location'),
        label: _hasLocation ? 'تعديل الموقع على الخريطة' : 'تأكيد الموقع على الخريطة',
        icon: Icons.map_outlined, style: _hasLocation ? AppButtonStyle.tonal : AppButtonStyle.filled,
        onPressed: _busy || _resolvingLocation || _selectingLocation ? null : _selectOnMap, expand: true),
      const SizedBox(height: 8),
      TextButton.icon(key: const ValueKey('listing-current-location'),
        onPressed: _busy || _resolvingLocation || _selectingLocation ? null : () => _selectLocation(useCurrent: true),
        icon: const Icon(Icons.my_location, size: 19), label: const Text('تحديد موقعي الحالي')),
      if (_selectingLocation) const LinearProgressIndicator(),
      if (_locationError != null) Text(_locationError!, style: Theme.of(context).textTheme.bodySmall),
      if (_locationNeedsSettings) TextButton(key: const ValueKey('listing-location-settings'), onPressed: () => ref.read(appPermissionSettingsProvider)(), child: const Text('فتح إعدادات الإذن')),
      if (_locationServiceDisabled) TextButton(key: const ValueKey('listing-enable-location-service'), onPressed: () => ref.read(locationServiceSettingsProvider)(), child: const Text('تفعيل خدمة الموقع')),
      if (_hasLocation && _showLocationPreview) Padding(padding: const EdgeInsets.only(top: 12), child: PropertyLocationPreview(
        key: const ValueKey('listing-location-preview'), latitude: _latitude!, longitude: _longitude!, onOpen: _selectOnMap)),
      if (_hasLocation && _completionOnly) TextButton(onPressed: () => _showFullStep(1), child: const Text('تصحيح العنوان النصي')),
    ]));

  Widget _locationStep() {
    final hasLocation = _hasLocation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(title: 'موقع العقار',
          subtitle: 'ثبّت الموقع مرة واحدة، وسيبقى محفوظًا مع المسودة.'),
        const SizedBox(height: AppSpacing.s12),
        _locationCard(),
        if (_resolvingLocation) ...[
          const SizedBox(height: AppSpacing.s12),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: AppSpacing.s16),
        AppTextField(controller: _governorate, label: 'المحافظة *', enabled: !_busy && hasLocation),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(controller: _district, label: 'المنطقة / الحي', enabled: !_busy && hasLocation),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(controller: _street, label: 'الشارع', enabled: !_busy && hasLocation),
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
            final unit = AppSelectField<String>(value: _areaUnit, isExpanded: true,
              decoration: const InputDecoration(labelText: 'وحدة المساحة'),
              items: propertyAreaUnitLabels.entries.map((entry) => DropdownMenuItem(value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis))).toList(growable: false),
              onChanged: _busy ? null : (value) => setState(() => _areaUnit = value ?? 'sqm'));
            return MediaQuery.textScalerOf(context).scale(14) > 21
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [area, const SizedBox(height: 12), unit])
              : Row(children: [Expanded(flex: 2, child: area), const SizedBox(width: 8), Expanded(flex: 3, child: unit)]);
          }),
        if (_applies('floors_count')) ..._structureFields(),
        if (_type == 'shop') ...[const SizedBox(height: 12), AppTextField(key: const ValueKey('listing-shop-openings'), controller: _shopOpenings, label: 'عدد الفتحات *', keyboardType: TextInputType.number, enabled: !_busy)],
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
          AppSelectField<String>(value: _elevatorChoice ?? 'unknown', isExpanded: true,
            decoration: const InputDecoration(labelText: 'المصعد'), items: const [
              DropdownMenuItem(value: 'unknown', child: Text('غير مذكور')),
              DropdownMenuItem(value: 'yes', child: Text('يوجد مصعد')),
              DropdownMenuItem(value: 'no', child: Text('بدون مصعد')),
            ], onChanged: _busy ? null : (value) => setState(() => _elevatorChoice = value == 'unknown' ? null : value)),
        ],
        if (_requiresStructure) ...[
          const SizedBox(height: AppSpacing.s16),
          AppSelectField<String>(
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
          AppSelectField<String>(
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
        if (_type == 'land') ...[const SizedBox(height: 12), AppSelectField<String>(value: _facade, isExpanded: true,
          decoration: const InputDecoration(labelText: 'واجهة الأرض (اختياري)'), items: propertyFacadeLabels.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
          onChanged: _busy ? null : (value) => setState(() => _facade = value))],
        const SizedBox(height: 24),
        _listingPhotos(),
        const SizedBox(height: 8),
        const Text('يجب أن تكون الصور حقيقية للعقار المعلن عنه.'),
        const SizedBox(height: 20),
        AppTextField(controller: _description, label: 'وصف العقار',
          hint: 'اذكر التفاصيل التي لا تظهر في المواصفات: مجلس، حوش، مدخل مستقل، حمام خارجي، سطح…',
          enabled: !_busy && !_descriptionCapture.active, maxLines: 5),
        if (_descriptionCapture.active) InlineVoiceCapture(capture: _descriptionCapture,
          listeningLabel: 'جارٍ إملاء الوصف', onCancel: _cancelDescriptionVoice, onRestart: _restartDescriptionVoice),
        if (!_descriptionCapture.active && !_busy && !_descriptionBusy) Wrap(spacing: 8, children: [
          if (_lastDescriptionVoiceBase != null && _description.text == _lastDescriptionVoiceText) TextButton(onPressed: _restartDescriptionVoice, child: const Text('ابدأ الإملاء من جديد')),
          TextButton(onPressed: () => _dictateDescription(wholeRecording: true), child: const Text('تسجيل مقطع كامل (بديل)')),
        ]),
        if (!_descriptionCapture.active) TextButton.icon(key: const ValueKey('listing-description-voice'),
          onPressed: _busy || _descriptionBusy ? null : _dictateDescription,
          icon: const Icon(Icons.mic_none, size: 19), label: const Text('إملاء الوصف')),
        if (_descriptionCapture.error != null) Text(_descriptionCapture.error!, style: Theme.of(context).textTheme.bodySmall),
        if (_descriptionCapture.permissionDenied) TextButton.icon(onPressed:()=>ref.read(appPermissionSettingsProvider)(),
          icon:const Icon(Icons.settings_outlined),label:const Text('فتح إعدادات الميكروفون')),
        if (_descriptionCapture.canRetry) TextButton(onPressed: _busy || _descriptionBusy ? null : () => _dictateDescription(retry: true),
          child: const Text('إعادة محاولة تفريغ الوصف')),
        if (_descriptionBusy) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Expanded(child: Text('جارٍ تجهيز الوصف…'))])),
        if (_descriptionError != null) Text(_descriptionError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ValueListenableBuilder<TextEditingValue>(valueListenable: _description, builder: (_, value, __) =>
          TextButton.icon(key: const ValueKey('listing-description-generate'), onPressed: _busy || _descriptionBusy || _descriptionCapture.active || _descriptionCoolingDown ? null : _generateDescription,
            icon: const EbrokerIcon(Icons.edit_note_outlined, size: 18), label: Text(value.text.trim().isEmpty ? 'اقتراح وصف من البيانات' : 'حسّن الوصف'))),
        if (_purpose == 'rent') RentalConditionsEditor(value: _rentalConditions, enabled: !_busy,
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
          label: 'رقم الاتصال *',
          helperText: 'رقم جوال يمني من 9 أرقام',
          onChanged: (_) { if (_validateContacts) setState(() {}); },
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
        if (_validateContacts && _contactPolicy.error(_phone.text, required: true) != null) Text(_contactPolicy.error(_phone.text, required: true)!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: AppSpacing.s12),
        AppTextField(
          controller: _whatsapp,
          label: 'رقم اتصال آخر (اختياري)',
          onChanged: (_) { if (_validateContacts) setState(() {}); },
          keyboardType: TextInputType.phone,
          enabled: !_busy,
        ),
        if (_validateContacts && _contactPolicy.error(_whatsapp.text) != null) Text(_contactPolicy.error(_whatsapp.text)!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }

  Widget _listingPhotos() {
    final keys = _photoKeys;
    final height=166+MediaQuery.textScalerOf(context).scale(13)*5;
    return AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('صور الإعلان ($_effectiveImageCount/12)',style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      AppButton(label:'إضافة صور',icon:Icons.add_photo_alternate_outlined,expand:true,style:AppButtonStyle.tonal,onPressed:_busy?null:_pickImages),
      if (keys.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('لم تضف صورًا بعد. أضف صورة واضحة للعقار لإرساله للمراجعة.')),
      if (keys.isNotEmpty) ...[
        const SizedBox(height:12),SizedBox(height:height,child:ReorderableListView.builder(scrollDirection:Axis.horizontal,
          itemCount:keys.length,onReorder:_busy ? (_,__) {} : (from,to) => setState(() {
            if(to>from)to--;final order=List<String>.of(keys);final key=order.removeAt(from);order.insert(to,key);_photoOrder=order;
          }),itemBuilder:(_,index) {
            final key=keys[index], path=_localPath(key), url=_photoUrl(key);
            final state=key.startsWith('property-') || _remotePhotos.containsKey(key) ? 'complete' : _photoStates[key] ?? (path==null ? 'failed':'queued');
            final label=const {'complete':'مكتمل','queued':'بانتظار الرفع','uploading':'جارٍ رفع الصورة','processing':'جارٍ معالجة الصورة','failed':'تعذر رفع الصورة'}[state] ?? 'بانتظار الرفع';
            return Container(key:ValueKey(key),width:174,margin:const EdgeInsetsDirectional.only(end:10),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              SizedBox(height:110,child:Stack(fit:StackFit.expand,children:[
                ClipRRect(borderRadius:BorderRadius.circular(8),child:path!=null ? Image.file(File(path),fit:BoxFit.cover,cacheWidth:400,
                  errorBuilder:(_,__,___)=>url!=null ? _remotePhoto(url) : const Icon(Icons.broken_image_outlined))
                  : url!=null ? _remotePhoto(url) : const Icon(Icons.photo_outlined)),
                PositionedDirectional(top:0,end:0,child:IconButton.filled(tooltip:'إزالة الصورة',onPressed:_busy?null:()=>_removeDraftPhoto(key),icon:const Icon(Icons.close,size:18))),
                PositionedDirectional(top:0,start:0,child:PopupMenuButton<String>(key:ValueKey('media-menu-$key'),tooltip:'خيارات الصورة',
                  enabled:!_busy,icon:Icon(index==0 ? Icons.star:Icons.more_horiz,color:Theme.of(context).colorScheme.primary),
                  onSelected:(action) { if(action=='primary') { setState(()=>_photoOrder=[key,...keys.where((k)=>k!=key)]); }
                    else if(action=='replace') { unawaited(_replacePhoto(key)); } },
                  itemBuilder:(_)=>[const PopupMenuItem(value:'primary',child:Text('جعلها الصورة الرئيسية')),const PopupMenuItem(value:'replace',child:Text('استبدال الصورة'))])),
              ])),
              if(index==0) const Text('الرئيسية',style:TextStyle(fontWeight:FontWeight.w600)),
              Semantics(liveRegion:true,child:Tooltip(message:_photoErrors[key] ?? label,child:Text(label,key:ValueKey('media-status-$key'),maxLines:2,style:Theme.of(context).textTheme.bodySmall))),
              if(state=='uploading' || state=='processing') LinearProgressIndicator(value:state=='uploading' ? _photoProgress[key] : null),
              if(state=='failed') TextButton(key:ValueKey('media-retry-$key'),onPressed:_busy || _accountSyncing ? null : ()=>_retryPhoto(key),
                child:Text(path==null ? 'اختر الملف مجددًا':'إعادة المحاولة')),
            ]));
          })),const SizedBox(height:6),const Text('اسحب الصور لترتيبها، أو اختر الرئيسية من خيارات الصورة. إعادة المحاولة ترفع الملف المتعثر كاملًا فقط.'),
      ],
    ]));
  }

  String? _localPath(String key) {
    for (final entry in _localPhotoKeys.entries) { if (entry.value==key && _imagePaths.contains(entry.key)) return entry.key; }
    return null;
  }
  String? _photoUrl(String key) {
    if (_remotePhotos[key] case final String url) return url;
    for (final image in _existing?.images ?? const <PropertyImageItem>[]) { if ('property-${image.id}'==key) return image.url; }
    return null;
  }
  Widget _remotePhoto(String url) => url.contains('/api/property-media/') || url.contains('/listing-editor-drafts/')
    ? ListingDraftPhoto(url:url) : AppPropertyMedia(imageUrl:url,height:110);

  Future<void> _retryPhoto(String key) async {
    if (_localPath(key)==null) { await _replacePhoto(key);return; }
    _retryPhotoKeys.add(key);
    await _writeLocalRecovery();
    if (mounted && _sessionValid) {
      final pending={for (final path in _imagePaths)
        if (_localPhotoKeys[path]==key || (_photoStates[_localPhotoKeys[path]] ?? 'queued')=='queued') _localPhotoKeys[path]!:path};
      await _saveAccount(_recoverySnapshot(),pending);
    }
  }

  Future<void> _replacePhoto(String key) async {
    try {
      final picked=await _mediaPicker.pickImages();
      if (!mounted || !_sessionValid) { await _mediaPicker.clearTemporaryFiles(picked);return; }
      final valid=await _validImagePaths(picked);
      if (valid.isEmpty) return;
      await _mediaPicker.clearTemporaryFiles(valid.skip(1));
      final path=valid.first, next=newListingDraftKey(), order=List<String>.of(_photoKeys), index=order.indexOf(key);
      _photoCancels[key]?.cancel('Image replaced');
      setState(() {
        final old=_localPath(key);if(old!=null)_imagePaths.remove(old);
        _removedPhotoKeys.add(key);_localPhotoKeys[path]=next;_imagePaths.add(path);_photoStates[next]='queued';
        if(index>=0) { order[index]=next; } else { order.add(next); }
        _photoOrder=order;
      });
      await _saveRecovery();
    } catch (_) { if(mounted)_message('تعذر استبدال الصورة. الصورة السابقة باقية حتى اختيار بديل.'); }
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
          AppSelectField<String>(
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
          AppSelectField<String>(
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
    if (_reviewingCompleted) {
      return Material(color: Theme.of(context).colorScheme.surface, child: SafeArea(top: false,
      child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: TextButton(onPressed: _busy || _step == 0 ? null : () => _showFullStep(_step - 1), child: const Text('السابق'))),
          Expanded(child: TextButton(onPressed: _busy || _step == 3 ? null : () => _showFullStep(_step + 1), child: const Text('التالي'))),
        ]),
        EbrokerStepButton(key: const ValueKey('listing-return-completion'), label: 'العودة إلى النواقص',
          onPressed: _busy || _descriptionCapture.active ? null : _returnToCompletion, expand: true),
      ]))));
    }
    if (_step < 3) {
      return _BottomBar(
        children: [
            Expanded(
              child: EbrokerStepButton(
                label: 'السابق',
                style: AppButtonStyle.outlined,
                onPressed: _busy || _descriptionCapture.active ? null : () {
                  if (_step > 0) { _showFullStep(_step - 1); } else { Navigator.of(context).maybePop(); }
                },
                expand: true,
              ),
            ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            flex: 2,
            child: EbrokerStepButton(
              label: 'التالي',
              onPressed: _busy || _descriptionCapture.active ? null : _next,
              expand: true,
            ),
          ),
        ],
      );
    }

    return _FinalActionsBar(
      busy: _busy || _descriptionCapture.active,
      onPrevious: () => _showFullStep(_step - 1),
      onPreview: _preview,
      onSaveDraft: () => _persist(submit: false),
      onSubmit: () => _persist(submit: true),
    );
  }

  void _next() {
    if (_busy || _descriptionCapture.active) return;
    FocusScope.of(context).unfocus();
    if (_step == 0 && !_completionOnly) { _typeConfirmed = true; _purposeConfirmed = true; }
    final message = _validationMessageForStep(_step);
    if (message != null) {
      setState(() => _stepError = message);
      return;
    }
    _showFullStep(_step + 1);
  }

  void _showFullStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() { if (_completionOnly) _reviewingCompleted = true; _completionOnly = false; _step = step.clamp(0, 3).toInt(); _stepError = null; });
    if (_editorScroll.hasClients) _editorScroll.jumpTo(0);
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
      if (!_hasLocation) {
        return 'حدد نقطة العقار على الخريطة أو من موقعك الحالي، ثم أكد الموقع.';
      }
      if (_governorate.text.trim().length < 2) return 'أكمل اسم المحافظة.';
      if (_composedAddress.length < 3) return 'أكمل معلومات عنوان العقار.';
      if (_type == 'land' && _landBoundaryGeoJson == null) {
        return 'ارسم حدود الأرض حتى نتحقق من هوية القطعة ولا نعتمد على الدبوس وحده.';
      }
    }
    if (step == 2) {
      if (_applies('floors_count')) {
        final count = _optionalInt(_floorsCount) ?? 0;
        if (count < 1 || count > 50) return 'أدخل عدد الأدوار من 1 إلى 50.';
        if (_unitsPerFloor.length != count || _unitsPerFloor.any((v) => (int.tryParse(v) ?? 0)<1 || (int.tryParse(v) ?? 0)>100)) return 'أدخل عدد الوحدات في كل دور من 1 إلى 100.';
      }
      if (_type == 'shop' && ((_optionalInt(_shopOpenings) ?? 0)<1 || (_optionalInt(_shopOpenings) ?? 0)>100)) return 'أدخل عدد فتحات المحل من 1 إلى 100.';
      final areaValue = double.tryParse(_area.text.trim());
      if (!_isRentalApartment && (areaValue == null || areaValue <= 0)) return 'أدخل مساحة صحيحة أكبر من صفر.';
      final images = _effectiveImageCount;
      if (requireImages && images == 0) return 'أضف صورًا حقيقية للعقار قبل المتابعة.';
      if (_purpose == 'rent' && _rentalConditionsError() != null) return _rentalConditionsError();
      if (_isUnitType) {
        if (!_wholeFloor && !_isRentalApartment && _unitNumber.text.trim().isEmpty) {
          return 'أدخل رقم الوحدة أو موضعها لتمييزها عن غيرها.';
        }
        if (_unitNeedsFloor && _floorNumber.text.trim().isEmpty) {
          return 'أدخل رقم الدور.';
        }
        if (_type == 'apartment' && !DynamicPropertySchema.floorOptionsFor(_type).containsKey(_floorNumber.text.trim())) return 'اختر دورًا من الأرضي إلى السابع.';
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
      _validateContacts = true;
      final phoneError = _contactPolicy.error(_phone.text, required: true) ?? _contactPolicy.error(_whatsapp.text);
      if (phoneError != null) return phoneError;
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
    if (_photoKeys.any((key)=>!key.startsWith('property-') && !_remotePhotos.containsKey(key))) return 'لم تجهز كل الصور بعد. انتظر الرفع والمعالجة، أو أعد محاولة الصورة المتعثرة.';
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
        _showFullStep(step);
        setState(() => _stepError = message);
        return;
      }
    }
    _showFullStep(target);
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
      if (_whatsapp.text.trim().isNotEmpty) 'رقم اتصال آخر: ${_whatsapp.text.trim()}',
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
    if (_applies('floors_count') && (_optionalInt(_floorsCount) ?? 0) > 0) 'floors_count': _optionalInt(_floorsCount),
    if (_applies('units_per_floor') && _unitsPerFloor.isNotEmpty && _unitsPerFloor.every((v) => (int.tryParse(v) ?? 0)>0)) 'units_per_floor': _unitsPerFloor.map(int.parse).toList(),
    if (_type == 'shop' && (_optionalInt(_shopOpenings) ?? 0)>0) 'shop_openings': _optionalInt(_shopOpenings),
    if (_requiresResidential && (_optionalInt(_bedrooms) ?? 0) > 0) 'bedrooms': _optionalInt(_bedrooms),
    if (_requiresResidential && (_optionalInt(_bathrooms) ?? 0) > 0) 'bathrooms': _optionalInt(_bathrooms),
    if (_requiresStructure && _parkingChoice != null) 'has_parking': _parkingValue,
    if (_supportsElevator && _elevatorChoice != null) 'has_elevator': _elevatorChoice == 'yes',
    if (_supportsFacade && _facade != null) 'building_facade': _facade,
    if (_unitNeedsFloor && _floorNumber.text.trim().isNotEmpty) 'floor_number': _floorNumber.text.trim(),
    if (_type == 'apartment') 'unit_occupies_entire_floor': _wholeFloor,
  };

  Future<void> _assist({bool prepareDraft = false}) async {
    if (_busy || _descriptionCapture.active) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final result = await AppBottomSheet.show<Map<String, dynamic>>(context, builder: (_) => ListingAiSheet(
      facts: _aiFacts(), propertyId: _existing?.id ?? _recoveredServerId, draftKey: _draftRevision > 0 ? _draftKey : null,
      prepareDraft: prepareDraft, initialMessage: _assistantBrief.text,
      hasExistingDescription: _description.text.trim().isNotEmpty,
      onMessageChanged: (text) => _assistantBrief.text = text));
    if (!mounted || result == null || actor != ref.read(authControllerProvider).asData?.value?.id) return;
    final oldPurpose = _purpose;
    setState(() {
      if (result['description'] is String) _description.text = result['description'] as String;
      if (_typeLabels.containsKey(result['type'])) { _type = result['type'] as String; _typeConfirmed = true; }
      if (const ['sale', 'rent'].contains(result['purpose'])) { _purpose = result['purpose'] as String; _purposeConfirmed = true; }
      for (final entry in <String, TextEditingController>{
        'title': _title, if (!_isRentalApartment) 'area_value': _area, 'governorate': _governorate, 'district': _district, 'street': _street,
        if (_purpose == 'sale') 'price': _price,
        if (_purpose == 'rent') 'monthly_rent': _monthlyRent,
        if (_applies('floors_count')) 'floors_count': _floorsCount,
        if (_type == 'shop') 'shop_openings': _shopOpenings,
        if (_requiresResidential) 'bedrooms': _bedrooms,
        if (_requiresResidential) 'bathrooms': _bathrooms,
        if (_isUnitType) 'floor_number': _floorNumber,
        if (_isUnitType) 'unit_number': _unitNumber,
      }.entries) { if (result[entry.key] != null) entry.value.text = result[entry.key].toString(); }
      if (propertyAreaUnitLabels.containsKey(result['area_unit'])) _areaUnit = result['area_unit'] as String;
      if (_requiresSaleTenure && const ['freehold', 'waqf'].contains(result['tenure_type'])) _tenureType = result['tenure_type'] as String;
      if (_requiresStructure && result['has_parking'] is bool) _parkingChoice = result['has_parking'] == true ? 'yes' : 'no';
      if (_supportsFacade && propertyFacadeLabels.containsKey(result['building_facade'])) _facade = result['building_facade'] as String;
      if (_applies('units_per_floor') && result['units_per_floor'] is List) { _unitsGeneration++; _unitsPerFloor = (result['units_per_floor'] as List).map((e) => e.toString()).toList(); _sameFloorUnits = _unitsPerFloor.isNotEmpty && _unitsPerFloor.toSet().length == 1; }
      if (_supportsElevator && result['has_elevator'] is bool) _elevatorChoice = result['has_elevator'] == true ? 'yes' : 'no';
      if (_type != 'apartment') _wholeFloor = false;
      if (_wholeFloor) _unitNumber.clear();
      if (!_requiresResidential) { _bedrooms.clear(); _bathrooms.clear(); }
      if (!_requiresStructure) { _parkingChoice = null; if (!_supportsFacade) _facade = null; }
      if (!_supportsElevator) _elevatorChoice = null;
      if (!_requiresSaleTenure) _tenureType = null;
      if (!_isUnitType) { _floorNumber.clear(); _unitNumber.clear(); _buildingReference.clear(); }
      // Text corrections preserve the explicitly confirmed geographic point.
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
      final gaps = _completionGaps();
      setState(() {
        _completionOnly = true; _reviewingCompleted = false; _completionFields = _missingFields();
        if (gaps.isNotEmpty) _step = gaps.first.$1;
      });
      if (_editorScroll.hasClients) _editorScroll.jumpTo(0);
    }
    unawaited(_saveRecovery());
    _message('طُبّق الاقتراح في الحقول. راجع بقية الإعلان قبل إرساله.');
  }

  PropertyListingInput _input() {
    final user = ref.read(authControllerProvider).asData?.value;
    return PropertyListingInput(
      inputVersion: 9,
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
      floorsCount: _applies('floors_count') ? _optionalInt(_floorsCount) : null,
      unitsPerFloor: _applies('units_per_floor') ? _unitsPerFloor.map((e) => int.tryParse(e) ?? 0).toList() : const [],
      shopOpenings: _type == 'shop' ? _optionalInt(_shopOpenings) : null,
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
      contactPhone: ListingContactPolicy.normalize(_phone.text),
      contactWhatsapp: ListingContactPolicy.normalize(_whatsapp.text),
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
    if (_persistStarting || _busy || !_sessionValid) return;
    if (!submit) _draftSavedExplicitly = true;
    _persistStarting=true;
    try { await _persistOnce(submit:submit); } finally { _persistStarting=false; }
  }

  Future<void> _persistOnce({required bool submit}) async {
    if (!_recoveryReady || !await _resolveRecoveredDraft()) return;
    if (!mounted || !_sessionValid) return;
    final validation = submit ? _validateForSubmit() : _validateCore();
    if (validation != null) {
      if (!submit) { await _saveRecovery(retryFailed:true); if (mounted && _sessionValid) _message(_accountSaved ? 'حُفظت المسودة على حسابك. يمكنك إكمالها لاحقًا.' : 'لم يكتمل الحفظ على الحساب. أعد المحاولة قبل الخروج.'); } else { setState(() => _stepError = validation); }
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
      if (confirmed != true || !mounted || !_sessionValid) return;
    }

    setState(() => _busy = true);
    _recoveryTimer?.cancel();
    late PropertyDetails draft;
    try {
      await _saveRecovery(retryFailed:true);
      if (!mounted || !_sessionValid) return;
      if (!_accountSaved || _accountConflict) throw StateError('تعذر حفظ المسودة على الحساب.');
      if (!await _resolveRecoveredDraft()) return;
      if (!mounted || !_sessionValid) return;
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

      if (!mounted || !_sessionValid) return;
      setState(() => _workingDraft = draft);
      ref.read(propertyDataRevisionProvider.notifier).state++;
      final acknowledged=await _accountRepository.get(_draftKey);
      if (!mounted || !_sessionValid) return;
      await _clearUploadedTemporaryFiles();
      _adoptAccountDraft(acknowledged);
      _photoOrder.clear(); _removedPhotoKeys.clear(); _remotePhotos.clear(); _localPhotoKeys.clear();
      _accountSaved = false;
      await _saveRecovery();
      if (!mounted || !_sessionValid) return;

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
          if (!mounted || !_sessionValid) return;
          ref.read(propertyDataRevisionProvider.notifier).state++;
        } catch (error) {
          if (mounted) _message('حُفظت المسودة، لكن تعذر حفظ السعي: ${friendlyApiError(error)}');
          return;
        }
      }

      if (submit) {
        try {
          final identityReady = await _checkIdentityBeforeSubmit(draft.id);
          if (!identityReady || !mounted || !_sessionValid) return;
          draft = await repository.submitListing(draft.id);
          if (!mounted || !_sessionValid) return;
          ref.read(propertyDataRevisionProvider.notifier).state++;
        } catch (error) {
          if (mounted) {
            final message = friendlyApiError(error);
            setState(() => _stepError = 'تم حفظ الإعلان كمسودة، لكن تعذر إرساله للمراجعة: $message');
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
      _accountSaved=false;_needsReconcile=true;
      if (mounted) setState(() => _stepError = friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(PropertyDetails property) {
    setState(()=>_allowExit=true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_startedAsEditing) { Navigator.of(context).pop(property); }
      else { context.go('/my-listings'); }
    });
  }

  Future<void> _preview() async {
    final validation = _validateCore();
    if (validation != null) {
      setState(() => _stepError = validation);
      return;
    }

    final submit = await AppBottomSheet.show<bool>(
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
                    child: SizedBox(height: 210, width: double.infinity,
                      child: AdaptivePropertyPhoto(url: _existing!.mainImage!, authenticated: _existing!.status != 'published')),
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
                  for (final condition in _rentalConditions) Text(rentalConditionSummary(condition)),
                ],
                const SizedBox(height: AppSpacing.s20),
                if (_validateForSubmit() == null) ...[
                  AppButton(key: const ValueKey('listing-preview-submit'), label: 'إرسال للمراجعة',
                    onPressed: () => Navigator.pop(sheetContext, true), expand: true),
                  const SizedBox(height: 8),
                ],
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
    if (mounted && submit == true) await _persist(submit: true);
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
          _saiAmountType = management.configured ? management.amountType : 'fixed';
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
              AppSelectField<String>(
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
      if (!mounted || !_sessionValid) { await _mediaPicker.clearTemporaryFiles(picked);return; }
      if (picked.isEmpty) return;
      final valid=await _validImagePaths(picked);
      final available = (12 - _photoKeys.length).clamp(0, 12);
      final accepted = valid.take(available).toList(growable: false);
      final discarded = valid.where((path) => !accepted.contains(path));
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
    _photoCancels[key]?.cancel('Image removed');
    final paths = _localPhotoKeys.entries.where((e)=>e.value==key).map((e)=>e.key).toList();
    setState(() { _removedPhotoKeys.add(key); _photoOrder.remove(key); _imagePaths.removeWhere(paths.contains); });
    await _saveRecovery();
    try { await _mediaPicker.clearTemporaryFiles(paths); } catch (_) {}
  }

  Future<List<String>> _validImagePaths(List<String> paths) async {
    final accepted=<String>[], rejected=<String>[];
    for (final path in paths) {
      final ext=path.split('.').last.toLowerCase();
      try {
        if (!const ['jpg','jpeg','png','webp'].contains(ext) || await File(path).length()>8*1024*1024) { rejected.add(path); }
        else { accepted.add(path); }
      } catch (_) { rejected.add(path); }
    }
    if (rejected.isNotEmpty) {
      await _mediaPicker.clearTemporaryFiles(rejected);
      if (mounted) { _message('بعض الصور غير مدعومة أو كبيرة. اختر JPG أو PNG أو WebP حتى 8 ميجابايت للصورة.'); }
    }
    return accepted;
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

  bool _locationRequestCurrent(int? actor, int epoch) => mounted && _sessionValid &&
    Stage6SecureSessionStore.instance.sessionEpoch == epoch &&
    actor == ref.read(authControllerProvider).asData?.value?.id;

  Future<void> _selectOnMap() => _selectLocation();
  Future<void> _selectLocation({bool useCurrent = false}) async {
    if (_busy || _selectingLocation || _resolvingLocation || !_sessionValid) return;
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    setState(() {
      _selectingLocation = true; _locationError = null;
      _locationNeedsSettings = false; _locationServiceDisabled = false;
    });
    try {
      // The explicit current-location action now accepts the real GPS fix in
      // one step. Manual map selection keeps its own explicit confirmation.
      final PropertyLocationSelection? selection;
      if (useCurrent) {
        selection = await ref.read(propertyCurrentLocationProvider)();
      } else {
        selection = await ref.read(propertyLocationPickerProvider)(context,
          initialLatitude: _latitude, initialLongitude: _longitude);
      }
      final point = selection;
      if (!_locationRequestCurrent(actor, epoch) || point == null) return;
      if (!hasValidPropertyCoordinates(point.latitude, point.longitude)) {
        throw StateError('Invalid property point');
      }
      setState(() {
        if (_latitude != point.latitude || _longitude != point.longitude) _landBoundaryGeoJson = null;
        final city = point.address.governorate;
        if (city != null && _normalizedName(city) != _normalizedName(_governorate.text)) {
          _district.text = point.address.district ?? ''; _street.text = point.address.street ?? '';
        }
        _latitude = point.latitude; _longitude = point.longitude; _stepError = null;
        _showLocationPreview = true;
      });
      await _fillAddress(point.address, point.latitude, point.longitude, resolveMissing: useCurrent);
      if (_locationRequestCurrent(actor, epoch)) { unawaited(_saveRecovery()); }
    } on PlatformException catch (error) {
      if (_locationRequestCurrent(actor, epoch)) { setState(() {
        _locationNeedsSettings = error.code == 'LOCATION_DENIED_FOREVER';
        _locationServiceDisabled = error.code == 'LOCATION_DISABLED';
        _locationError = error.message ?? 'تعذر تحديد الموقع الحالي. اختر النقطة على الخريطة.';
      }); }
    } catch (_) {
      if (_locationRequestCurrent(actor, epoch)) setState(() => _locationError = 'تعذّر تحديد الموقع الحالي. اختر النقطة على الخريطة.');
    } finally { if (mounted) setState(() => _selectingLocation = false); }
  }

  Future<void> _fillAddress(
    PropertyLocationAddress initial,
    double latitude,
    double longitude, {bool resolveMissing = true}
  ) async {
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final before = [_governorate.text, _district.text, _street.text];
    setState(() => _resolvingLocation = true);
    try {
      var address = initial;
      if (resolveMissing && !address.isComplete) {
        final resolved = await ref
            .read(propertyRepositoryProvider)
            .resolveLocationAddress(latitude: latitude, longitude: longitude)
            .timeout(const Duration(seconds: 4));
        address = address.mergeFallback(resolved);
      }
      if (!_locationRequestCurrent(actor, epoch) || _latitude != latitude || _longitude != longitude) return;
      setState(() {
        if (address.governorate != null && _governorate.text == before[0]) {
          _governorate.text = address.governorate!;
        }
        if (address.district != null && _district.text == before[1]) _district.text = address.district!;
        if (address.street != null && _street.text == before[2]) _street.text = address.street!;
      });
    } catch (_) {
      if (_locationRequestCurrent(actor, epoch)) {
        setState(() => _locationError = 'تم تثبيت الموقع. تعذّر جلب العنوان تلقائيًا؛ أكمله يدويًا.');
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
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
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
    required this.onPreview, required this.onSaveDraft, required this.onSubmit, this.primaryLabel = 'إرسال للمراجعة'});
  final bool busy;
  final String primaryLabel;
  final VoidCallback onPrevious, onPreview, onSaveDraft, onSubmit;
  @override
  Widget build(BuildContext context) => Material(color: Theme.of(context).colorScheme.surface,
    elevation: AppElevation.floating, child: SafeArea(top: false, child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 10, 18, 12),
      child: Row(children: [
        Expanded(child: EbrokerStepButton(label: 'السابق', style: AppButtonStyle.outlined,
          onPressed: busy ? null : onPrevious, expand: true)),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: EbrokerStepButton(label: primaryLabel, icon: primaryLabel == 'إرسال للمراجعة' ? Icons.send_outlined : Icons.visibility_outlined,
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
