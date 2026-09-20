import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/design/app_design.dart';
import '../../messages/domain/message_models.dart';
import '../data/agreement_repository.dart';
import '../domain/agreement_models.dart';
import 'agreement_forms.dart';

class ConversationAgreementCard extends ConsumerStatefulWidget {
  const ConversationAgreementCard({required this.thread, super.key});
  final MessageThreadSummary thread;

  @override
  ConsumerState<ConversationAgreementCard> createState() =>
      _ConversationAgreementCardState();
}

class _ConversationAgreementCardState
    extends ConsumerState<ConversationAgreementCard> {
  PropertyAgreement? _agreement;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(agreementRepositoryProvider).mine();
      PropertyAgreement? found;
      for (final item in rows) {
        if (item.messageThreadId == widget.thread.id) {
          found = item;
          if (item.status == 'draft' || item.status == 'accepted') break;
        }
      }
      if (!mounted) return;
      setState(() {
        _agreement = found;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    if (_busy || widget.thread.isPropertyUnavailable) return;
    final terms = await showAgreementTermsSheet(context);
    if (terms == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final agreement = await ref
          .read(agreementRepositoryProvider)
          .startAgreement(widget.thread.id, terms);
      ref.read(agreementDataRevisionProvider.notifier).state++;
      if (!mounted) return;
      setState(() => _agreement = agreement);
      await context.push('/agreements/${agreement.id}');
      if (mounted) _load();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppSurface(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.s12),
          child: LinearProgressIndicator(),
        ),
      );
    }

    final agreement = _agreement;
    if (agreement != null) {
      final revision = agreement.currentRevision;
      return AppSurface(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () async {
            await context.push('/agreements/${agreement.id}');
            if (mounted) _load();
          },
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Row(
              children: [
                const Icon(Icons.handshake_outlined),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اتفاق مرتبط بهذه المحادثة • ${agreement.statusLabel}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        '${moneyLabel(revision.agreedAmount, revision.currency)} • نسخة ${revision.revisionNumber}',
                      ),
                      if (!agreement.isAccepted)
                        Text(
                          agreement.myAccepted
                              ? 'تم تسجيل قبولك. بانتظار الطرف الآخر.'
                              : 'راجع النسخة الحالية قبل القبول.',
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
        ),
      );
    }

    if (widget.thread.isPropertyUnavailable) {
      return const SizedBox.shrink();
    }

    return AppSectionCard(
      title: 'جاهزون للاتفاق؟',
      subtitle: 'أنشئ مسودة شروط مرتبطة بهذا العقار. لا تصبح مقبولة حتى يوافق الطرفان على نفس النسخة.',
      child: AppButton(
        label: 'بدء اتفاق',
        style: AppButtonStyle.tonal,
        onPressed: _busy ? null : _start,
        expand: true,
      ),
    );
  }
}
