import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/agreement_repository.dart';
import '../domain/agreement_models.dart';
import 'agreement_forms.dart';

class AgreementDetailScreen extends ConsumerStatefulWidget {
  const AgreementDetailScreen({required this.agreementId, super.key});
  final int agreementId;

  @override
  ConsumerState<AgreementDetailScreen> createState() => _AgreementDetailScreenState();
}

class _AgreementDetailScreenState extends ConsumerState<AgreementDetailScreen> {
  PropertyAgreement? _agreement;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final value = await ref.read(agreementRepositoryProvider).agreement(widget.agreementId);
      if (!mounted) return;
      setState(() { _agreement = value; _loading = false; _error = null; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = friendlyApiError(error); });
    }
  }

  Future<void> _accept() async {
    final agreement = _agreement;
    if (agreement == null || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(agreementRepositoryProvider).acceptAgreement(
            agreement.id,
            agreement.currentRevision.id,
          );
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
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
    if (agreement == null || _busy) return;
    final terms = await showAgreementTermsSheet(context, current: agreement.currentRevision);
    if (terms == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(agreementRepositoryProvider).reviseAgreement(agreement.id, terms);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
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
    if (agreement == null || _busy) return;
    final reason = await _reasonDialog('إلغاء مسودة الاتفاق');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(agreementRepositoryProvider).cancelAgreement(agreement.id, reason);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      setState(() => _agreement = updated);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createRentalContract() async {
    final agreement = _agreement;
    if (agreement == null || !agreement.isRental || !agreement.isAccepted || _busy) return;
    final terms = await showRentalContractTermsSheet(context, fromAgreement: agreement.currentRevision);
    if (terms == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final contract = await ref.read(agreementRepositoryProvider).startRentalContract(agreement.id, terms);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
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
          FilledButton(
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
          actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : _body(_agreement!),
      ),
    );
  }

  Widget _body(PropertyAgreement agreement) {
    final revision = agreement.currentRevision;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.handshake_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text('${agreement.transactionLabel} • ${agreement.statusLabel}', style: const TextStyle(fontWeight: FontWeight.w900))),
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
          OutlinedButton.icon(
            onPressed: () => context.push('/messages/${agreement.messageThreadId}'),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('المحادثة'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push('/properties/${agreement.propertyId}'),
            icon: const Icon(Icons.home_outlined),
            label: const Text('العقار'),
          ),
        ]),
        if (agreement.canAccept) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _accept,
            icon: const Icon(Icons.verified_outlined),
            label: Text('أوافق على النسخة ${revision.revisionNumber}'),
          ),
        ],
        if (agreement.canRevise) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _revise,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('اقتراح شروط جديدة'),
          ),
        ],
        if (agreement.canCancel) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('إلغاء مسودة الاتفاق'),
          ),
        ],
        if (agreement.isAccepted && agreement.isRental) ...[
          const SizedBox(height: 18),
          if (agreement.rentalContractId == null)
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _createRentalContract,
              icon: const Icon(Icons.home_work_outlined),
              label: const Text('إنشاء عقد إيجار داخل التطبيق'),
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => context.push('/rental-contracts/${agreement.rentalContractId}'),
              icon: const Icon(Icons.description_outlined),
              label: const Text('فتح عقد الإيجار'),
            ),
        ],
        if (agreement.isAccepted && !agreement.isRental) ...[
          const SizedBox(height: 18),
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
          Text('النسخة الحالية ${r.revisionNumber}', style: const TextStyle(fontWeight: FontWeight.w900)),
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
          const Text('قبول النسخة الحالية', style: TextStyle(fontWeight: FontWeight.w900)),
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
        Icon(accepted ? Icons.check_circle : Icons.radio_button_unchecked, size: 20),
        const SizedBox(width: 8),
        Text('$label: ${accepted ? 'وافق' : 'لم يوافق بعد'}'),
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
