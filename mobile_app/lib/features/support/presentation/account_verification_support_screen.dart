import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/account_verification_support_repository.dart';

class AccountVerificationSupportScreen extends ConsumerStatefulWidget {
  const AccountVerificationSupportScreen({super.key, this.focusUserId});

  final int? focusUserId;

  @override
  ConsumerState<AccountVerificationSupportScreen> createState() =>
      _AccountVerificationSupportScreenState();
}

class _AccountVerificationSupportScreenState
    extends ConsumerState<AccountVerificationSupportScreen> {
  late Future<List<AccountVerificationSupportItem>> _future;
  int? _approvingUserId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AccountVerificationSupportItem>> _load() async {
    final rows = await ref
        .read(accountVerificationSupportRepositoryProvider)
        .pending();
    final focus = widget.focusUserId;
    if (focus == null) return rows;
    return rows.where((item) => item.userId == focus).toList(growable: false);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.focusUserId == null
              ? 'طلبات تحقق الحسابات'
              : 'تفاصيل طلب التحقق'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _approvingUserId == null ? _refresh : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<AccountVerificationSupportItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        friendlyApiError(snapshot.error!),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final rows = snapshot.data ?? const <AccountVerificationSupportItem>[];
            if (rows.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 140),
                    const Icon(Icons.fact_check_outlined, size: 56),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(widget.focusUserId == null
                          ? 'لا توجد طلبات تحقق معلقة حاليًا.'
                          : 'طلب التحقق غير موجود في قائمة المراجعة الحالية.'),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                itemCount: rows.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          widget.focusUserId == null
                              ? 'الوارد المشترك يعرض الطلبات غير المسندة. استلم المهمة من مركز الدعم قبل تنفيذ قرار عليها.'
                              : 'هذه المهمة مفتوحة من مساحة العمل. راجع البيانات والمستندات ثم نفذ الإجراء المسموح لك.',
                        ),
                      ),
                    );
                  }
                  final item = rows[index - 1];
                  final title = item.name.isEmpty
                      ? 'مستخدم #${item.userId}'
                      : item.name;
                  final location = <String>[
                    item.detailText('governorate'),
                    item.detailText('district'),
                  ].where((value) => value.isNotEmpty).join(' - ');
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.verified_user_outlined),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text([
                        item.typeLabel,
                        if (item.phone.isNotEmpty) item.phone,
                        if (location.isNotEmpty) location,
                      ].join('\n')),
                      isThreeLine: item.phone.isNotEmpty || location.isNotEmpty,
                      trailing: _approvingUserId == item.userId
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_left),
                      onTap: _approvingUserId == null
                          ? () => _showDetails(item)
                          : null,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showDetails(AccountVerificationSupportItem item) async {
    final documents = _documentsFor(item.type);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(item.name.isEmpty ? 'طلب تحقق #${item.userId}' : item.name),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InfoLine(label: 'نوع الحساب', value: item.typeLabel),
                  if (item.phone.isNotEmpty)
                    _InfoLine(label: 'الهاتف', value: item.phone),
                  _detail(item, 'المحافظة', 'governorate'),
                  _detail(item, 'المديرية', 'district'),
                  if (item.type == 'broker') ...[
                    _detail(item, 'مناطق العمل', 'work_areas'),
                    _detail(item, 'التخصصات', 'specialties'),
                  ],
                  if (item.type == 'office') ...[
                    _detail(item, 'اسم المكتب', 'office_name'),
                    _detail(item, 'رقم السجل التجاري', 'commercial_register_number'),
                    _detail(item, 'الحي', 'neighborhood'),
                    _detail(item, 'الشارع', 'street'),
                    _detail(item, 'أقرب معلم', 'landmark'),
                    _detail(item, 'هاتف المكتب', 'office_phone'),
                    _detail(item, 'خط العرض', 'latitude'),
                    _detail(item, 'خط الطول', 'longitude'),
                  ],
                  const Divider(height: 28),
                  const Text(
                    'المستندات',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  ...documents.map(
                    (document) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton.icon(
                        onPressed: () => _openDocument(item, document),
                        icon: const Icon(Icons.image),
                        label: Text(document.label),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _confirmApprove(item);
              },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('اعتماد التحقق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(
    AccountVerificationSupportItem item,
    String label,
    String key,
  ) {
    final value = item.detailText(key);
    if (value.isEmpty) return const SizedBox.shrink();
    return _InfoLine(label: label, value: value);
  }

  Future<void> _openDocument(
    AccountVerificationSupportItem item,
    _VerificationDocument document,
  ) async {
    try {
      final bytes = await ref
          .read(accountVerificationSupportRepositoryProvider)
          .documentBytes(item.userId, document.kind);
      if (!mounted) return;
      if (bytes.isEmpty) {
        _message('المستند غير موجود أو فارغ.');
        return;
      }
      await _showImage(document.label, bytes);
    } catch (error) {
      _message('تعذر فتح ${document.label}: ${friendlyApiError(error)}');
    }
  }

  Future<void> _showImage(String title, Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(title),
                  trailing: IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('تعذر عرض هذا الملف كصورة.'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmApprove(AccountVerificationSupportItem item) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اعتماد طلب التحقق؟'),
        content: Text(
          'سيصبح حساب ${item.typeLabel} موثقًا، وبعد نجاح الاعتماد يستطيع استخدام صلاحيات النشر المسموحة لهذه الصفة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _approvingUserId = item.userId);
    try {
      await ref
          .read(accountVerificationSupportRepositoryProvider)
          .approve(item.userId);
      if (!mounted) return;
      _message('تم اعتماد طلب التحقق بنجاح.');
      await _refresh();
    } catch (error) {
      _message(friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _approvingUserId = null);
    }
  }

  List<_VerificationDocument> _documentsFor(String type) => switch (type) {
        'owner' => const <_VerificationDocument>[
            _VerificationDocument('identity_document', 'صورة الهوية / الجواز'),
            _VerificationDocument('identity_back', 'الوجه الخلفي للهوية'),
            _VerificationDocument('selfie', 'صورة السيلفي'),
          ],
        'broker' => const <_VerificationDocument>[
            _VerificationDocument('identity_document', 'صورة الهوية / الجواز'),
            _VerificationDocument('identity_back', 'الوجه الخلفي للهوية'),
            _VerificationDocument('selfie', 'صورة السيلفي'),
            _VerificationDocument('professional_license', 'المستند المهني'),
          ],
        _ => const <_VerificationDocument>[
            _VerificationDocument('responsible_identity', 'هوية مسؤول المكتب'),
            _VerificationDocument('identity_back', 'الوجه الخلفي للهوية'),
            _VerificationDocument('selfie', 'صورة السيلفي'),
            _VerificationDocument('commercial_register', 'السجل التجاري'),
            _VerificationDocument('office_license', 'ترخيص المكتب'),
            _VerificationDocument('office_frontage', 'واجهة المكتب'),
            _VerificationDocument('office_logo', 'شعار المكتب'),
          ],
      };

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                '$label:',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _VerificationDocument {
  const _VerificationDocument(this.kind, this.label);

  final String kind;
  final String label;
}
