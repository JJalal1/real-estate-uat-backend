import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../data/account_safety_repository.dart';
import '../data/auth_controller.dart';

class AccountSafetyScreen extends ConsumerWidget {
  const AccountSafetyScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authControllerProvider).asData?.value?.id;
    return actor == null ? const Scaffold(body: Center(child: Text('سجّل الدخول للمتابعة.')))
      : _AccountSafetyBody(key: ValueKey(actor), actorId: actor);
  }
}
class _AccountSafetyBody extends ConsumerStatefulWidget {
  const _AccountSafetyBody({required this.actorId, super.key});
  final int actorId;
  @override
  ConsumerState<_AccountSafetyBody> createState() => _AccountSafetyBodyState();
}
class _AccountSafetyBodyState extends ConsumerState<_AccountSafetyBody> {
  List<BlockedAccount> _blocked = const [];
  DeletionRequestStatus? _deletion;
  String? _error;
  bool _loading = true, _busy = false, _more = false, _confirming = false;
  int _page = 1, _generation = 0;
  bool get _valid => mounted && ref.read(authControllerProvider).asData?.value?.id == widget.actorId;
  @override
  void initState() { super.initState(); Future.microtask(_load); }
  Future<void> _load({bool more = false}) async {
    if (!_valid) return;
    if (more && (_busy || _loading || !_more)) return;
    final generation = ++_generation;
    setState(() { _error = null; if (more) { _busy = true; } else { _loading = true; } });
    try {
      final repo = ref.read(accountSafetyRepositoryProvider);
      final page = more ? _page + 1 : 1;
      final values = await Future.wait<dynamic>([repo.blocked(page: page), repo.deletionStatus()]);
      if (!_valid || generation != _generation) return;
      final result = values[0] as BlockedAccountPage;
      setState(() {
        _blocked = more ? [..._blocked, ...result.accounts] : result.accounts;
        _more = result.hasMore; _page = page; _deletion = values[1] as DeletionRequestStatus;
      });
    } catch (error) {
      if (_valid && generation == _generation) setState(() => _error = friendlyApiError(error));
    } finally {
      if (_valid && generation == _generation) setState(() { _loading = false; _busy = false; });
    }
  }
  Future<bool> _confirm({required String title, required String message, required String action}) async {
    if (_confirming) return false;
    setState(() => _confirming = true);
    try { return await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      scrollable: true, title: Text(title), content: Text(message), actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(action)),
      ])) ?? false; } finally { if (_valid) setState(() => _confirming = false); }
  }
  Future<void> _unblock(BlockedAccount account) async {
    if (_busy || !await _confirm(title: 'إلغاء الحظر؟', message: 'يمكن استئناف الرسائل الجديدة إذا كانت متاحة لدى الطرف الآخر. يبقى تاريخ المحادثة محفوظًا.', action: 'إلغاء الحظر') || !_valid) return;
    setState(() => _busy = true);
    try {
      await ref.read(accountSafetyRepositoryProvider).setBlocked(account.id, false);
      if (_valid) setState(() => _blocked = _blocked.where((x) => x.id != account.id).toList());
    } catch (error) { if (_valid) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
    finally { if (_valid) setState(() => _busy = false); }
  }
  Future<void> _requestDeletion() async {
    if (_busy || !await _confirm(title: 'إرسال طلب حذف الحساب؟', message: 'يراجع الدعم طلبك والحقوق القائمة والبيانات الواجب الاحتفاظ بها. إرسال الطلب لا يحذف حسابك أو إعلاناتك، وستتابع الرد من الدعم.', action: 'إرسال الطلب للمراجعة') || !_valid) return;
    setState(() => _busy = true);
    try {
      final status = await ref.read(accountSafetyRepositoryProvider).requestDeletion();
      if (_valid) setState(() => _deletion = status);
    } catch (error) { if (_valid) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error)))); }
    finally { if (_valid) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Text('الأمان والخصوصية'), actions: [IconButton(tooltip: 'تحديث', onPressed: _loading || _busy || _confirming ? null : _load, icon: const Icon(Icons.refresh))]),
    body: _loading ? const AppLoadingState() : ListView(padding: const EdgeInsets.all(16), children: [
      if (_error != null) ...[AppErrorState(message: _error!, onRetry: _load), const SizedBox(height: 16)],
      AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('الحسابات المحظورة', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8), const Text('الحظر يوقف الرسائل الجديدة بينكما. تبقى المحادثات السابقة وإمكانية البلاغ محفوظة.'),
        if (_blocked.isEmpty && _error == null) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('لا توجد حسابات محظورة.')),
        for (final account in _blocked) Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(account.name), Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: _busy || _confirming ? null : () => _unblock(account), child: const Text('إلغاء الحظر'))),
        ])),
        if (_more) TextButton(onPressed: _busy || _confirming ? null : () => _load(more: true), child: const Text('عرض المزيد')),
      ])),
      const SizedBox(height: 16),
      AppSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('طلب حذف الحساب', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8), const Text('أرسل طلبًا للدعم لمراجعة حذف الحساب. لا يُنفذ حذف نهائي حاليًا، ويظل حسابك وبياناتك محفوظين أثناء المراجعة.'),
        if (_deletion?.hasRequest == true) ...[
          const SizedBox(height: 12), Semantics(liveRegion: true, child: Text('${_deletion!.label} — ${_deletion!.reference}')),
          TextButton(onPressed: () => context.push('/support?case=${_deletion!.caseId}'), child: const Text('متابعة الطلب في الدعم')),
        ] else if (_error == null) Padding(padding: const EdgeInsets.only(top: 12), child: OutlinedButton.icon(
          key: const ValueKey('request-account-deletion'), onPressed: _busy || _confirming ? null : _requestDeletion,
          icon: const Icon(Icons.person_remove_outlined), label: const Text('طلب المراجعة'))),
      ])),
      if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
    ])));
}
