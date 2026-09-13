import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/agreement_repository.dart';
import '../domain/agreement_models.dart';
import 'agreement_forms.dart';

class RentalContractDetailScreen extends ConsumerStatefulWidget {
  const RentalContractDetailScreen({required this.contractId, super.key});
  final int contractId;

  @override
  ConsumerState<RentalContractDetailScreen> createState() =>
      _RentalContractDetailScreenState();
}

class _RentalContractDetailScreenState
    extends ConsumerState<RentalContractDetailScreen> {
  RentalContract? _contract;
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
      final value = await ref
          .read(agreementRepositoryProvider)
          .contract(widget.contractId);
      if (!mounted) return;
      setState(() {
        _contract = value;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _accept() async {
    final contract = _contract;
    if (contract == null || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(agreementRepositoryProvider)
          .acceptRentalContract(contract.id, contract.currentRevision.id);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      setState(() => _contract = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updated.isActive
              ? 'وافق الطرفان على نفس نسخة عقد الإيجار داخل التطبيق.'
              : 'تم تسجيل قبولك لهذه النسخة. بانتظار الطرف الآخر.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revise() async {
    final contract = _contract;
    if (contract == null || _busy) return;
    final terms = await showRentalContractTermsSheet(
      context,
      current: contract.currentRevision,
    );
    if (terms == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(agreementRepositoryProvider)
          .reviseRentalContract(contract.id, terms);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      setState(() => _contract = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إنشاء نسخة جديدة. يحتاج الطرفان إلى قبولها من جديد.',
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

  Future<void> _cancel() async {
    final contract = _contract;
    if (contract == null || _busy) return;
    final reason = await _reasonDialog('إلغاء مسودة عقد الإيجار');
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(agreementRepositoryProvider)
          .cancelRentalContract(contract.id, reason);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      setState(() => _contract = updated);
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

  Future<void> _terminate() async {
    final contract = _contract;
    if (contract == null || _busy) return;
    final reason = await _reasonDialog('تسجيل انتهاء عقد الإيجار داخل التطبيق');
    if (reason == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تسجيل الانتهاء'),
        content: const Text(
          'سيتم حفظ انتهاء السجل داخل التطبيق مع السبب والتاريخ. لا يمثل هذا الإجراء بحد ذاته حكماً قانونياً أو توثيقاً حكومياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تسجيل الانتهاء'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(agreementRepositoryProvider)
          .terminateRentalContract(contract.id, reason);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      setState(() => _contract = updated);
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
          maxLength: 3000,
          decoration: const InputDecoration(labelText: 'السبب'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('رجوع'),
          ),
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
          title: const Text('عقد الإيجار داخل التطبيق'),
          actions: [
            IconButton(
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _body(_contract!),
      ),
    );
  }

  Widget _body(RentalContract contract) {
    final revision = contract.currentRevision;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.home_work_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        contract.statusLabel,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('مرجع: ${contract.reference}'),
                const SizedBox(height: 8),
                const Text(
                  'هذا سجل عقد إيجار داخل التطبيق فقط. لا يمثل توثيقاً حكومياً أو تسجيلاً رسمياً أو حكماً على الأثر القانوني، ولا يقدم استشارة قانونية.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('العقار والأطراف',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _row('العقار', contract.propertyTitle),
                if (contract.propertyAddress != null)
                  _row('العنوان', contract.propertyAddress!),
                _row('المستأجر', contract.tenantName),
                _row('المعلن/المؤجر', contract.advertiserName),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _termsCard(contract),
        const SizedBox(height: 12),
        _acceptanceCard(contract),
        if (contract.closureReason != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('سجل الإغلاق',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(contract.closureReason!),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  context.push('/agreements/${contract.propertyAgreementId}'),
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('الاتفاق'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  context.push('/messages/${contract.messageThreadId}'),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('المحادثة'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/properties/${contract.propertyId}'),
              icon: const Icon(Icons.home_outlined),
              label: const Text('العقار'),
            ),
          ],
        ),
        if (contract.canAccept) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _accept,
            icon: const Icon(Icons.verified_outlined),
            label: Text('أوافق على النسخة ${revision.revisionNumber}'),
          ),
        ],
        if (contract.canRevise) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _revise,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('اقتراح بنود جديدة'),
          ),
        ],
        if (contract.canCancel) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('إلغاء مسودة العقد'),
          ),
        ],
        if (contract.canTerminate) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _terminate,
            icon: const Icon(Icons.event_busy_outlined),
            label: const Text('تسجيل انتهاء العقد داخل التطبيق'),
          ),
        ],
        if (contract.revisions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('سجل النسخ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...contract.revisions.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${item.revisionNumber}')),
              title: Text(moneyLabel(item.rentAmount, item.currency)),
              subtitle: Text(
                'أنشأها ${item.createdByName}${item.createdAt == null ? '' : ' • ${_date(item.createdAt!)}'}',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _termsCard(RentalContract contract) {
    final r = contract.currentRevision;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('النسخة الحالية ${r.revisionNumber}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            _row('الإيجار', moneyLabel(r.rentAmount, r.currency)),
            _row('الدورية', r.cadenceLabel),
            _row('البداية', _date(r.startDate)),
            _row('النهاية', _date(r.endDate)),
            if (r.securityDepositAmount != null)
              _row('الضمان المسجل',
                  moneyLabel(r.securityDepositAmount!, r.currency)),
            if (r.paymentDueDay != null)
              _row('يوم الاستحقاق', '${r.paymentDueDay} من الشهر'),
            if (r.additionalTerms != null) ...[
              const Divider(),
              Text(r.additionalTerms!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _acceptanceCard(RentalContract contract) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('قبول النسخة الحالية',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            _acceptance('المستأجر', contract.tenantAccepted),
            _acceptance('المعلن/المؤجر', contract.advertiserAccepted),
            if (!contract.isActive)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'لا يصبح سجل العقد فعالاً داخل التطبيق إلا بعد قبول الطرفين لنفس النسخة.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _acceptance(String label, bool accepted) => Row(
        children: [
          Icon(
            accepted ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text('$label: ${accepted ? 'وافق' : 'لم يوافق بعد'}'),
        ],
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
}
