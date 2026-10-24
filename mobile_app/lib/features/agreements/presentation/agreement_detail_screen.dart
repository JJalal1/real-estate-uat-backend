import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart' show AppErrorState, AppRefreshStatus, AppLoadingState;
import '../../account/presentation/actor_scoped_page.dart';
import '../../financial/presentation/deal_financial_screen.dart';
import '../data/agreement_repository.dart';
import '../domain/agreement_models.dart';
import 'agreement_forms.dart';

class AgreementDetailScreen extends ConsumerWidget {
  const AgreementDetailScreen({required this.agreementId, super.key});
  final int agreementId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorScopedPage(title: 'تفاصيل الاتفاق', builder: (_) =>
    _AgreementDetailScreenForActor(key: ValueKey(agreementId), agreementId: agreementId));
}

class _AgreementDetailScreenForActor extends ConsumerStatefulWidget {
  const _AgreementDetailScreenForActor({required this.agreementId, super.key});
  final int agreementId;

  @override
  ConsumerState<_AgreementDetailScreenForActor> createState() => _AgreementDetailPageState();
}

class _AgreementDetailPageState extends ConsumerState<_AgreementDetailScreenForActor> {
  PropertyAgreement? _agreement;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final value = await ref.read(agreementRepositoryProvider).agreement(widget.agreementId);
      if (!mounted || generation != _generation) return;
      setState(() { _agreement = value; _loading = false; _error = null; });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!isTransientApiFailure(error)) { _agreement = null; }
        _loading = false; _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _accept() async {
    final agreement = _agreement;
    if (agreement == null || _busy || _loading || _error != null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(agreementRepositoryProvider).acceptAgreement(
            agreement.id,
            agreement.currentRevision.id,
          );
      if (!mounted) return;
      ref.read(agreementDataRevisionProvider.notifier).state++;
      setState(() => _agreement = updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(updated.isAccepted
            ? 'وافق الطرفان على نفس نسخة الاتفاق.'
            : 'تم تسجيل قبولك لهذه النسخة. بانتظار الطرف الآخر.'),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revise() async {
    final agreement = _agreement;
    if (agreement == null || _busy || _loading || _error != null) return;
    final terms = await showAgreementTermsSheet(context, current: agreement.currentRevision);
    if (terms == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(agreementRepositoryProvider).reviseAgreement(agreement.id, terms);
      if (!mounted) return;
      ref.read(agreementDataRevisionProvider.notifier).state++;
      setState(() => _agreement = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء نسخة جديدة. يحتاج الطرفان إلى قبولها من جديد.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final agreement = _agreement;
    if (agreement == null || _busy || _loading || _error != null) return;
    final reason = await _reasonDialog('إلغاء مسودة الاتفاق');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(agreementRepositoryProvider).cancelAgreement(agreement.id, reason);
      if (!mounted) return;
      ref.read(agreementDataRevisionProvider.notifier).state++;
      setState(() => _agreement = updated);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createRentalContract() async {
    final agreement = _agreement;
    if (agreement == null || !agreement.isRental || !agreement.isAccepted || _busy || _loading || _error != null) return;
    final terms = await showRentalContractTermsSheet(context, fromAgreement: agreement.currentRevision);
    if (terms == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final contract = await ref.read(agreementRepositoryProvider).startRentalContract(agreement.id, terms);
      if (!mounted) return;
      ref.read(agreementDataRevisionProvider.notifier).state++;
      await _load();
      if (mounted) await context.push('/rental-contracts/${contract.id}');
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _reasonDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: 'السبب'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('رجوع')),
          EbrokerFilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().length < 2) return null;
    return result.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل الاتفاق'),
          actions: [IconButton(tooltip: 'تحديث', onPressed: _busy || _loading ? null : _load, icon: const EbrokerIcon(Icons.refresh))],
        ),
        body: _agreement == null && _loading
            ? const AppLoadingState()
            : _agreement == null
                ? AppErrorState(message: _error ?? 'هذا السجل غير متاح.', onRetry: _load)
                : _body(_agreement!),
      ),
    );
  }

  Widget _body(PropertyAgreement agreement) {
    final revision = agreement.currentRevision;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const EbrokerIcon(Icons.handshake_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text('${agreement.transactionLabel} • ${agreement.statusLabel}', style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 6),
              Text('مرجع: ${agreement.reference}'),
              const SizedBox(height: 4),
              const Text('سجل اتفاق داخل التطبيق فقط — لا يمثل توثيقاً حكومياً أو نقل ملكية أو استشارة قانونية.'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _termsCard(agreement),
        const SizedBox(height: 12),
        _acceptanceCard(agreement),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          EbrokerOutlinedButton.icon(
            onPressed: () => context.push('/messages/${agreement.messageThreadId}'),
            icon: const EbrokerIcon(Icons.chat_bubble_outline),
            label: const Text('المحادثة'),
          ),
          EbrokerOutlinedButton.icon(
            onPressed: () => context.push('/properties/${agreement.propertyId}'),
            icon: const EbrokerIcon(Icons.home_outlined),
            label: const Text('العقار'),
          ),
        ]),
        if (agreement.canAccept) ...[
          const SizedBox(height: 16),
          EbrokerFilledButton.icon(
            onPressed: _busy || _loading || _error != null ? null : _accept,
            icon: const EbrokerIcon(Icons.verified_outlined),
            label: Text('أوافق على النسخة ${revision.revisionNumber}'),
          ),
        ],
        if (agreement.canRevise) ...[
          const SizedBox(height: 8),
          EbrokerOutlinedButton.icon(
            onPressed: _busy || _loading || _error != null ? null : _revise,
            icon: const EbrokerIcon(Icons.edit_note_outlined),
            label: const Text('اقتراح شروط جديدة'),
          ),
        ],
        if (agreement.canCancel) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy || _loading || _error != null ? null : _cancel,
            icon: const EbrokerIcon(Icons.cancel_outlined),
            label: const Text('إلغاء مسودة الاتفاق'),
          ),
        ],
        if (agreement.isAccepted) ...[
          const SizedBox(height: 18),
          EbrokerFilledButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DealFinancialScreen(agreementId: agreement.id),
              ),
            ),
            icon: const EbrokerIcon(Icons.account_balance_wallet_outlined),
            label: const Text('فتح تسوية الصفقة'),
          ),
        ],
        if (agreement.isAccepted && agreement.isRental) ...[
          const SizedBox(height: 10),
          if (agreement.rentalContractId == null)
            EbrokerFilledButton.tonalIcon(
              onPressed: _busy || _loading || _error != null ? null : _createRentalContract,
              icon: const EbrokerIcon(Icons.home_work_outlined),
              label: const Text('إنشاء عقد إيجار داخل التطبيق'),
            )
          else
            EbrokerFilledButton.tonalIcon(
              onPressed: () => context.push('/rental-contracts/${agreement.rentalContractId}'),
              icon: const EbrokerIcon(Icons.description_outlined),
              label: const Text('فتح عقد الإيجار'),
            ),
        ],
        if (agreement.isAccepted && !agreement.isRental) ...[
          const SizedBox(height: 10),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('تم اعتماد اتفاق البيع داخل التطبيق. نقل الملكية والتوثيق الرسمي وأي إجراءات حكومية خارج نطاق هذه المرحلة.'),
            ),
          ),
        ],
        if (agreement.revisions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('سجل النسخ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...agreement.revisions.map((item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${item.revisionNumber}')),
                title: Text(moneyLabel(item.agreedAmount, item.currency)),
                subtitle: Text('أنشأها ${item.createdByName}${item.createdAt == null ? '' : ' • ${_date(item.createdAt!)}'}'),
              )),
        ],
      ],
    );
  }

  Widget _termsCard(PropertyAgreement agreement) {
    final r = agreement.currentRevision;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('النسخة الحالية ${r.revisionNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _row('المبلغ', moneyLabel(r.agreedAmount, r.currency)),
          if (agreement.isRental) ...[
            _row('الدورية', r.cadenceLabel),
            if (r.securityDepositAmount != null) _row('الضمان المسجل', moneyLabel(r.securityDepositAmount!, r.currency)),
            if (r.rentalStartDate != null) _row('بداية الإيجار', _date(r.rentalStartDate!)),
            if (r.rentalEndDate != null) _row('نهاية الإيجار', _date(r.rentalEndDate!)),
          ],
          if (r.conditions != null) ...[
            const Divider(),
            Text(r.conditions!),
          ],
        ]),
      ),
    );
  }

  Widget _acceptanceCard(PropertyAgreement agreement) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('قبول النسخة الحالية', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _acceptance('طالب العقار/المستأجر', agreement.requesterAccepted),
          _acceptance('المعلن', agreement.advertiserAccepted),
          if (!agreement.isAccepted)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('لا يصبح الاتفاق مقبولاً إلا بعد موافقة الطرفين على نفس النسخة.'),
            ),
        ]),
      ),
    );
  }

  Widget _acceptance(String label, bool accepted) => Row(children: [
        EbrokerIcon(accepted ? Icons.check_circle : Icons.radio_button_unchecked, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('$label: ${accepted ? 'وافق' : 'لم يوافق بعد'}')),
      ]);

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(value)),
        ]),
      );

  String _date(DateTime value) => '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}
