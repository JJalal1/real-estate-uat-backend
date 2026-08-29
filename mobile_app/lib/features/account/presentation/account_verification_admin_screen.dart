import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/account_verification_repository.dart';
import '../data/auth_controller.dart';
import '../domain/account_verification.dart';

class AccountVerificationAdminScreen extends ConsumerStatefulWidget {
  const AccountVerificationAdminScreen({super.key});

  @override
  ConsumerState<AccountVerificationAdminScreen> createState() =>
      _AccountVerificationAdminScreenState();
}

class _AccountVerificationAdminScreenState
    extends ConsumerState<AccountVerificationAdminScreen> {
  String _status = 'pending';
  String _typeFilter = 'all';
  bool _busy = false;
  late Future<List<AccountVerificationApplication>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AccountVerificationApplication>> _load() => ref
      .read(accountVerificationRepositoryProvider)
      .adminQueue(
        status: _status,
        type: _typeFilter == 'all' ? null : _typeFilter,
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final allowed = user?.isPlatformOwner == true ||
        user?.hasPermission('accounts.verify_profiles') == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طلبات توثيق الحسابات'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !allowed
            ? const Center(child: Text('لا تملك صلاحية مراجعة طلبات التحقق.'))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _status,
                            decoration: const InputDecoration(
                              labelText: 'الحالة',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'pending',
                                child: Text('قيد المراجعة'),
                              ),
                              DropdownMenuItem(
                                value: 'needs_more_info',
                                child: Text('يحتاج مستندًا إضافيًا'),
                              ),
                              DropdownMenuItem(
                                value: 'approved',
                                child: Text('موثق'),
                              ),
                              DropdownMenuItem(
                                value: 'rejected',
                                child: Text('مرفوض'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _status = value;
                                      _future = _load();
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _typeFilter,
                            decoration: const InputDecoration(
                              labelText: 'نوع الحساب',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem<String>(
                                value: 'all',
                                child: Text('الكل'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'owner',
                                child: Text('مالك'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'broker',
                                child: Text('دلال'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'office',
                                child: Text('مكتب عقارات'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == null) return;
                                      _typeFilter = value;
                                      _future = _load();
                                    });
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<List<AccountVerificationApplication>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                friendlyApiError(snapshot.error!),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        final rows = snapshot.data ?? const [];
                        if (rows.isEmpty) {
                          return const Center(
                            child: Text('لا توجد طلبات بهذه الفلاتر.'),
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: () async => _reload(),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final item = rows[index];
                              return Card(
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.verified_user_outlined),
                                  ),
                                  title: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item.typeLabel} • ${item.statusLabel}\n${item.phone ?? ''}',
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_left),
                                  onTap: _busy
                                      ? null
                                      : () => _reviewApplication(item),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _reviewApplication(
      AccountVerificationApplication application) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _AccountVerificationReviewDetails(
          application: application,
          repository: ref.read(accountVerificationRepositoryProvider),
          onAction: _performAction,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<bool> _performAction(
    AccountVerificationApplication application,
    String action,
    String? note,
  ) async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(accountVerificationRepositoryProvider);
      switch (action) {
        case 'approve':
          await repository.approve(application.userId, note: note);
          break;
        case 'more_info':
          await repository.requestMoreInfo(application.userId, note ?? '');
          break;
        case 'reject':
          await repository.reject(application.userId, note ?? '');
          break;
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reload() {
    setState(() => _future = _load());
  }
}

class _AccountVerificationReviewDetails extends StatefulWidget {
  const _AccountVerificationReviewDetails({
    required this.application,
    required this.repository,
    required this.onAction,
  });

  final AccountVerificationApplication application;
  final AccountVerificationRepository repository;
  final Future<bool> Function(
    AccountVerificationApplication application,
    String action,
    String? note,
  ) onAction;

  @override
  State<_AccountVerificationReviewDetails> createState() =>
      _AccountVerificationReviewDetailsState();
}

class _AccountVerificationReviewDetailsState
    extends State<_AccountVerificationReviewDetails> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.application;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text('مراجعة ${a.typeLabel}')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(a.phone ?? ''),
                    Text('نوع الحساب: ${a.typeLabel}'),
                    Text('الحالة: ${a.statusLabel}'),
                    if (a.note != null) Text('الملاحظة السابقة: ${a.note}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _detailsCard(a),
            const SizedBox(height: 8),
            Text('المستندات',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            ...a.documents.map((document) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(accountVerificationDocumentLabel(document.kind),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(document.originalName),
                    trailing: const Icon(Icons.open_in_full),
                    onTap: _busy ? null : () => _openDocument(document),
                  ),
                )),
            if (a.status == 'pending' || a.status == 'needs_more_info') ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _action('approve'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('اعتماد التحقق'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _action('more_info'),
                icon: const Icon(Icons.info_outline),
                label: const Text('طلب مستند أو توضيح إضافي'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _action('reject'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('رفض الطلب'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailsCard(AccountVerificationApplication a) {
    final rows = <(String, String?)>[
      ('المحافظة', a.detailText('governorate')),
      ('المديرية', a.detailText('district')),
      if (a.type == 'broker')
        ('مناطق العمل', a.detailStrings('work_areas').join('، ')),
      if (a.type == 'broker')
        ('التخصصات', a.detailStrings('specialties').join('، ')),
      if (a.type == 'office') ('اسم المكتب', a.detailText('office_name')),
      if (a.type == 'office')
        ('رقم السجل التجاري', a.detailText('commercial_register_number')),
      if (a.type == 'office') ('الحي', a.detailText('neighborhood')),
      if (a.type == 'office') ('الشارع', a.detailText('street')),
      if (a.type == 'office') ('أقرب معلم', a.detailText('landmark')),
      if (a.type == 'office') ('هاتف المكتب', a.detailText('office_phone')),
      if (a.type == 'office')
        (
          'الموقع',
          a.detailDouble('latitude') == null
              ? null
              : '${a.detailDouble('latitude')!.toStringAsFixed(6)}, ${a.detailDouble('longitude')!.toStringAsFixed(6)}'
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('بيانات الطلب',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const Divider(),
            ...rows.where((row) => row.$2 != null && row.$2!.trim().isNotEmpty).map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text('${row.$1}: ${row.$2}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocument(AccountVerificationDocumentItem document) async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.repository
          .documentBytes(widget.application.userId, document.kind);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(accountVerificationDocumentLabel(document.kind)),
                  trailing: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(30),
                        child: Text('تعذر عرض هذا الملف كصورة.'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action) async {
    String? note;
    if (action == 'more_info' || action == 'reject') {
      note = await _askNote(
        action == 'reject' ? 'سبب الرفض' : 'ما المستند أو التوضيح المطلوب؟',
        required: true,
      );
      if (note == null) return;
    } else {
      note = await _askNote('ملاحظة الاعتماد (اختياري)', required: false);
      if (note == null || !mounted) return;
    }
    setState(() => _busy = true);
    final ok = await widget.onAction(widget.application, action, note);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<String?> _askNote(String title, {required bool required}) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (required && value.length < 3) return;
              Navigator.of(context).pop(value.isEmpty ? '' : value);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
