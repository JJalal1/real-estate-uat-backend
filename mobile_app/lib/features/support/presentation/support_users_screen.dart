import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../account/data/access_control_repository.dart';
import '../../account/domain/access_models.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportUsersScreen extends ConsumerWidget {
  const SupportUsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorScopedPage(title: 'المستخدمون - الدعم',
    builder: (_) => const _SupportUsersBody());
}

class _SupportUsersBody extends ConsumerStatefulWidget {
  const _SupportUsersBody();
  @override
  ConsumerState<_SupportUsersBody> createState() => _SupportUsersScreenState();
}

class _SupportUsersScreenState extends ConsumerState<_SupportUsersBody> {
  final _search = TextEditingController();
  bool _loading = false;
  bool _restoring = false;
  String? _error;
  List<AccessUserSummary> _users = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(accessControlRepositoryProvider)
          .users(search: _search.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _users = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = friendlyApiError(e);
        if (!isTransientApiFailure(e)) _users = const [];
      });
    }
  }

  Future<void> _open(AccessUserSummary user) async {
    try {
      final data =
          await ref.read(supportRepositoryProvider).userContext(user.id);
      if (!mounted) {
        return;
      }
      final action = await showActorDialog<({int? caseId, bool restoreHold})>(
        context: context, ref: ref,
        builder: (_) => _UserContextDialog(contextData: data),
      );
      if (!mounted || action == null) return;
      final caseId = action.caseId;
      if (caseId != null) {
        context.push('/admin/support?case=$caseId');
      } else if (action.restoreHold) {
        await _restoreFinancialHold(user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(e))),
        );
      }
    }
  }

  Future<void> _restoreFinancialHold(AccessUserSummary user) async {
    if (_restoring) return;
    final form = GlobalKey<FormState>();
    var reason = '';
    final note = await showActorDialog<String>(
      context: context,
      ref: ref,
      builder: (dialog) => AlertDialog(
        title: const Text('إعادة تفعيل النشر'),
        scrollable: true,
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('إعادة تفعيل النشر وإظهار الإعلانات الموقوفة ماليًا للحساب «${user.name}». يبقى المستحق ظاهرًا حتى اعتماد السداد.'),
            TextFormField(
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'سبب إعادة التفعيل'),
              onChanged: (value) => reason = value.trim(),
              validator: (_) => reason.length < 3 ? 'اكتب سبب إعادة التفعيل' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')),
          EbrokerFilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(dialog, reason);
            },
            child: const Text('إعادة التفعيل'),
          ),
        ],
      ),
    );
    if (!mounted || note == null) return;
    setState(() => _restoring = true);
    try {
      await ref.read(supportRepositoryProvider).restoreFinancialHold(user.id, note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع القيد المالي على النشر.')));
      await _load();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('المستخدمون - الدعم')),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                      labelText: 'بحث بالاسم أو الهاتف أو البريد',
                      prefixIcon: const EbrokerIcon(Icons.search),
                      suffixIcon: IconButton(
                          onPressed: _load,
                          icon: const EbrokerIcon(Icons.arrow_forward))),
                )),
            if (_users.isNotEmpty && (_loading || _error != null))
              AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
            Expanded(
                child: _loading && _users.isEmpty ? const AppLoadingState()
                    : _error != null && _users.isEmpty ? AppErrorState(message: _error!, onRetry: _load)
                    : _users.isEmpty
                    ? const AppEmptyState(title: 'لا توجد نتائج', message: 'جرّب اسمًا أو رقمًا آخر.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final user = _users[i];
                          return Card(
                              child: ListTile(
                            leading: const CircleAvatar(
                                child: EbrokerIcon(Icons.person_outline)),
                            title: Text(user.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              if (user.phone != null) user.phone!,
                              user.email,
                              'الحالة: ${user.accountStatus}'
                            ].join('\n')),
                            trailing: const EbrokerIcon(Icons.chevron_left),
                            onTap: _restoring ? null : () => _open(user),
                          ));
                        },
                      )),
          ]),
        ),
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class _UserContextDialog extends StatelessWidget {
  const _UserContextDialog({required this.contextData});
  final SupportUserContext contextData;
  @override
  Widget build(BuildContext context) {
    final user = contextData.user;
    return AlertDialog(
      title: Text(user['name']?.toString() ?? 'المستخدم'),
      content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('الهاتف: ${user['phone'] ?? '-'}'),
                Text('البريد: ${user['email'] ?? '-'}'),
                Text('الحالة: ${user['account_status'] ?? '-'}'),
                Text('نوع الحساب: ${user['account_type'] ?? '-'}'),
                if (user['financial_hold_active'] == true)
                  const Text('إيقاف مؤقت للنشر بسبب مستحقات المنصة'),
                const Divider(height: 24),
                Text(
                    'تذاكر: ${contextData.counts['tickets'] ?? 0} • بلاغات: ${contextData.counts['reports'] ?? 0} • مفتوحة: ${contextData.counts['open'] ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (contextData.cases.isNotEmpty)
                  const Text(
                    'اضغط على التذكرة أو البلاغ لفتح إجراءات الدعم المسموحة لك.',
                  ),
                ...contextData.cases.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.subject),
                    subtitle: Text('${item.reference} • ${item.status}'),
                    trailing: const EbrokerIcon(Icons.chevron_left),
                    onTap: () => Navigator.pop(context, (caseId: item.id, restoreHold: false)))),
              ]))),
      actions: [
        if (user['can_restore_financial_hold'] == true)
          EbrokerFilledButton(
            onPressed: () => Navigator.pop(context, (caseId: null, restoreHold: true)),
            child: const Text('إعادة تفعيل النشر'),
          ),
        EbrokerFilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))
      ],
    );
  }
}
