from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def patch(path, old, new, count=1):
    p = ROOT / path
    text = p.read_text()
    actual = text.count(old)
    if actual < count:
        raise SystemExit(f"pattern missing in {path}: expected >= {count}, got {actual}: {old[:140]!r}")
    p.write_text(text.replace(old, new, count))

# Domain payload/details.
path = 'mobile_app/lib/features/properties/domain/property_details.dart'
patch(path, "class PropertyImageItem {\n", "import 'dart:convert';\n\nclass PropertyImageItem {\n")
patch(path,
      "    this.address,\n    this.status = 'published',\n",
      "    this.address,\n    this.buildingReference,\n    this.unitNumber,\n    this.floorNumber,\n    this.landBoundaryGeoJson,\n    this.duplicateCheckStatus,\n    this.duplicateCheckScore = 0,\n    this.status = 'published',\n")
patch(path,
      "  final String? address;\n  final double latitude;\n",
      "  final String? address;\n  final String? buildingReference;\n  final String? unitNumber;\n  final String? floorNumber;\n  final Map<String, dynamic>? landBoundaryGeoJson;\n  final String? duplicateCheckStatus;\n  final int duplicateCheckScore;\n  final double latitude;\n")
patch(path,
      "      address: _nullableString(json['address']),\n      latitude: _asDouble(json['latitude']) ?? 0,\n",
      "      address: _nullableString(json['address']),\n      buildingReference: _nullableString(json['building_reference']),\n      unitNumber: _nullableString(json['unit_number']),\n      floorNumber: _nullableString(json['floor_number']),\n      landBoundaryGeoJson: json['land_boundary_geojson'] is Map<String, dynamic>\n          ? Map<String, dynamic>.from(json['land_boundary_geojson'] as Map<String, dynamic>)\n          : null,\n      duplicateCheckStatus: _nullableString(json['duplicate_check_status']),\n      duplicateCheckScore: _asInt(json['duplicate_check_score']) ?? 0,\n      latitude: _asDouble(json['latitude']) ?? 0,\n")
patch(path,
      "    this.address,\n    this.contactPhone,\n",
      "    this.address,\n    this.buildingReference,\n    this.unitNumber,\n    this.floorNumber,\n    this.landBoundaryGeoJson,\n    this.contactPhone,\n")
patch(path,
      "  final String? address;\n  final double latitude;\n  final double longitude;\n  final String? contactPhone;\n",
      "  final String? address;\n  final String? buildingReference;\n  final String? unitNumber;\n  final String? floorNumber;\n  final Map<String, dynamic>? landBoundaryGeoJson;\n  final double latitude;\n  final double longitude;\n  final String? contactPhone;\n", 1)
patch(path,
      "      'listing_input_version': 2,\n",
      "      'listing_input_version': 3,\n")
patch(path,
      "      if (address != null && address!.trim().isNotEmpty)\n        'address': address!.trim(),\n      'latitude': latitude,\n",
      "      if (address != null && address!.trim().isNotEmpty)\n        'address': address!.trim(),\n      if (buildingReference != null && buildingReference!.trim().isNotEmpty)\n        'building_reference': buildingReference!.trim(),\n      if (unitNumber != null && unitNumber!.trim().isNotEmpty)\n        'unit_number': unitNumber!.trim(),\n      if (floorNumber != null && floorNumber!.trim().isNotEmpty)\n        'floor_number': floorNumber!.trim(),\n      if (landBoundaryGeoJson != null)\n        'land_boundary_geojson': jsonEncode(landBoundaryGeoJson),\n      'latitude': latitude,\n")

# Repository identity endpoints.
path = 'mobile_app/lib/features/properties/data/property_repository.dart'
patch(path,
      "import '../domain/property_details.dart';\n",
      "import '../domain/property_details.dart';\nimport '../domain/property_identity.dart';\n")
