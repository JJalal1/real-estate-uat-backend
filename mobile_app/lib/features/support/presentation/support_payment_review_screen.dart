import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/stage6_secure_session_store.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../account/data/account_request_scope.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../../financial/data/financial_repository.dart';
import '../../financial/domain/financial_models.dart';

class SupportPaymentReviewScreen extends ConsumerStatefulWidget {
  const SupportPaymentReviewScreen({
    super.key,
    required this.paymentId,
    required this.actingAsAgent,
    this.advertiserName,
  });

  final int paymentId;
  final bool actingAsAgent;
  final String? advertiserName;

  @override
  ConsumerState<SupportPaymentReviewScreen> createState() =>
      _SupportPaymentReviewScreenState();
}

class _SupportPaymentReviewScreenState
    extends ConsumerState<SupportPaymentReviewScreen> {
  late Future<FinancialPayment> _payment;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _payment = ref.read(financialRepositoryProvider).adminPayment(
          widget.paymentId,
          actingAsAgent: widget.actingAsAgent,
        );
  }

  Future<MemoryImage> _loadProof() async {
    final response = await ref.read(financialRepositoryProvider).paymentProof(
          widget.paymentId,
          actingAsAgent: widget.actingAsAgent,
        );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw StateError('إيصال الدفع فارغ');
    return MemoryImage(Uint8List.fromList(bytes));
  }

  void _showProof(MemoryImage image) {
    final actor = ref.read(authControllerProvider).asData?.value?.id;
    if (actor == null) return;
    final epoch = Stage6SecureSessionStore.instance.sessionEpoch;
    final scope = ref.read(accountRequestScopeProvider);
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ActorBoundPage(
        title: 'صورة الإيصال',
        actorId: actor,
        sessionEpoch: epoch,
        requestScope: scope,
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xff101c2a),
          appBar: AppBar(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xff101c2a),
            title: const Text('صورة الإيصال'),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image(
                image: image,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                  'تعذر عرض الصورة.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> _decide(String decision, String title) async {
    if (_saving) return;
    final scope = ref.read(accountRequestScopeProvider);
    setState(() => _saving = true);
    try {
      final comment = await showActorDialog<String>(
        ref: ref,
        context: context,
        builder: (_) => _PaymentDecisionDialog(
          title: title,
          requiresReason: decision != 'confirm',
        ),
      );
      if (comment == null || !mounted || !scope.isCurrent) return;
      final payment = await ref.read(financialRepositoryProvider).reviewPayment(
            widget.paymentId,
            decision,
            note: comment.isEmpty ? null : comment,
            actingAsAgent: widget.actingAsAgent,
          );
      if (!mounted || !scope.isCurrent) return;
      Navigator.pop(context, payment.statusLabel);
    } catch (error) {
      if (!mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _facts(FinancialPayment payment) {
    final date = payment.submittedAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(payment.propertyTitle ?? 'مراجعة إيصال سداد',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _fact(
            payment.mode == 'platform_receivable' ? 'المعلن' : 'الدافع',
            widget.advertiserName,
          ),
          Text(payment.statusLabel),
          const Divider(),
          _fact('المبلغ المطلوب', moneyLabel(payment.amount, payment.currency)),
          _fact('مرجع المستحق', payment.receivableReference),
          _fact('مرجع الدفع', payment.reference),
          _fact('طريقة الدفع', payment.paymentMethod),
          _fact('رقم العملية', payment.providerReference),
          _fact('اسم المرسل', payment.senderName),
          _fact('رقم المرسل', payment.senderPhone),
          if (date != null)
            _fact('وقت رفع الإيصال', '${localizations.formatCompactDate(date)} · '
                '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}'),
          _fact('ملاحظة المراجعة', payment.reviewNote),
        ],
      ),
    );
  }

  Widget _fact(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('$label · $value'),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FinancialPayment>(
        future: _payment,
        builder: (context, snapshot) {
          final payment = snapshot.data;
          final reviewable = payment?.status == 'proof_submitted' ||
              payment?.status == 'under_review';
          return Scaffold(
            appBar: AppBar(title: const Text('مراجعة إيصال سداد')),
            body: snapshot.connectionState != ConnectionState.done
                ? const AppLoadingState(label: 'جارٍ تحميل المهمة…')
                : payment == null
                    ? AppErrorState(
                        message: friendlyApiError(snapshot.error ??
                            StateError('تعذر تحميل عملية الدفع')),
                        onRetry: () => setState(_load),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _facts(payment),
                          if (payment.hasProof) ...[
                            const SizedBox(height: 16),
                            const AppSectionHeader(title: 'إثبات السداد'),
                            const SizedBox(height: 8),
                            _ReceiptPreview(
                              load: _loadProof,
                              open: _showProof,
                            ),
                          ],
                        ],
                      ),
            bottomNavigationBar: !reviewable
                ? null
                : SafeArea(
                    minimum: const EdgeInsets.all(12),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        EbrokerFilledButton(
                          onPressed: _saving
                              ? null
                              : () => _decide('confirm', 'اعتماد السداد'),
                          child: const Text('اعتماد السداد'),
                        ),
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _decide('correction', 'طلب تصحيح الإيصال'),
                          child: const Text('طلب تصحيح الإيصال'),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => _decide('reject', 'رفض الإثبات'),
                          child: const Text('رفض الإثبات'),
                        ),
                      ],
                    ),
                  ),
          );
        },
      );
}

class _ReceiptPreview extends StatefulWidget {
  const _ReceiptPreview({
    required this.load,
    required this.open,
  });

  final Future<MemoryImage> Function() load;
  final ValueChanged<MemoryImage> open;

  @override
  State<_ReceiptPreview> createState() => _ReceiptPreviewState();
}

class _ReceiptPreviewState extends State<_ReceiptPreview> {
  late Future<MemoryImage> _loading;
  MemoryImage? _image;

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<MemoryImage> _load() async {
    final image = await widget.load();
    if (mounted) _image = image;
    return image;
  }

  @override
  void dispose() {
    _image?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MemoryImage>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppLoadingState(label: 'جارٍ تحميل الإيصال…');
          }
          final image = snapshot.data;
          if (snapshot.hasError || image == null) {
            return AppErrorState(
              message: 'تعذر تحميل صورة الإيصال.',
              onRetry: () => setState(() => _loading = _load()),
            );
          }
          return AppSurface(
            child: Column(
              children: [
                InkWell(
                  onTap: () => widget.open(image),
                  child: Image(
                    image: image,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Text('تعذر عرض صورة الإيصال.'),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => widget.open(image),
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('عرض الإيصال'),
                ),
              ],
            ),
          );
        },
      );
}

class _PaymentDecisionDialog extends StatefulWidget {
  const _PaymentDecisionDialog({required this.title, required this.requiresReason});

  final String title;
  final bool requiresReason;

  @override
  State<_PaymentDecisionDialog> createState() => _PaymentDecisionDialogState();
}

class _PaymentDecisionDialogState extends State<_PaymentDecisionDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: widget.requiresReason
            ? TextField(
                controller: _reason,
                maxLines: 3,
                maxLength: 2000,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'السبب'),
              )
            : const Text('تأكيد اعتماد إثبات السداد لهذا المستحق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          EbrokerFilledButton(
            onPressed: widget.requiresReason && _reason.text.trim().length < 3
                ? null
                : () => Navigator.pop(context, _reason.text.trim()),
            child: const Text('تأكيد'),
          ),
        ],
      );
}
