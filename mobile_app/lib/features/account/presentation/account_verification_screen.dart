import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../properties/presentation/property_location_picker_screen.dart';
import '../data/account_verification_repository.dart';
import '../data/auth_controller.dart';
import '../domain/account_verification.dart';
import '../domain/yemen_admin_divisions.dart';

class AccountVerificationScreen extends ConsumerStatefulWidget {
  const AccountVerificationScreen({super.key});

  @override
  ConsumerState<AccountVerificationScreen> createState() =>
      _AccountVerificationScreenState();
}

class _AccountVerificationScreenState
    extends ConsumerState<AccountVerificationScreen> {
  final _picker = const Stage5MediaPicker();
  final _governorate = TextEditingController();
  final _district = TextEditingController();
  final _workAreas = TextEditingController();
  final _specialties = TextEditingController();
  final _officeName = TextEditingController();
  final _commercialRegisterNumber = TextEditingController();
  final _neighborhood = TextEditingController();
  final _street = TextEditingController();
  final _landmark = TextEditingController();
  final _officePhone = TextEditingController();
  final Map<String, String> _files = <String, String>{};

  late Future<AccountVerificationApplication> _future;
  AccountVerificationApplication? _application;
  String _type = 'owner';
  double? _latitude;
  double? _longitude;
  bool _initialized = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _governorate,
      _district,
      _workAreas,
      _specialties,
      _officeName,
      _commercialRegisterNumber,
      _neighborhood,
      _street,
      _landmark,
      _officePhone,
    ]) {
      controller.dispose();
    }
    _picker.clearTemporaryFiles(_files.values).catchError((_) {});
    super.dispose();
  }

  Future<AccountVerificationApplication> _load() async {
    final application =
        await ref.read(accountVerificationRepositoryProvider).status();
    if (!_initialized) {
      _applyApplication(application);
      _initialized = true;
    }
    _application = application;
    return application;
  }

  void _applyApplication(AccountVerificationApplication application) {
    _type = application.type ?? 'owner';
    final storedGovernorate = application.detailText('governorate') ?? '';
    _governorate.text =
        YemenAdminDivisions.canonicalGovernorate(storedGovernorate);
    _district.text = application.detailText('district') ?? '';
    _workAreas.text = application.detailStrings('work_areas').join('، ');
    _specialties.text = application.detailStrings('specialties').join('، ');
    _officeName.text = application.detailText('office_name') ?? '';
    _commercialRegisterNumber.text =
        application.detailText('commercial_register_number') ?? '';
    _neighborhood.text = application.detailText('neighborhood') ?? '';
    _street.text = application.detailText('street') ?? '';
    _landmark.text = application.detailText('landmark') ?? '';
    _officePhone.text = application.detailText('office_phone') ?? '';
    _latitude = application.detailDouble('latitude');
    _longitude = application.detailDouble('longitude');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('نوع الحساب والتحقق'),
          actions: [
            IconButton(
              tooltip: 'تحديث الحالة',
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: user == null
            ? const Center(child: Text('سجّل الدخول أولاً.'))
            : user.canAccessSupportWorkspace || user.canAccessSystemWorkspace
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'صفحة نوع الحساب والتحقق مخصصة لحسابات المستخدمين العاديين فقط.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : FutureBuilder<AccountVerificationApplication>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      _application == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError && _application == null) {
                    return Center(
                      child: FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    );
                  }
                  final application = snapshot.data ?? _application!;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      _StatusCard(application: application),
                      const SizedBox(height: 16),
                      Text(
                        'نوع الحساب',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'الحساب الأساسي يبقى للبحث والتصفح والشراء. اختر صفة موثقة فقط إذا أردت النشر بهذه الصفة.',
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'owner',
                            icon: Icon(Icons.home_work_outlined),
                            label: Text('مالك'),
                          ),
                          ButtonSegment(
                            value: 'broker',
                            icon: Icon(Icons.real_estate_agent_outlined),
                            label: Text('دلال'),
                          ),
                          ButtonSegment(
                            value: 'office',
                            icon: Icon(Icons.apartment_outlined),
                            label: Text('مكتب عقارات'),
                          ),
                        ],
                        selected: <String>{_type},
                        onSelectionChanged: _formLocked
                            ? null
                            : (value) => setState(() => _type = value.first),
                      ),
                      const SizedBox(height: 18),
                      _governorateDropdown(),
                      _districtDropdown(),
                      if (_type == 'broker') ..._brokerFields(),
                      if (_type == 'office') ..._officeFields(),
                      const SizedBox(height: 8),
                      Text(
                        'المستندات',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      ..._documentTiles(application),
                      if (_type == 'owner') ...[
                        const SizedBox(height: 8),
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'هوية المالك تُراجع مرة واحدة هنا. عند نشر كل عقار سيُطلب مستند العلاقة بذلك العقار بشكل مستقل، مثل بصيرة شراء أو سجل عقاري أو فصل قسمة أو إرث أو حكم قضائي أو عقد تمليك.',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _formLocked ? null : _submit,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : application.approved
                                ? const Icon(Icons.verified_outlined)
                                : application.status == 'pending'
                                    ? const Icon(Icons.hourglass_top_outlined)
                                    : const Icon(Icons.verified_user_outlined),
                        label: Text(
                          application.approved
                              ? 'تم التحقق'
                              : application.status == 'pending'
                                  ? 'تم إرسال الطلب - قيد المراجعة'
                                  : application.hasApplication
                                      ? 'إعادة إرسال طلب التحقق'
                                      : 'إرسال طلب التحقق للمراجعة',
                        ),
                      ),
                      if (application.approved) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'هذا النوع موثق حاليًا. تغيير نوع الحساب يتطلب مراجعة جديدة، لذلك لا يتم تغييره من هذه الشاشة أثناء حالة الاعتماد.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
    );
  }

  bool get _formLocked {
    final application = _application;
    return _busy ||
        application?.status == 'pending' ||
        application?.approved == true;
  }

  Widget _governorateDropdown() {
    final current = YemenAdminDivisions.canonicalGovernorate(_governorate.text);
    final values = YemenAdminDivisions.governorates.toList(growable: true);
    if (current.isNotEmpty && !values.contains(current)) values.add(current);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'المحافظة التي تقيم فيها',
          prefixIcon: Icon(Icons.map_outlined),
          border: OutlineInputBorder(),
        ),
        items: values
            .map((value) => DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                ))
            .toList(growable: false),
        onChanged: _formLocked
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  _governorate.text = value;
                  _district.clear();
                });
              },
      ),
    );
  }

  Widget _districtDropdown() {
    final governorate =
        YemenAdminDivisions.canonicalGovernorate(_governorate.text);
    final values =
        YemenAdminDivisions.districtsFor(governorate).toList(growable: true);
    final current = _district.text.trim();
    if (current.isNotEmpty && !values.contains(current)) values.add(current);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'المديرية التي تقيم فيها',
          prefixIcon: Icon(Icons.location_city_outlined),
          border: OutlineInputBorder(),
        ),
        items: values
            .map((value) => DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                ))
            .toList(growable: false),
        onChanged: _formLocked || governorate.isEmpty
            ? null
            : (value) {
                if (value == null) return;
                setState(() => _district.text = value);
              },
      ),
    );
  }

  List<Widget> _brokerFields() => [
        _textField(
          _workAreas,
          'المناطق التي تعمل فيها',
          hint: 'مثال: صنعاء، حدة، شملان، عمران',
          icon: Icons.location_on_outlined,
          maxLines: 2,
        ),
        _textField(
          _specialties,
          'التخصصات (اختياري)',
          hint: 'مثال: أراضٍ، منازل، شقق، محلات',
          icon: Icons.category_outlined,
          maxLines: 2,
        ),
      ];

  List<Widget> _officeFields() => [
        _textField(
          _officeName,
          'اسم المكتب العقاري الرسمي',
          icon: Icons.business_outlined,
        ),
        _textField(
          _commercialRegisterNumber,
          'رقم السجل التجاري',
          icon: Icons.numbers_outlined,
        ),
        _textField(
          _neighborhood,
          'الحي',
          icon: Icons.holiday_village_outlined,
        ),
        _textField(
          _street,
          'الشارع',
          icon: Icons.add_road_outlined,
        ),
        _textField(
          _landmark,
          'أقرب معلم',
          icon: Icons.place_outlined,
        ),
        _textField(
          _officePhone,
          'رقم هاتف المكتب',
          hint: '+967...',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        Card(
          child: ListTile(
            leading: Icon(
              _latitude == null ? Icons.add_location_alt_outlined : Icons.check_circle,
            ),
            title: const Text(
              'موقع المكتب',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(_latitude == null
                ? 'اضغط لاختيار تحديد موقعك الحالي أو الموقع على الخريطة'
                : 'تم تسجيل الموقع (${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)})'),
            trailing: const Icon(Icons.chevron_left),
            onTap: _formLocked ? null : _chooseOfficeLocation,
          ),
        ),
        const SizedBox(height: 8),
      ];

  List<Widget> _documentTiles(AccountVerificationApplication application) {
    final specs = switch (_type) {
      'owner' => const <(String, String, bool)>[
          ('identity_document', 'صورة البطاقة الشخصية أو جواز السفر', true),
          ('identity_back', 'الوجه الخلفي للهوية إن وجد', false),
          ('selfie', 'صورة حية / سيلفي', true),
        ],
      'broker' => const <(String, String, bool)>[
          ('identity_document', 'صورة البطاقة الشخصية أو جواز السفر', true),
          ('identity_back', 'الوجه الخلفي للهوية إن وجد', false),
          ('selfie', 'صورة حية / سيلفي', true),
          ('professional_license', 'رخصة دلالة أو مستند مهني (اختياري)', false),
        ],
      _ => const <(String, String, bool)>[
          ('responsible_identity', 'هوية صاحب / مسؤول المكتب', true),
          ('identity_back', 'الوجه الخلفي للهوية إن وجد', false),
          ('selfie', 'صورة حية / سيلفي لصاحب الحساب', true),
          ('commercial_register', 'صورة السجل التجاري', true),
          ('office_license', 'صورة ترخيص المكتب العقاري', true),
          ('office_frontage', 'صورة واجهة المكتب', true),
          ('office_logo', 'شعار المكتب (اختياري)', false),
        ],
    };
    return specs
        .map((spec) => _DocumentTile(
              label: spec.$2,
              requiredDocument: spec.$3,
              selected: _files.containsKey(spec.$1),
              alreadyStored:
                  application.type == _type && application.hasDocument(spec.$1),
              cameraOnly: spec.$1 == 'selfie',
              onTap: _formLocked ? null : () => _pickDocument(spec.$1),
            ))
        .toList(growable: false);
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    IconData? icon,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        enabled: !_formLocked,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _pickDocument(String kind) async {
    try {
      String? selected;
      if (kind == 'selfie') {
        selected = await _picker.takePhoto();
      } else {
        final source = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('فتح الكاميرا'),
                  onTap: () => Navigator.of(sheetContext).pop('camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('اختيار من الملفات'),
                  onTap: () => Navigator.of(sheetContext).pop('files'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || source == null) return;
        if (source == 'camera') {
          selected = await _picker.takePhoto();
        } else {
          final paths = await _picker.pickImages();
          if (paths.isEmpty) return;
          selected = paths.first;
          await _picker.clearTemporaryFiles(paths.skip(1));
        }
      }
      if (!mounted || selected == null) return;
      final old = _files[kind];
      setState(() => _files[kind] = selected!);
      if (old != null && old != selected) {
        await _picker.clearTemporaryFiles([old]);
      }
    } on PlatformException {
      _message(kind == 'selfie'
          ? 'تعذر فتح الكاميرا لالتقاط السيلفي.'
          : 'تعذر فتح الكاميرا أو اختيار المستند من الملفات.');
    } catch (_) {
      _message(kind == 'selfie'
          ? 'تعذر التقاط صورة السيلفي.'
          : 'تعذر اختيار المستند.');
    }
  }

  Future<void> _chooseOfficeLocation() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('تحديد موقعي الحالي'),
              subtitle: const Text('استخدام GPS لتسجيل موقع المكتب الحالي'),
              onTap: () => Navigator.of(sheetContext).pop('current'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('موقع المكتب على الخريطة'),
              subtitle: const Text('تحريك المؤشر واختيار موقع المكتب يدويًا'),
              onTap: () => Navigator.of(sheetContext).pop('map'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'current') {
      await _useCurrentOfficeLocation();
    } else {
      await _pickOfficeLocationOnMap();
    }
  }

  Future<void> _useCurrentOfficeLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _message('فعّل خدمة الموقع في الهاتف ثم حاول مرة أخرى.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _message('لا يمكن تحديد الموقع الحالي بدون إذن الموقع.');
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
      _message('تم تحديد موقع المكتب الحالي بنجاح.');
    } catch (_) {
      _message('تعذر تحديد موقعك الحالي. جرّب تحديد الموقع على الخريطة.');
    }
  }

  Future<void> _pickOfficeLocationOnMap() async {
    final result = await Navigator.of(context).push<PropertyLocationSelection>(
      MaterialPageRoute(
        builder: (_) => PropertyLocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          title: 'تحديد موقع المكتب',
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
    });
  }

  Future<void> _submit() async {
    final application = _application;
    final error = _validate(application);
    if (error != null) {
      _message(error);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(accountVerificationRepositoryProvider).submit(
            type: _type,
            governorate: _governorate.text,
            district: _district.text,
            files: Map<String, String>.from(_files),
            workAreas: _splitList(_workAreas.text),
            specialties: _splitList(_specialties.text),
            officeName: _type == 'office' ? _officeName.text : null,
            commercialRegisterNumber:
                _type == 'office' ? _commercialRegisterNumber.text : null,
            neighborhood: _type == 'office' ? _neighborhood.text : null,
            street: _type == 'office' ? _street.text : null,
            landmark: _type == 'office' ? _landmark.text : null,
            latitude: _type == 'office' ? _latitude : null,
            longitude: _type == 'office' ? _longitude : null,
            officePhone: _type == 'office' ? _officePhone.text : null,
          );
      if (!mounted) return;
      await ref.read(authControllerProvider.notifier).refresh();
      final uploaded = _files.values.toList(growable: false);
      _files.clear();
      await _picker.clearTemporaryFiles(uploaded).catchError((_) {});
      if (!mounted) return;
      _application = result;
      setState(() => _future = Future.value(result));
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined, size: 44),
          title: const Text('تم استلام طلب التحقق بنجاح'),
          content: const Text(
            'بياناتك ومستنداتك الآن قيد المراجعة من فريق الدعم\n'
            'سنرسل لك إشعار فور اكتمال المراجعة أو إذا احتجنا إلى مستند إضافي.\n\n'
            'المدة المتوقعة، من عدة ساعات إلى 24 ساعة\n\n'
            'حالة الطلب: قيد المراجعة',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
    } catch (error) {
      _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validate(AccountVerificationApplication? application) {
    if (_governorate.text.trim().length < 2) return 'أدخل المحافظة.';
    if (_district.text.trim().length < 2) return 'أدخل المديرية.';
    bool available(String kind) =>
        _files.containsKey(kind) ||
        (application?.type == _type && application!.hasDocument(kind));
    final required = switch (_type) {
      'owner' => const ['identity_document', 'selfie'],
      'broker' => const ['identity_document', 'selfie'],
      _ => const [
          'responsible_identity',
          'selfie',
          'commercial_register',
          'office_license',
          'office_frontage',
        ],
    };
    if (required.any((kind) => !available(kind))) {
      return 'أكمل جميع المستندات المطلوبة قبل إرسال طلب التحقق.';
    }
    if (_type == 'broker' && _splitList(_workAreas.text).isEmpty) {
      return 'أدخل منطقة عمل واحدة على الأقل.';
    }
    if (_type == 'office') {
      if (_officeName.text.trim().length < 2 ||
          _commercialRegisterNumber.text.trim().length < 2 ||
          _neighborhood.text.trim().length < 2 ||
          _street.text.trim().length < 2 ||
          _landmark.text.trim().length < 2 ||
          _officePhone.text.trim().length < 7) {
        return 'أكمل بيانات المكتب والعنوان ورقم الهاتف.';
      }
      if (_latitude == null || _longitude == null) {
        return 'حدد موقع المكتب.';
      }
    }
    return null;
  }

  List<String> _splitList(String value) => value
      .split(RegExp(r'[,،\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  void _reload() {
    _initialized = false;
    setState(() => _future = _load());
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.application});
  final AccountVerificationApplication application;

  @override
  Widget build(BuildContext context) {
    final icon = switch (application.status) {
      'approved' => Icons.verified_outlined,
      'pending' => Icons.hourglass_top_outlined,
      'needs_more_info' => Icons.info_outline,
      'rejected' => Icons.cancel_outlined,
      _ => Icons.badge_outlined,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.typeLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'حالة الطلب: ${application.approved ? 'تم التحقق' : application.statusLabel}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (application.note != null) ...[
              const Divider(height: 24),
              Text('ملاحظة فريق الدعم: ${application.note}'),
            ],
            if (application.approved) ...[
              const Divider(height: 24),
              if (application.verificationFlags['identity_reviewed'] == true)
                const _VerifiedLine('الهوية تمت مراجعتها'),
              if (application.verificationFlags['professional_document_reviewed'] == true)
                const _VerifiedLine('الوثيقة المهنية تمت مراجعتها'),
              if (application.verificationFlags['commercial_register_reviewed'] == true)
                const _VerifiedLine('السجل التجاري تمت مراجعته'),
              if (application.verificationFlags['office_documents_reviewed'] == true)
                const _VerifiedLine('مستندات المكتب المهنية تمت مراجعتها'),
              if (application.verificationFlags['office_location_registered'] == true)
                const _VerifiedLine('موقع المكتب مسجل'),
            ],
          ],
        ),
      ),
    );
  }
}

class _VerifiedLine extends StatelessWidget {
  const _VerifiedLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.label,
    required this.requiredDocument,
    required this.selected,
    required this.alreadyStored,
    required this.cameraOnly,
    required this.onTap,
  });

  final String label;
  final bool requiredDocument;
  final bool selected;
  final bool alreadyStored;
  final bool cameraOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ready = selected || alreadyStored;
    return Card(
      child: ListTile(
        leading: Icon(
          ready ? Icons.check_circle_outline : Icons.add_photo_alternate_outlined,
        ),
        title: Text(
          requiredDocument ? '$label *' : label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          selected
              ? 'تم اختيار ملف جديد'
              : alreadyStored
                  ? 'مرفوع سابقًا ويمكن استبداله'
                  : cameraOnly
                      ? 'اضغط لالتقاط صورة مباشرة بالكاميرا'
                      : 'اضغط لاختيار فتح الكاميرا أو اختيار من الملفات',
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