patch(path,
      "  Future<PropertyDetails> submitListing(int propertyId) async {\n",
      "  Future<PropertyIdentityResult> checkPropertyIdentity(int propertyId) async {\n"
      "    final response = await _dio.post<Map<String, dynamic>>(\n"
      "      '/properties/$propertyId/identity/check',\n"
      "      options: await _auth.requiredAuthOptions(),\n"
      "    );\n"
      "    final data = response.data?['data'];\n"
      "    if (data is! Map<String, dynamic>) {\n"
      "      throw StateError('Invalid property identity response.');\n"
      "    }\n"
      "    return PropertyIdentityResult.fromJson(data);\n"
      "  }\n\n"
      "  Future<PropertyIdentityResult> selfVerifyPropertyIdentity(\n"
      "    int propertyId, {\n"
      "    required String differenceType,\n"
      "    required String differenceNote,\n"
      "  }) async {\n"
      "    final response = await _dio.post<Map<String, dynamic>>(\n"
      "      '/properties/$propertyId/identity/self-verify',\n"
      "      data: <String, dynamic>{\n"
      "        'assert_different': true,\n"
      "        'difference_type': differenceType,\n"
      "        'difference_note': differenceNote.trim(),\n"
      "      },\n"
      "      options: await _auth.requiredAuthOptions(),\n"
      "    );\n"
      "    final data = response.data?['data'];\n"
      "    if (data is! Map<String, dynamic>) {\n"
      "      throw StateError('Invalid property identity response.');\n"
      "    }\n"
      "    return PropertyIdentityResult.fromJson(data);\n"
      "  }\n\n"
      "  Future<PropertyDetails> submitListing(int propertyId) async {\n")

# Listing editor.
path = 'mobile_app/lib/features/properties/presentation/listing_editor_screen.dart'
patch(path,
      "import 'property_location_picker_screen.dart';\n",
      "import 'property_land_boundary_picker_screen.dart';\nimport 'property_location_picker_screen.dart';\n")
patch(path,
      "  final _street = TextEditingController();\n  final _phone = TextEditingController();\n",
      "  final _street = TextEditingController();\n  final _buildingReference = TextEditingController();\n  final _unitNumber = TextEditingController();\n  final _floorNumber = TextEditingController();\n  final _phone = TextEditingController();\n")
patch(path,
      "  double? _latitude;\n  double? _longitude;\n",
      "  double? _latitude;\n  double? _longitude;\n  Map<String, dynamic>? _landBoundaryGeoJson;\n")
patch(path,
      "  bool get _requiresStructure => _structureTypes.contains(_type);\n",
      "  bool get _requiresStructure => _structureTypes.contains(_type);\n  bool get _isUnitType => const {'apartment', 'office', 'shop'}.contains(_type);\n  bool get _unitNeedsFloor => const {'apartment', 'office'}.contains(_type);\n")
patch(path,
      "    _latitude = property.latitude;\n    _longitude = property.longitude;\n",
      "    _latitude = property.latitude;\n    _longitude = property.longitude;\n    _buildingReference.text = property.buildingReference ?? '';\n    _unitNumber.text = property.unitNumber ?? '';\n    _floorNumber.text = property.floorNumber ?? '';\n    _landBoundaryGeoJson = property.landBoundaryGeoJson;\n")
patch(path,
      "      _street,\n      _phone,\n",
      "      _street,\n      _buildingReference,\n      _unitNumber,\n      _floorNumber,\n      _phone,\n")
patch(path,
      "                            if (!_requiresStructure) {\n                              _parkingChoice = null;\n                              _facade = null;\n                            }\n",
      "                            if (!_requiresStructure) {\n                              _parkingChoice = null;\n                              _facade = null;\n                            }\n                            if (!_isUnitType) {\n                              _buildingReference.clear();\n                              _unitNumber.clear();\n                              _floorNumber.clear();\n                            }\n                            if (_type != 'land') _landBoundaryGeoJson = null;\n")
patch(path,
      "        AppTextField(\n          controller: _street,\n          label: 'الشارع',\n          enabled: !_busy && hasLocation,\n        ),\n",
      "        AppTextField(\n          controller: _street,\n          label: 'الشارع',\n          enabled: !_busy && hasLocation,\n        ),\n"
      "        if (_type == 'land' && hasLocation) ...[\n"
      "          const SizedBox(height: AppSpacing.s16),\n"
      "          AppInlineMessage(\n"
      "            title: _landBoundaryGeoJson == null ? 'حدود الأرض غير محددة' : 'تم تحديد حدود الأرض',\n"
      "            message: _landBoundaryGeoJson == null\n"
      "                ? 'ارسم زوايا الأرض حتى لا يعتمد منع التكرار على الدبوس فقط.'\n"
      "                : 'سيستخدم النظام حدود القطعة والمساحة معاً لمنع تكرارها.',\n"
      "            tone: _landBoundaryGeoJson == null ? AppStatusTone.warning : AppStatusTone.success,\n"
      "          ),\n"
      "          const SizedBox(height: AppSpacing.s8),\n"
      "          AppButton(\n"
      "            label: _landBoundaryGeoJson == null ? 'رسم حدود الأرض' : 'تعديل حدود الأرض',\n"
      "            icon: Icons.polyline_outlined,\n"
      "            style: AppButtonStyle.tonal,\n"
      "            onPressed: _busy ? null : _pickLandBoundary,\n"
      "            expand: true,\n"
      "          ),\n"
      "        ],\n")
patch(path,
      "        const SizedBox(height: AppSpacing.s16),\n        Row(\n",
      "        if (_isUnitType) ...[\n"
      "          const SizedBox(height: AppSpacing.s16),\n"
      "          AppInlineMessage(\n"
      "            title: 'هوية الوحدة داخل المبنى',\n"
      "            message: 'يمكن نشر وحدات مختلفة في نفس العمارة، لكن لا يمكن نشر نفس الوحدة مرتين.',\n"
      "            tone: AppStatusTone.info,\n"
      "          ),\n"
      "          const SizedBox(height: AppSpacing.s12),\n"
      "          AppTextField(\n"
      "            controller: _buildingReference,\n"
      "            label: 'اسم أو رقم المبنى *',\n"
      "            hint: 'مثال: عمارة النور 12',\n"
      "            enabled: !_busy,\n"
      "          ),\n"
      "          const SizedBox(height: AppSpacing.s12),\n"
      "          Row(children: [\n"
      "            Expanded(child: AppTextField(controller: _unitNumber, label: 'رقم الوحدة *', enabled: !_busy)),\n"
      "            const SizedBox(width: AppSpacing.s8),\n"
      "            Expanded(child: AppTextField(controller: _floorNumber, label: _unitNeedsFloor ? 'الدور *' : 'الدور', enabled: !_busy)),\n"
      "          ]),\n"
      "        ],\n"
      "        const SizedBox(height: AppSpacing.s16),\n        Row(\n", 1)
patch(path,
      "      if (_governorate.text.trim().length < 2) return 'أكمل اسم المحافظة.';\n      if (_composedAddress.length < 3) return 'أكمل معلومات عنوان العقار.';\n",
      "      if (_governorate.text.trim().length < 2) return 'أكمل اسم المحافظة.';\n      if (_composedAddress.length < 3) return 'أكمل معلومات عنوان العقار.';\n"
      "      if (_type == 'land' && _landBoundaryGeoJson == null) {\n"
      "        return 'ارسم حدود الأرض حتى نتحقق من هوية القطعة ولا نعتمد على الدبوس وحده.';\n"
      "      }\n")
patch(path,
      "      if (_requiresResidential) {\n",
      "      if (_isUnitType) {\n"
      "        if (_buildingReference.text.trim().isEmpty) return 'أدخل اسم أو رقم المبنى.';\n"
      "        if (_unitNumber.text.trim().isEmpty) return 'أدخل رقم الوحدة.';\n"
      "        if (_unitNeedsFloor && _floorNumber.text.trim().isEmpty) return 'أدخل رقم الدور.';\n"
      "      }\n"
      "      if (_requiresResidential) {\n")
patch(path,
      "      address: _composedAddress,\n      latitude: _latitude!,\n",
      "      address: _composedAddress,\n"
      "      buildingReference: _isUnitType ? _buildingReference.text.trim() : null,\n"
      "      unitNumber: _isUnitType ? _unitNumber.text.trim() : null,\n"
      "      floorNumber: _isUnitType && _floorNumber.text.trim().isNotEmpty ? _floorNumber.text.trim() : null,\n"
      "      landBoundaryGeoJson: _type == 'land' ? _landBoundaryGeoJson : null,\n"
      "      latitude: _latitude!,\n")
patch(path,
      "          draft = await repository.submitListing(draft.id);\n",
      "          final identityReady = await _checkIdentityBeforeSubmit(draft.id);\n"
      "          if (!identityReady) return;\n"
      "          draft = await repository.submitListing(draft.id);\n")
patch(path,
      "  Future<void> _configureSai() async {\n",
      "  Future<bool> _checkIdentityBeforeSubmit(int propertyId) async {\n"
      "    final repository = ref.read(propertyRepositoryProvider);\n"
      "    final result = await repository.checkPropertyIdentity(propertyId);\n"
      "    if (result.isDistinct) return true;\n"
      "    if (result.isConfirmedDuplicate) {\n"
      "      _message('هذا العقار أو هذه الوحدة مسجلة بالفعل على المنصة ولا يمكن إنشاء إعلان آخر لها.');\n"
      "      return false;\n"
      "    }\n"
      "    final answer = await _duplicateSelfVerificationDialog();\n"
      "    if (answer == null || !mounted) return false;\n"
      "    final verified = await repository.selfVerifyPropertyIdentity(\n"
      "      propertyId, differenceType: answer.$1, differenceNote: answer.$2,\n"
      "    );\n"
      "    if (verified.isConfirmedDuplicate) {\n"
      "      _message('بعد التحقق ما زال هذا العقار مطابقاً لعقار مسجل، لذلك لا يمكن إرساله.');\n"
      "      return false;\n"
      "    }\n"
      "    if (verified.needsSupport) {\n"
      "      _message('تم تسجيل توضيحك. بقي تشابه غير محسوم وسيشاهده موظف الدعم كمقارنة جاهزة فقط.');\n"
      "    }\n"
      "    return true;\n"
      "  }\n\n"
      "  Future<(String, String)?> _duplicateSelfVerificationDialog() async {\n"
      "    final note = TextEditingController();\n"
      "    var type = 'different_address';\n"
      "    String? error;\n"
      "    final result = await showDialog<(String, String)>(\n"
      "      context: context,\n"
      "      barrierDismissible: false,\n"
      "      builder: (dialogContext) => StatefulBuilder(\n"
      "        builder: (context, setDialogState) => Directionality(\n"
      "          textDirection: TextDirection.rtl,\n"
      "          child: AlertDialog(\n"
      "            title: const Text('وجدنا عقاراً مشابهاً'),\n"
      "            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [\n"
      "              const Text('إذا كان هذا عقاراً مختلفاً، اختر الفرق واكتب معلومة تساعد النظام على التمييز. الحالات غير المحسومة فقط تذهب للدعم.'),\n"
      "              const SizedBox(height: 12),\n"
      "              DropdownButtonFormField<String>(\n"
      "                value: type,\n"
      "                decoration: const InputDecoration(labelText: 'ما الفرق الأساسي؟'),\n"
      "                items: const [\n"
      "                  DropdownMenuItem(value: 'different_building', child: Text('مبنى مختلف')),\n"
      "                  DropdownMenuItem(value: 'different_unit', child: Text('وحدة مختلفة')),\n"
      "                  DropdownMenuItem(value: 'different_area', child: Text('مساحة مختلفة')),\n"
      "                  DropdownMenuItem(value: 'different_boundary', child: Text('حدود أرض مختلفة')),\n"
      "                  DropdownMenuItem(value: 'different_address', child: Text('عنوان/رقم عقار مختلف')),\n"
      "                  DropdownMenuItem(value: 'other', child: Text('فرق آخر')),\n"
      "                ],\n"
      "                onChanged: (value) => setDialogState(() => type = value ?? type),\n"
      "              ),\n"
      "              const SizedBox(height: 12),\n"
      "              TextField(controller: note, maxLines: 3, decoration: InputDecoration(labelText: 'وضح الفرق *', errorText: error)),\n"
      "            ])),\n"
      "            actions: [\n"
      "              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('رجوع')),\n"
      "              FilledButton(onPressed: () {\n"
      "                final text = note.text.trim();\n"
      "                if (text.length < 10) { setDialogState(() => error = 'اكتب توضيحاً من 10 أحرف على الأقل.'); return; }\n"
      "                Navigator.pop(dialogContext, (type, text));\n"
      "              }, child: const Text('أؤكد أنه عقار مختلف')),\n"
      "            ],\n"
      "          ),\n"
      "        ),\n"
      "      ),\n"
      "    );\n"
      "    note.dispose();\n"
      "    return result;\n"
      "  }\n\n"
      "  Future<void> _pickLandBoundary() async {\n"
      "    final latitude = _latitude; final longitude = _longitude;\n"
      "    if (latitude == null || longitude == null) { _message('حدد موقع الأرض أولاً.'); return; }\n"
      "    final selection = await Navigator.of(context).push<PropertyLandBoundarySelection>(\n"
      "      MaterialPageRoute(builder: (_) => PropertyLandBoundaryPickerScreen(\n"
      "        initialLatitude: latitude, initialLongitude: longitude, initialBoundary: _landBoundaryGeoJson,\n"
      "      )),\n"
      "    );\n"
      "    if (selection != null && mounted) setState(() => _landBoundaryGeoJson = selection.geoJson);\n"
      "  }\n\n"
      "  Future<void> _configureSai() async {\n")

print('Property Identity V2 Flutter integration applied')
